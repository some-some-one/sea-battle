--!nonstrict
-- A player's saved profile: silver, the daily bonus, unlocks, cosmetics, purchases. Only the server
-- writes it. One record per account in the DataStore P.STORE under "u_<UserId>", shared by solo and online.
--
--  * Every change of money, purchases or the daily bonus is one UpdateAsync: the check and the change
--    happen together inside its callback (`transact`), so two servers can never both spend the same
--    silver, and a payout or a receipt with an id already in the record is not granted twice.
--  * Changes that are not money (equipped cosmetics) are `soft`: they change the server's copy at once
--    and are written a little later, or together with the next transaction, or when the player leaves.
--  * The store is injected: P.dataStore() in a published game, P.memoryStore() in Studio without access
--    to the DataStore and in tests. Both have one method, update(key, fn) -> ok, value | error.
--  * `migrate` brings an older record up to P.VERSION and keeps fields it does not know.
local DataStoreService=game:GetService("DataStoreService")

local P={}
P.STORE="SeaBattleProfiles_v1"
P.VERSION=1
P.RECEIPTS=200   -- purchase ids kept against a receipt processed twice
P.PAYOUTS=60     -- match payout ids kept against a payout granted twice
P.SOFT_DELAY=20  -- seconds before a soft change is written on its own

local function copy(v)
 if type(v)~='table'then return v end
 local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out
end
P.copy=copy
function P.key(userId)return "u_"..tostring(userId)end
function P.default(now)
 return {v=P.VERSION,silver=0,silverEarned=0,silverSpent=0,
  daily={cycleDay=0,lastClaimDay=-1,graceUsed=0,cycleStart=-1,totalClaims=0},
  unlocks={},owned={},equipped={},boosts={silver2x=false},credits={},receipts={},payouts={},
  paid=false,starter=nil,stats={matches=0,wins=0},createdAt=now,updatedAt=now,
  -- chests bought at the first price (shared/Products.chestFirstLeft)
  chestFirst=0,
  -- background music on (shared/Music; the player's switch, kept for next time)
  music=true}
end
-- An older (or empty) record brought to the current version; unknown fields stay as they are.
function P.migrate(rec,now)
 now=now or os.time()
 if type(rec)~='table'then return P.default(now)end
 local base=P.default(now)
 for k,v in pairs(base)do
  if rec[k]==nil then rec[k]=v
  elseif type(v)=='table'and type(rec[k])=='table'and k~='receipts'and k~='payouts'then
   for k2,v2 in pairs(v)do if rec[k][k2]==nil then rec[k][k2]=v2 end end
  end
 end
 if type(rec.silver)~='number'or rec.silver~=rec.silver or rec.silver<0 then rec.silver=0 end
 rec.silver=math.floor(rec.silver)
 -- (version steps go here: if rec.v<2 then ... end)
 rec.v=P.VERSION
 return rec
end
-- What the player's own client may know.
function P.view(rec)
 return {silver=rec.silver,daily=copy(rec.daily),unlocks=copy(rec.unlocks),owned=copy(rec.owned),equipped=copy(rec.equipped),
  boosts=copy(rec.boosts),credits=copy(rec.credits),paid=rec.paid==true,starter=copy(rec.starter),stats=copy(rec.stats),
  chestFirst=rec.chestFirst or 0,music=rec.music~=false}
end
local function remember(list,id,max)
 table.insert(list,id);while #list>max do table.remove(list,1)end
end
P.remember=remember

-- ---------------------------------------------------------------- stores
-- In memory: Studio without API access, and tests. `failNext` (a number) makes that many updates fail,
-- `calls` counts them.
function P.memoryStore()
 local store={data={},calls=0,failNext=0}
 function store.update(key,fn)
  store.calls+=1
  if store.failNext>0 then store.failNext-=1;return false,"memory store: injected failure"end
  local new=fn(copy(store.data[key]))
  if new~=nil then store.data[key]=copy(new)end
  return true,copy(store.data[key])
 end
 return store
end
-- The real one: UpdateAsync with retries, waiting for the request budget.
function P.dataStore(name)
 local ds=DataStoreService:GetDataStore(name or P.STORE)
 local store={}
 function store.update(key,fn)
  local lastError
  for attempt=1,4 do
   local waited=0
   while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)<1 and waited<10 do waited+=task.wait(.5)end
   local ok,value=pcall(ds.UpdateAsync,ds,key,fn)
   if ok then return true,value end
   lastError=value
   task.wait(attempt*1.5)
  end
  return false,lastError
 end
 return store
end

-- ---------------------------------------------------------------- manager
local M={};M.__index=M
-- hooks (all optional): changed(userId, rec) after any change of the server's copy;
-- silver(userId, delta, reason, balance) after silver was earned or spent.
function P.new(store,hooks)
 return setmetatable({store=store,hooks=hooks or {},cache={},soft={},dirtyAt={},loading={}},M)
end
function M:get(userId)return self.cache[userId]end
function M:_changed(userId,rec)
 self.cache[userId]=rec
 if self.hooks.changed then task.spawn(self.hooks.changed,userId,rec)end
end
-- One atomic change. fn(rec) -> ok, result: it checks and changes `rec` in place; ok == false leaves the
-- record as it was (nothing is written). It may run more than once, so it must depend on `rec` alone.
-- Returns ok, result, rec; ok == nil with result "store" when the store could not be reached.
function M:transact(userId,fn)
 local pending=self.soft[userId]
 local okFn,result
 local ok,value=self.store.update(P.key(userId),function(old)
  local rec=P.migrate(copy(old))
  if pending then for _,soft in ipairs(pending)do soft(rec)end end
  okFn,result=fn(rec)
  if okFn==false and not pending and old~=nil then return nil end
  if okFn==false then
   -- Refused: still write a new record or the waiting soft changes, without the refused change.
   rec=P.migrate(copy(old));if pending then for _,soft in ipairs(pending)do soft(rec)end end
  end
  rec.updatedAt=os.time()
  return rec
 end)
 if not ok then warn("[Profiles] write failed for "..tostring(userId)..": "..tostring(value));return nil,"store",self.cache[userId]end
 if pending and self.soft[userId]==pending then self.soft[userId]=nil;self.dirtyAt[userId]=nil end
 if type(value)=='table'then self:_changed(userId,P.migrate(value))end
 return okFn,result,self.cache[userId]
end
-- The record of a player who has just arrived (created when new).
function M:load(userId)
 if self.cache[userId]then return self.cache[userId]end
 if self.loading[userId]then
  local waited=0;while self.loading[userId]and waited<20 do waited+=task.wait(.1)end
  return self.cache[userId]
 end
 self.loading[userId]=true
 self:transact(userId,function()return true end)
 self.loading[userId]=nil
 return self.cache[userId]
end
-- Silver earned. `payoutId` (optional): the same id is granted once, whichever server asks.
-- Returns the amount granted (0 for a repeat), or nil when the store failed.
function M:addSilver(userId,amount,reason,payoutId)
 amount=math.floor(tonumber(amount)or 0)
 if not(amount>0 and amount<1e12)then return 0 end
 local ok,granted,rec=self:transact(userId,function(rec)
  if payoutId then
   if table.find(rec.payouts,payoutId)then return false,0 end
   remember(rec.payouts,payoutId,P.PAYOUTS)
  end
  rec.silver+=amount;rec.silverEarned+=amount
  return true,amount
 end)
 if ok==nil then return nil end
 if ok and self.hooks.silver then task.spawn(self.hooks.silver,userId,amount,reason,rec and rec.silver or 0)end
 return ok and granted or 0
end
-- Silver spent on something: `apply(rec)` (optional) checks the thing itself and grants it; it returns
-- false, reason to refuse. Returns true, or false and 'silver' / the reason / 'store'.
function M:spend(userId,amount,reason,apply)
 amount=math.floor(tonumber(amount)or -1)
 if not(amount>=0 and amount<1e12)then return false,'invalid'end
 local ok,why,rec=self:transact(userId,function(rec)
  if rec.silver<amount then return false,'silver'end
  if apply then
   local fine,refusal=apply(rec)
   if fine==false then return false,refusal or 'invalid'end
  end
  rec.silver-=amount;rec.silverSpent+=amount
  return true
 end)
 if ok==nil then return false,'store'end
 if ok and amount>0 and self.hooks.silver then task.spawn(self.hooks.silver,userId,-amount,reason,rec and rec.silver or 0)end
 return ok==true,why
end
-- A change that is not money: the server's copy changes now, the store a little later.
function M:softChange(userId,fn)
 local rec=self.cache[userId];if not rec then return false end
 fn(rec)
 self.soft[userId]=self.soft[userId]or {};table.insert(self.soft[userId],fn)
 self.dirtyAt[userId]=self.dirtyAt[userId]or os.clock()
 self:_changed(userId,rec)
 return true
end
function M:flush(userId)
 if not self.soft[userId]then return true end
 return self:transact(userId,function()return true end)~=nil
end
-- Called now and then: writes soft changes that have waited long enough.
function M:flushDue()
 for userId,at in pairs(self.dirtyAt)do
  if os.clock()-at>=P.SOFT_DELAY then self.dirtyAt[userId]=os.clock();task.spawn(self.flush,self,userId)end
 end
end
-- The player left: write what waits and forget the copy.
function M:release(userId)
 local ok=self:flush(userId)
 self.cache[userId]=nil;self.soft[userId]=nil;self.dirtyAt[userId]=nil
 return ok
end
-- The server is closing: everything that waits, within `seconds`.
function M:flushAll(seconds)
 local left=0
 for userId in pairs(self.soft)do left+=1;task.spawn(function()self:flush(userId);left-=1 end)end
 local waited=0
 while left>0 and waited<(seconds or 20)do waited+=task.wait(.1)end
 return left==0
end
return P
