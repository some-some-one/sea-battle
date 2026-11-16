--!nonstrict
-- The account service of a server (hub and match alike): loads each player's profile (server/Profiles),
-- keeps their client up to date through the RemoteEvent ConquestAPI.Profile, answers the economy
-- commands that arrive through ConquestAPI.Command, and reports silver to analytics.
-- The client never names an amount or a price: it asks, the server decides from its own data.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local DataStoreService=game:GetService("DataStoreService")
local AnalyticsService=game:GetService("AnalyticsService")
local Profiles=require(script.Parent.Profiles)
local shared=game:GetService("ReplicatedStorage"):WaitForChild("SeaBattle")
local Daily=require(shared.Daily)
local Catalog=require(shared.Catalog)
local Economy=require(shared.Economy)
local Products=require(shared.Products)
local Purchases=require(script.Parent.Purchases)
local MarketplaceService=game:GetService("MarketplaceService")
local LocalizationService=game:GetService("LocalizationService")

local A={}
local remote
-- The country each player plays from (an ISO code from Roblox, kept only while on this server).
A.home={}
local prizeRandom=Random.new()
function A.lookupHome(player)
 if A.home[player.UserId]then return A.home[player.UserId]end
 local ok,code=pcall(LocalizationService.GetCountryRegionForPlayerAsync,LocalizationService,player)
 if ok and type(code)=='string'and code~=''then A.home[player.UserId]=string.upper(code)end
 return A.home[player.UserId]
end
-- Silver earned or spent, for the economy charts (no personal data: the player object is the key Roblox asks for).
local SOURCES={daily=Enum.AnalyticsEconomyTransactionType.TimedReward,match_online=Enum.AnalyticsEconomyTransactionType.Gameplay,
 match_solo=Enum.AnalyticsEconomyTransactionType.Gameplay,purchase=Enum.AnalyticsEconomyTransactionType.IAP,
 refund_duplicate=Enum.AnalyticsEconomyTransactionType.IAP,unlock=Enum.AnalyticsEconomyTransactionType.Shop,
 cosmetic=Enum.AnalyticsEconomyTransactionType.Shop}
local function logSilver(userId,delta,reason,balance)
 local player=Players:GetPlayerByUserId(userId)
 if not player or RunService:IsStudio()then return end
 pcall(function()
  AnalyticsService:LogEconomyEvent(player,delta>=0 and Enum.AnalyticsEconomyFlowType.Source or Enum.AnalyticsEconomyFlowType.Sink,
   "Silver",math.abs(delta),balance,(SOURCES[reason]or Enum.AnalyticsEconomyTransactionType.Gameplay).Name,reason)
 end)
end
local function push(userId,rec)
 local player=Players:GetPlayerByUserId(userId)
 if player and remote then remote:FireClient(player,Profiles.view(rec))end
end
-- Something besides the profile for the player's client: {payout = {lines, total}} after a match.
local function tell(userId,extra)
 local player=Players:GetPlayerByUserId(userId)
 local rec=A.profiles and A.profiles:get(userId)
 if player and remote and rec then remote:FireClient(player,Profiles.view(rec),extra)end
end
-- Solo matches under way on this server: [userId] = {at = os.clock(), difficulty, id}. The device reports
-- the result; the server knows only when the match began, and pays no more than that time allows.
local solo={}
local soloCount=0
local soloLast={}   -- [userId] = difficulty of the solo match last paid (a takeover goes on in it)
-- A custom analytics event (the starter pack shown and bought); nothing personal in it.
local function logEvent(userId,name,value)
 local player=Players:GetPlayerByUserId(userId)
 if not player or RunService:IsStudio()then return end
 pcall(function()AnalyticsService:LogCustomEvent(player,name,value or 1)end)
end
-- The store: the DataStore in a published game; in Studio it needs "Enable Studio Access to API Services"
-- and a published place, otherwise profiles live in memory until the server stops.
local function chooseStore()
 if RunService:IsStudio()then
  local ok=pcall(function()return DataStoreService:GetDataStore(Profiles.STORE):GetAsync("probe")end)
  if not ok then
   print("[Profiles] memory store (Studio without API access)")
   A.memory=true
   return Profiles.memoryStore()
  end
 end
 return Profiles.dataStore()
end
-- `event`: the RemoteEvent ConquestAPI.Profile.
function A.start(event)
 remote=event
 A.profiles=Profiles.new(chooseStore(),{changed=push,silver=logSilver})
 local function arrive(player)
  task.spawn(A.lookupHome,player)
  local rec=A.profiles:load(player.UserId)
  if rec and player.Parent then push(player.UserId,rec)end
 end
 Players.PlayerAdded:Connect(arrive)
 for _,player in ipairs(Players:GetPlayers())do task.spawn(arrive,player)end
 Players.PlayerRemoving:Connect(function(player)A.home[player.UserId]=nil;solo[player.UserId]=nil;soloLast[player.UserId]=nil;A.profiles:release(player.UserId)end)
 game:BindToClose(function()A.profiles:flushAll(20)end)
 -- Purchases for Robux (server/Purchases): granted in the profile's own write, reported only after it.
 MarketplaceService.ProcessReceipt=function(receipt)
  local ok,granted=pcall(Purchases.process,A.profiles,receipt,{granted=A.purchased,home=function(userId)return A.home[userId]end})
  if ok and granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
  if not ok then warn("[Purchases] "..tostring(granted))end
  return Enum.ProductPurchaseDecision.NotProcessedYet
 end
 task.spawn(function()while true do task.wait(5);A.profiles:flushDue()end end)
end
-- An economy command; nil when `action` is not one (the match's own commands go on as before).
function A.command(player,action,value)
 if action=="profile"then
  local rec=A.profiles:load(player.UserId)
  if not rec then return {ok=false,reason="store"}end
  return {ok=true,reason="profile",profile=Profiles.view(rec)}
 end
 if action=="daily_claim"then return A.claimDaily(player.UserId,os.time())end
 if action=="buy"then return A.buy(player.UserId,type(value)=='table'and value.id)end
 if action=="equip"then return A.equip(player.UserId,type(value)=='table'and value.slot,type(value)=='table'and value.id)end
 if action=="starter_seen"then return A.starterSeen(player.UserId,os.time())end
 if action=="takeover_use"then return A.takeoverUse(player.UserId,os.clock())end
 if action=="chest_open"then return A.openChest(player.UserId)end
 if action=="music"then return A.setMusic(player.UserId,type(value)=='table'and value.on)end
 if action=="tutorial"then return A.tutorialSeen(player.UserId)end
 if action=="solo_started"then
  local difficulty=type(value)=='table'and value.difficulty
  if difficulty~='easy'and difficulty~='hard'then difficulty='normal'end
  return A.soloStarted(player.UserId,difficulty,os.clock())
 end
 if action=="solo_result"then return A.soloResult(player.UserId,value,os.clock())end
 return nil
end
-- After a new grant for Robux: the economy charts and the starter pack's event.
function A.purchased(userId,product,info)
 local rec=A.profiles:get(userId)
 if info.kind=='unlock'and not info.refund and A.unlocksChanged then A.unlocksChanged(userId)end
 if info.refund and info.refund>0 then logSilver(userId,info.refund,"refund_duplicate",rec and rec.silver or 0)end
 if info.kind=='starter'then
  if info.silver then logSilver(userId,info.silver,"purchase",rec and rec.silver or 0)end
  logEvent(userId,"StarterPackBought")
  -- (its torpedo and cluster missile: a country already in a match has them at once)
  if info.unlocked and A.unlocksChanged then A.unlocksChanged(userId)end
  -- (what came out of it, for the client's reward window: the flag and the pattern drawn, the silver)
  tell(userId,{starter={items=info.items,silver=info.silver}})
 end
end
-- The starter pack is being shown for the first time: its 48 hours start now (kept in the record).
function A.starterSeen(userId,now)
 local rec=A.profiles:load(userId)
 if not rec then return {ok=false,reason="store"}end
 if rec.starter or not Products.available('starter_pack')then return {ok=false,reason="invalid",profile=Profiles.view(rec)}end
 local ok=A.profiles:transact(userId,function(r)
  if r.starter then return false end
  r.starter={started=now,ends=now+Products.Starter.hours*3600,used=false}
  return true
 end)
 if ok then logEvent(userId,"StarterPackShown")end
 return {ok=ok==true,reason=ok and "starter"or "invalid",profile=Profiles.view(A.profiles:get(userId)or rec)}
end
-- Solo: take command of the country that defeated you. Spends one bought credit; the new life is a new
-- solo match for the payout (the first life was paid when the country fell).
function A.takeoverUse(userId,clock)
 local difficulty=soloLast[userId]
 if not difficulty or solo[userId]then return {ok=false,reason="invalid"}end
 local ok=A.profiles:transact(userId,function(rec)
  if(rec.credits.takeover or 0)<1 then return false,'no_credit'end
  rec.credits.takeover-=1
  return true
 end)
 if ok==nil then return {ok=false,reason="store"}end
 if not ok then return {ok=false,reason="no_credit"}end
 A.soloStarted(userId,difficulty,clock)
 return {ok=true,reason="takeover",profile=Profiles.view(A.profiles:get(userId))}
end
-- Open one chest with one golden key: the server draws the item (Catalog.chestRoll) in the same write that
-- spends both, so they are never lost and never give twice. Nothing left to give: Catalog.ChestSilver instead.
local chestRandom=Random.new()
function A.openChest(userId)
 local ok,given,rec=A.profiles:transact(userId,function(r)
  if(r.credits.chest or 0)<1 then return false,'no_chest'end
  if(r.credits.key or 0)<1 then return false,'no_key'end
  r.credits.chest-=1;r.credits.key-=1
  local id=Catalog.chestRoll(r.owned,function()return chestRandom:NextNumber()end,function(n)return chestRandom:NextInteger(1,n)end)
  if id then Catalog.giveAndWear(r,id);return true,{item=id}end
  r.silver+=Catalog.ChestSilver;r.silverEarned+=Catalog.ChestSilver
  return true,{silver=Catalog.ChestSilver}
 end)
 if ok==nil then return {ok=false,reason="store"}end
 if not ok then return {ok=false,reason=given or "no_chest",profile=rec and Profiles.view(rec)}end
 if given.silver then logSilver(userId,given.silver,"chest_empty",rec and rec.silver or 0)end
 rec=A.profiles:get(userId)or rec
 return {ok=true,reason="chest",item=given.item,silver=given.silver,profile=rec and Profiles.view(rec)}
end
-- A purchase for silver. The price is the catalog's; the client names only the item.
function A.buy(userId,id)
 -- An arsenal item: opened for silver once.
 local unlock=type(id)=='string'and Catalog.Arsenal[id]
 local have=A.profiles:get(userId)
 -- (already there: say so before the price is even looked at)
 if have and type(id)=='string'and(have.unlocks[id]or have.owned[id])then return {ok=false,reason="owned",profile=Profiles.view(have)}end
 if unlock then
  local ok,why=A.profiles:spend(userId,unlock.silver,"unlock",function(rec)
   if rec.unlocks[id]then return false,'owned'end
   rec.unlocks[id]=true
  end)
  -- (opened in the middle of a match: the country has it at once)
  if ok and A.unlocksChanged then A.unlocksChanged(userId)end
  local rec=A.profiles:get(userId)
  return {ok=ok,reason=ok and "bought"or why,profile=rec and Profiles.view(rec)}
 end
 local item=type(id)=='string'and Catalog.Cosmetics[id]
 if not item or type(item.silver)~='number'then return {ok=false,reason="invalid"}end
 local ok,why=A.profiles:spend(userId,item.silver,"cosmetic",function(rec)
  if rec.owned[id]then return false,'owned'end
  rec.owned[id]=true
 end)
 local rec=A.profiles:get(userId)
 return {ok=ok,reason=ok and "bought"or why,profile=rec and Profiles.view(rec)}
end
-- The background music switch, kept in the profile (not money: written a little later).
function A.setMusic(userId,on)
 local rec=A.profiles:load(userId)
 if not rec then return {ok=false,reason="store"}end
 A.profiles:softChange(userId,function(r)r.music=on~=false end)
 return {ok=true,reason="music",profile=Profiles.view(A.profiles:get(userId))}
end
-- The newcomer's tutorial is over (done, skipped or left): not money, written a little later.
function A.tutorialSeen(userId)
 local rec=A.profiles:load(userId)
 if not rec then return {ok=false,reason="store"}end
 A.profiles:softChange(userId,function(r)r.tutorial=true end)
 return {ok=true,reason="tutorial",profile=Profiles.view(A.profiles:get(userId))}
end
-- Wear an owned cosmetic in its slot, or take it off (id == nil or false). Not money: written a little later.
function A.equip(userId,slot,id)
 if type(slot)~='string'or not Catalog.Slots[slot]then return {ok=false,reason="invalid"}end
 local rec=A.profiles:load(userId)
 if not rec then return {ok=false,reason="store"}end
 if id then
  local item=type(id)=='string'and Catalog.Cosmetics[id]
  if not item or item.kind~=slot or not rec.owned[id]then return {ok=false,reason="not_owned"}end
 else id=nil end
 A.profiles:softChange(userId,function(r)r.equipped[slot]=id end)
 return {ok=true,reason="equipped",profile=Profiles.view(A.profiles:get(userId))}
end
-- The flag and the water pattern a player's new country wears (only what they own).
function A.dress(userId,faction)
 local rec=A.profiles:get(userId)
 if not faction or not rec then return end
 faction.flag=Catalog.worn(rec,'flag');faction.pattern=Catalog.worn(rec,'pattern')
 -- The arsenal the player has opened, as the match's mask (sim/NavalArsenal).
 faction.arsenal=Catalog.mask(rec.unlocks)
end
-- Silver for a finished match, once for `payoutId` (the same id from any server is ignored), with the
-- match counted in the player's statistics. pay: Economy.payout's {lines, total}. -> granted (0 for a repeat), or nil.
-- drops: the match for Catalog.chestDrops (drawn here, in the same write, so a repeat gives nothing);
-- what fell is written into pay.chests / pay.keys for the end card.
local dropRandom=Random.new()
function A.payMatch(userId,pay,reason,payoutId,won,drops)
 local amount=math.max(0,math.floor(pay.total or 0))
 local ok,granted,rec=A.profiles:transact(userId,function(rec)
  if table.find(rec.payouts,payoutId)then return false,0 end
  Profiles.remember(rec.payouts,payoutId,Profiles.PAYOUTS)
  rec.silver+=amount;rec.silverEarned+=amount
  rec.stats.matches=(rec.stats.matches or 0)+1
  if won then rec.stats.wins=(rec.stats.wins or 0)+1 end
  if drops then
   if drops.kind=='solo'then drops.first=not rec.firstSolo;rec.firstSolo=true end
   local chests,keys=Catalog.chestDrops(drops,function()return dropRandom:NextNumber()end)
   rec.credits.chest=(rec.credits.chest or 0)+chests;rec.credits.key=(rec.credits.key or 0)+keys
   pay.chests,pay.keys=chests,keys
  end
  return true,amount
 end)
 if ok==nil then return nil end
 if not ok then return 0 end
 if amount>0 then logSilver(userId,amount,reason,rec and rec.silver or 0)end
 return granted
end
-- An online match's result, counted by this server's own simulation (SeaBattle.server calls it).
function A.payOnline(userId,result,payoutId)
 local rec=A.profiles:load(userId)
 if not rec then return nil end
 local pay=Economy.payout(result,{kind='online'},rec.boosts)
 local granted=A.payMatch(userId,pay,"match_online",payoutId,result.won,{kind='online',place=result.place,quit=result.quit,won=result.won})
 if granted and granted>0 then tell(userId,{payout=pay})end
 -- (paid after the player had left: their copy was loaded only for this)
 if not Players:GetPlayerByUserId(userId)then A.profiles:release(userId)end
 return granted,pay
end
function A.soloStarted(userId,difficulty,clock)
 soloCount+=1
 solo[userId]={at=clock,difficulty=difficulty,id=soloCount}
 return {ok=true,reason="solo_started"}
end
-- One payout for one solo match: the report is cut to its limits and to the real time since the start.
function A.soloResult(userId,report,clock)
 local started=solo[userId]
 if not started then return {ok=false,reason="invalid"}end
 solo[userId]=nil;soloLast[userId]=started.difficulty
 local rec=A.profiles:load(userId)
 if not rec then return {ok=false,reason="store"}end
 local realMinutes=(clock-started.at)/60
 local pay,result=Economy.soloPayout(report,realMinutes,started.difficulty,rec.boosts)
 local granted=A.payMatch(userId,pay,"match_solo","solo:"..game.JobId..":"..userId..":"..started.id,result.won,
  {kind='solo',difficulty=started.difficulty,won=result.won,quit=result.quit,realMinutes=realMinutes})
 if granted==nil then return {ok=false,reason="store"}end
 return {ok=true,reason="solo_paid",payout=pay,profile=Profiles.view(A.profiles:get(userId)or rec)}
end
-- Today's reward of the daily bonus (shared/Daily), with the day-7 prize; all in one write.
function A.claimDaily(userId,unixTime)
 local today=Daily.day(unixTime)
 local player=Players:GetPlayerByUserId(userId)
 local home=A.home[userId]or(player and A.lookupHome(player))
 local ok,reward,rec=A.profiles:transact(userId,function(rec)
  local daily,reward=Daily.claim(rec.daily,today)
  if not daily then return false,'claimed'end
  rec.daily=daily
  local silver=reward.silver
  if reward.prize then
   local item=Catalog.dailyPrize(rec.owned,home,function(n)return prizeRandom:NextInteger(1,n)end)
   if item then Catalog.giveAndWear(rec,item);reward.item=item
   else silver+=Daily.PrizeFallback;reward.bonus=Daily.PrizeFallback end
  end
  rec.silver+=silver;rec.silverEarned+=silver;reward.total=silver
  return true,reward
 end)
 if ok==nil then return {ok=false,reason="store"}end
 if not ok then return {ok=false,reason=reward or "claimed"}end
 logSilver(userId,reward.total,"daily",rec and rec.silver or 0)
 return {ok=true,reason="daily",reward=reward,profile=rec and Profiles.view(rec)}
end
return A
