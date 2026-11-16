--!native
--!nonstrict
-- OpenFront-derived fleet/economy adapter. © OpenFront and Contributors, AGPL-3.0; see LICENSE.
local R=require(game.ReplicatedStorage.SeaBattle.NavalRules)
local compact=require(game.ReplicatedStorage.SeaBattle.NumberFormat).compact
local M={}
-- Key of the 32×32-cell bucket (bx, by) in structureBuckets.
local function bucketKey(bx,by)return by*4096+bx end
function M.install(Game)
 function Game:distance(a,b)
  local w=self.grid.width;return math.sqrt(((a-1)%w-(b-1)%w)^2+(math.floor((a-1)/w)-math.floor((b-1)/w))^2)
 end
 function Game:notice(owner,message)
  self.events=self.events or {};table.insert(self.events,{owner=owner,text=message,time=self.time})
  if #self.events>30 then table.remove(self.events,1)end
 end
 function Game:activeStructure(s)return not s.dead and s.ready<=self.time end
 function Game:nearStructures(cell,radius)
  -- (buckets of 32×32 cells under numeric keys, distances worked out here: fighters ask this every
  -- step over a radius of a hundred cells, 81 buckets, and string keys were most of a step's cost)
  local w=self.grid.width;local out={};local r=math.ceil(radius/32)
  local cx,cy=(cell-1)%w,(cell-1)//w;local x,y=cx//32,cy//32
  local buckets,r2=self.structureBuckets,radius*radius
  for yy=y-r,y+r do for xx=x-r,x+r do
   local list=buckets[bucketKey(xx,yy)]
   if list then for _,s in ipairs(list)do
    if not s.dead then
     local sx,sy=(s.cell-1)%w,(s.cell-1)//w
     if(cx-sx)^2+(cy-sy)^2<=r2 then table.insert(out,s)end
    end
   end end
  end end;return out
 end
 -- Structure mutations bump the revision; network sync and the level cache follow it.
 function Game:structuresChanged()
  self.structureRevision=(self.structureRevision or 0)+1;self.levelCache=nil
 end
 -- One scan per simulation time step instead of one per country, kind and caller.
 function Game:levels(owner,kind,active)
  local cache=self.levelCache
  if not cache or cache.revision~=self.structureRevision or cache.time~=self.time or cache.count~=#self.structures then
   cache={revision=self.structureRevision,time=self.time,count=#self.structures,all={},ready={}}
   for _,s in ipairs(self.structures)do if not s.dead then
    local key=s.owner..':'..s.kind
    cache.all[key]=(cache.all[key]or 0)+s.level
    if self:activeStructure(s)then cache.ready[key]=(cache.ready[key]or 0)+s.level end
   end end
   self.levelCache=cache
  end
  return(active and cache.ready or cache.all)[owner..':'..kind]or 0
 end
 function Game:cap(owner)local f=self.factions[owner];return R.cap(f.count,self:levels(owner,'port',true))*(f.bot and R.difficulty(self.settings.difficulty).cap or 1)end
 function Game:shoreAnchor(owner,cell)
  if not R.cell(cell,self.grid.count)or self.grid:isWater(cell)then return nil end
  for _,n in ipairs(self.grid:neighborIds(cell))do
   if self.grid:isWater(n)and self:owner(n)==owner then return n end
  end
 end
 function Game:newStructure(owner,kind,cell,free,water)
  local s={id=#self.structures+1,owner=owner,kind=kind,cell=cell,level=1,ready=free and self.time or self.time+R.Buildings[kind].seconds,
   nextTrade=self.time+8,nextShot=0,ammo={},paid=not free,water=water}
  if kind=='airport'then s.land=cell end
  table.insert(self.structures,s);self.structureAt[cell]=s
  local w=self.grid.width;local key=bucketKey(((cell-1)%w)//32,((cell-1)//w)//32)
  self.structureBuckets[key]=self.structureBuckets[key]or {};table.insert(self.structureBuckets[key],s)
  self:structuresChanged();return s
 end
 function Game:buildingCost(owner,kind)
  local f=self.factions[owner];local count=math.min(self:levels(owner,kind),f.built[kind]or 0)
  if kind=='airport'or kind=='oil'or kind=='gas'then
   count=0;for _,k in ipairs({'airport','oil','gas'})do count+=math.min(self:levels(owner,k),f.built[k]or 0)end
  end
  return R.cost(kind,count)
 end
 function Game:insideBotBuildArea(cell)
  if not R.cell(cell,self.grid.count)then return false end
  local c=self.grid:getCell(cell);local margin=R.BotBuildEdgeMargin
  return c.x>margin and c.y>margin and c.x<=self.grid.width-margin and c.y<=self.grid.height-margin
 end
 -- Why a building of this kind cannot stand on this cell (nil when it can), plus its shore anchor.
 -- Any two buildings keep BuildSpacing; two of the same kind keep SameKindSpacing,
 -- so one spot never collects a stack of ports that read as a single icon on the map.
 function Game:siteError(owner,kind,cell)
  local info=R.Buildings[kind]
  local water
  if info.land then
   if self.grid:isWater(cell)then return 'shore_land_required'end
   water=self:shoreAnchor(owner,cell)
   if not water then return 'own_coast_required'end
  elseif not self.grid:isWater(cell)or self:owner(cell)~=owner then return 'own_water_required'end
  if self.structureAt[cell]and not self.structureAt[cell].dead then return 'occupied'end
  for _,s in ipairs(self:nearStructures(cell,R.SameKindSpacing))do
   if s.kind==kind or self:distance(cell,s.cell)<=R.BuildSpacing then return 'too_close'end
  end
  return nil,water
 end
 -- A tap rarely hits the exact pixel: take the nearest valid cell within `reach` of it.
 function Game:buildSite(owner,kind,cell,reach)
  local err,water=self:siteError(owner,kind,cell)
  if not err or not reach or reach<1 then return err==nil and cell or nil,err,water end
  local w=self.grid.width;local x,y=(cell-1)%w,(cell-1)//w;local best,bestWater,bestDistance
  reach=math.min(math.floor(reach),R.BuildSnap)
  for dy=-reach,reach do for dx=-reach,reach do
   local d=dx*dx+dy*dy;local nx,ny=x+dx,y+dy
   if d<=reach*reach and(not bestDistance or d<bestDistance)and nx>=0 and nx<w and ny>=0 and ny<self.grid.height then
    local id=ny*w+nx+1;local e,anchor=self:siteError(owner,kind,id)
    if not e then best,bestWater,bestDistance=id,anchor,d end
   end
  end end
  if best then return best,nil,bestWater end
  return nil,err
 end
 function Game:build(owner,kind,cell,reach)
  local info=R.Buildings[kind];local f=self.factions[owner]
  if not info or not f or not f.alive or not R.cell(cell,self.grid.count)then return false,'invalid'end
  -- (an arsenal building needs its unlock)
  if info.arsenal and not self:has(owner,info.arsenal)then return false,'locked'end
  if f.bot and not self:insideBotBuildArea(cell)then return false,'map_edge'end
  local site,err,water=self:buildSite(owner,kind,cell,not f.bot and reach or nil)
  if not site then return false,err end
  if f.bot and not self:insideBotBuildArea(site)then return false,'map_edge'end
  local price=self:buildingCost(owner,kind)
  if f.gold<price then return false,'gold'end
  f.gold-=price;f.built[kind]=(f.built[kind]or 0)+1;self:newStructure(owner,kind,site,false,water)
  return true,'building'
 end
 -- (asked for every cell a front takes: the ready defence posts of each owner are listed once per time
 -- step, like levels(), instead of searching the structure buckets each time)
 function Game:fortified(owner,cell)
  local cache=self.defenseCache
  if not cache or cache.revision~=self.structureRevision or cache.time~=self.time or cache.count~=#self.structures then
   -- (by owner, then in buckets of 32×32 cells: DefenseRange is under 32, so the 3×3 buckets around a
   -- cell hold every post that can reach it; a country with dozens of posts asked them all per cell)
   cache={revision=self.structureRevision,time=self.time,count=#self.structures,by={}}
   local w=self.grid.width
   for _,s in ipairs(self.structures)do
    if s.kind=='defense'and self:activeStructure(s)then
     local buckets=cache.by[s.owner];if not buckets then buckets={};cache.by[s.owner]=buckets end
     local key=bucketKey(((s.cell-1)%w)//32,((s.cell-1)//w)//32)
     local list=buckets[key];if not list then list={};buckets[key]=list end;table.insert(list,s)
    end
   end
   self.defenseCache=cache
  end
  local buckets=cache.by[owner];if not buckets then return false end
  local w=self.grid.width;local bx,by=((cell-1)%w)//32,((cell-1)//w)//32
  for yy=by-1,by+1 do for xx=bx-1,bx+1 do
   local list=buckets[bucketKey(xx,yy)]
   if list then for _,s in ipairs(list)do if self:distance(cell,s.cell)<=R.DefenseRange then return true end end end
  end end
  return false
 end
 -- Ends one order (`enemy`: its target, 0 for neutral expansion) or, without `enemy`, all of them.
 -- With a penalty (a retreat) 75% of the force comes home two seconds later.
 function Game:stop(owner,penalty,reason,enemy)
  local f=self.factions[owner];if not f then return end
  local orders=Game.ordersOf(f);local list={}
  if enemy~=nil then if orders[enemy]then list={enemy}end else for e in pairs(orders)do table.insert(list,e)end end
  if #list==0 then return end
  for _,e in ipairs(list)do
   local order=orders[e];orders[e]=nil
   local survivors=math.max(0,order.fleet or 0)*(penalty and .75 or 1)
   if penalty and survivors>0 then table.insert(self.returns,{owner=owner,amount=survivors,at=self.time+2})
   else f.fleet=math.min(self:cap(owner),f.fleet+survivors)end
  end
  f.lastOrderEnd=reason
 end
 function Game:conquestCost(f,order,id)
  local enemy=self:owner(id);local defender=enemy>0 and self.factions[enemy]or nil
  if defender then
   if self.time<(defender.protectedUntil or 0)or self:allied(f.id,enemy)then return nil end
   defender.traitorActive=(defender.traitorUntil or 0)>self.time
  end
  local fortified=defender and self:fortified(enemy,id)
  local losses,defense,fraction=R.battle(order.fleet,f,defender,math.max(1,order.tickBorder or order.border or 1),fortified,self.fallout[id]and self.fallout[id]>self.time)
  return losses,defense,fraction,fortified
 end
 local NONE=table.freeze({})
 function Game:onOwnership(id,old,new)
  -- (a table only when a building is there: this runs for every captured cell)
  local affected=nil
  local at=self.structureAt
  local direct=at[id];if direct then affected={direct}end
  local n1,n2,n3,n4=self.grid:nb4(id)
  for k=1,4 do
   local land=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
   local s=land>0 and at[land]
   if s and s.water==id then affected=affected or {};table.insert(affected,s)end
  end
  affected=affected or NONE
  for _,s in ipairs(affected)do if not s.dead then
   if new==0 or s.kind=='defense'then s.dead=true;self.structureAt[s.cell]=nil
   else s.owner=new end -- captured buildings change hands as they are, no new construction
  end end
  if #affected>0 then self:structuresChanged()end
  if old>0 and not self.factions[old].alive then
   local victim=self.factions[old]
   -- For the match results (Game:matchResult): when the country fell and who finished it off.
   if self.phase=='playing'and not self.demo and not victim.diedAt then
    victim.diedAt=self.time
    if new>0 then victim.killedBy=new;self.factions[new].kills=(self.factions[new].kills or 0)+1 end
   end
   if new>0 then
    local award=victim.bot and (victim.gold or 0)or victim.hasAttacked and (victim.gold or 0)*.5 or 0
    self.factions[new].gold+=math.floor(award);self:notice(new,'Victory over '..victim.name..': +'..compact(award)..' gold')
    -- The conqueror inherits the defeated country's fighters, which keep patrolling in the new colour.
    local taken=0
    for _,u in pairs(self.units or {})do if u.owner==old and u.kind=='fighter'then u.owner=new;taken+=1 end end
    if taken>0 then self:notice(new,'Fighters joined you: '..taken)end
   end
   victim.gold=0;victim.fleet=0
  end
 end

 local reset=Game.reset
 function Game:reset(seed)
  self.resetting=true;reset(self,seed)
  self.structures={};self.structureAt={};self.structureBuckets={};self.units={};self.nextUnit=0;self:structuresChanged()
  self.rail=nil;self.railRevision=(self.railRevision or 0)+1;self.nextRailCheck=0
  self.personasAssigned=false;self.returns={};self.fallout={};self.events={};self.clients={};self.alliances={};self.requests={};self.wars={};self.mirvs=0
  self.tradeClock=0;self.economyClock=0;self.winner=nil;self.record={};self.recordFrames={}
  self.settings=self.settings or {difficulty='normal',mode='solo',teams=false};self.demo=false;self.buildPace=1;self.maxBuildings=nil;self.maxTotal=nil;self.countdownEnds=nil
  for _,f in ipairs(self.factions)do
   f.gold=R.StartGold;f.fleet=f.bot and R.difficulty(self.settings.difficulty).start or R.StartFleet;f.ratio=R.AttackShare;f.built={};f.peak=f.count
   f.protectedUntil=R.StartingProtection;f.traitorUntil=0;f.donationAt=0;f.nextBuild=8+self.random:NextNumber(0,20);f.nextDiplomacy=15
   -- Personal saving margin: equal incomes must not make every bot buy its port in the same second.
   f.thrift=f.bot and self.random:NextNumber(0,.6)or 0
   f.team=self.settings.teams and(f.id%2+1)or f.id;f.hasAttacked=false;f.retaliation={};f.graceJitter=self.random:NextNumber(0,90)
  end
  self.resetting=false
 end
 function Game:initHuman(f,user)
  self.clients[user]=f.id;self.controller=self.controller or user
  f.kills=0;f.diedAt=nil;f.killedBy=nil;f.joinedAt=self.time;f.peakBase=nil
  f.gold=R.StartGold;f.fleet=R.StartFleet;f.ratio=R.AttackShare;f.built={};f.protectedUntil=self.time+R.StartingProtection
  f.team=self.settings.teams and(f.id%2+1)or f.id;f.peak=f.count;f.donationAt=0;f.traitorUntil=0;f.hasAttacked=false;f.retaliation={};f.humanGraceUntil=self.time+R.difficulty(self.settings.difficulty).grace
 end
 -- Fleet away from home (attack, landing transports, retreat on its way back) per country.
 -- It still counts against the cap, so home + away never exceeds it.
 function Game:awayFleet()
  local away={}
  for _,f in ipairs(self.factions)do local n=self:orderFleet(f);if n>0 then away[f.id]=n end end
  for _,u in pairs(self.units)do if u.kind=='transport'and u.hp>0 then away[u.owner]=(away[u.owner]or 0)+(u.fleet or 0)end end
  for _,a in ipairs(self.returns)do away[a.owner]=(away[a.owner]or 0)+a.amount end
  return away
 end
 function Game:fleetGrowthPerSecond(owner,cap,away)
  local f=self.factions[owner]
  if not f or not f.alive or self.phase~='playing'then return 0 end
  if away==nil then away=self:awayFleet()[owner]end
  cap=cap or self:cap(owner);away=math.max(0,away or 0)
  -- Growth follows the whole fleet, so a big attack slows recruiting at home.
  local total=f.fleet+away
  local rate=math.max(0,R.growth(total,cap))/R.Tick
  return rate*(f.bot and R.difficulty(self.settings.difficulty).growth or 1)
 end
 function Game:economyTick(dt)
  self:batteryTick()
  local away=self:awayFleet()
  for _,f in ipairs(self.factions)do if f.alive then
   local cap=self:cap(f.id);local out=away[f.id]or 0;local growth=self:fleetGrowthPerSecond(f.id,cap,out)
   f.gold+=R.GoldPerSecond*dt;f.peak=math.max(f.peak,f.count)
   -- Never shrink the home fleet here: only stop recruiting once home + away reach the cap.
   if growth>0 then f.fleet=math.min(f.fleet+growth*dt,math.max(f.fleet,cap-out))end
   if f.fleet>cap then f.fleet=cap end
  end end
  for i=#self.returns,1,-1 do local a=self.returns[i];if a.at<=self.time then
   local f=self.factions[a.owner];if f and f.alive then f.fleet=math.min(self:cap(a.owner),f.fleet+a.amount)end;table.remove(self.returns,i)
  end end
 end
 -- Countries attacking this bot right now.
 function Game:attackersOf(owner)
  local out={};for _,e in ipairs(self.factions)do if e.alive and Game.ordersOf(e)[owner]then table.insert(out,e)end end;return out
 end
 -- What a bot should save for next: economy first (ports, stations), then aircraft and missiles as it grows.
 -- Defense posts mostly while someone is attacking; how many depends on the difficulty.
 function Game:botBuildGoal(f)
  local count=f.count;local lv=function(k)return self:levels(f.id,k)end
  if lv('port')==0 then return 'port'end
  local wants={};local bias=R.botKind(f).build
  -- The bot's kind tilts the goals (R.BotKinds[..].build): 0 drops a building, >1 favours it.
  local function want(kind,have,target,weight)
   local k=bias[kind]or 1
   if k>0 and have<target then table.insert(wants,{kind,weight*k*(target-have)})end
  end
  want('port',lv('port'),math.clamp(1+count//3000,1,5),3)
  want(self.random:NextNumber()<.5 and'oil'or'gas',lv('oil')+lv('gas'),math.clamp(1+count//1500,2,10),3)
  want('airport',lv('airport'),count>=1500 and(count>=8000 and 2 or 1)or 0,2)
  want('silo',lv('silo'),self.time>=420 and count>=3000 and(count>=12000 and 2 or 1)or 0,2)
  want('sam',lv('sam'),self.time>=600 and count>=6000 and 1 or 0,1)
  local threatened=#self:attackersOf(f.id)>0
  -- Defence posts by difficulty (R.Difficulties[...].defense): many while attacked, a few otherwise.
  local d=R.difficulty(self.settings.difficulty).defense
  local target
  if threatened then target=math.clamp(d.threat[1]+count//d.threat[2],d.threat[1],d.threat[3])
  elseif count<d.calm[1]then target=0
  else target=math.min(d.calm[3],1+(d.calm[2]>0 and(count-d.calm[1])//d.calm[2]or 0))end
  want('defense',lv('defense'),target,threatened and 4 or 1)
  if #wants==0 then return nil end
  local total=0;for _,w in ipairs(wants)do total+=w[2]end
  local roll=self.random:NextNumber()*total
  for _,w in ipairs(wants)do roll-=w[2];if roll<=0 then return w[1]end end
  return wants[#wants][1]
 end
 -- Defense posts go on own water facing an attacker (or any border when nobody attacks).
 function Game:botFrontSite(f)
  local enemies={};for _,e in ipairs(self:attackersOf(f.id))do enemies[e.id]=true end
  local fallback
  for cell in pairs(f.frontier)do
   local other=self:owner(cell)
   if other>0 and other~=f.id then
    for _,n in ipairs(self.grid:neighborIds(cell))do
     if self:owner(n)==f.id and self:insideBotBuildArea(n)and not self:siteError(f.id,'defense',n)then
      if enemies[other]then return n end;fallback=fallback or n
     end
    end
   end
  end
  return next(enemies)==nil and fallback or nil
 end
 function Game:botEconomy(f)
  if self.time<(f.nextBuild or 0)then return end;f.nextBuild=self.time+self.random:NextNumber(4,9)*(self.buildPace or 1)
  -- The lobby's demo keeps every bot to a few buildings (Game:startDemo).
  if self.maxTotal and #self.structures>=self.maxTotal then return end
  if self.maxBuildings then
   local n=0;for _,s in ipairs(self.structures)do if s.owner==f.id then n+=1 end end
   if n>=self.maxBuildings then return end
  end
  local pick
  local airports=self:levels(f.id,'airport')
  if self.settings.difficulty=='easy'and self.random:NextNumber()<.5 then return end
  -- Keep one goal and save up for it, so cheap defense posts do not eat the whole budget.
  if not f.buildGoal or self.time>(f.buildGoalUntil or 0)then f.buildGoal=self:botBuildGoal(f);f.buildGoalUntil=self.time+60 end
  local kind=f.buildGoal
  -- Skip the site search until this bot has saved its own margin above the price.
  local affordable=kind and f.gold>=self:buildingCost(f.id,kind)*(1+(f.thrift or 0))
  if affordable and kind=='defense'then pick=self:botFrontSite(f)
  elseif affordable then
   -- Check a random sample of at most BotSiteChecks cells: a full scan of a large country took
   -- a quarter of a second and stalled the whole server every few seconds.
   local land=R.Buildings[kind].land;local pool=land and(f.shore or {})or f.owned
   local size=0;if land then for _ in pairs(pool)do size+=1 end else size=f.count end
   local chance=math.min(1,R.BotSiteChecks/math.max(1,size))
   for cell in pairs(pool)do
    if self.random:NextNumber()<chance then
     if land then
      for _,id in ipairs(self.grid:neighborIds(cell))do
       if not self.grid:isWater(id)and self:insideBotBuildArea(id)and not self:siteError(f.id,kind,id)then pick=id;break end
      end
     elseif self:insideBotBuildArea(cell)and not self:siteError(f.id,kind,cell)then pick=cell end
     if pick then break end
    end
   end
  end
  if pick and self:build(f.id,kind,pick)then f.buildGoal=nil end
  local kindRules=R.botKind(f)
  if f.gold>1000000 and kindRules.missiles then
   local enemy
   for _,other in ipairs(self.factions)do if other.alive and other.id~=f.id and not self:allied(f.id,other.id)and self:mayBotAttack(f.id,other.id)then
    if not enemy or self:distance(f.startCell,other.startCell)<self:distance(f.startCell,enemy.startCell)then enemy=other end
   end end
   if enemy then
    local strike=self:targetCell(enemy.id,false)
    if strike then for _,s in ipairs(self.structures)do if s.owner==f.id and s.kind=='silo'and self:activeStructure(s)then
     self:launchMissile(f.id,s.id,strike,f.gold>5000000 and 'hydrogen'or 'atom');break
    end end end
    if not f.airPlanning and airports>0 and f.fleet>10000 and self.random:NextNumber()<.15 then
     f.airPlanning=true;local epoch=self.epoch
     task.spawn(function()
      local ok,err=pcall(function()
       for _,s in ipairs(self.structures)do if epoch~=self.epoch then return end
        local landing=self:targetCell(enemy.id,true)
        if landing and s.owner==f.id and s.kind=='airport'and self:activeStructure(s)then self:transport(f.id,s.id,landing);break end
       end
      end)
      f.airPlanning=false;if not ok then warn(err)end
     end)
    end
   end
  end
  if f.gold>300000 and airports>0 and self.random:NextNumber()<.3*kindRules.fighters then
   for _,s in ipairs(self.structures)do if s.owner==f.id and s.kind=='airport'and self:activeStructure(s)then self:launchFighter(f.id,s.id);break end end
  end
 end
 -- A cell the enemy owns now: its start if still held, otherwise a sampled (coastal) cell.
 function Game:targetCell(owner,coastal)
  local f=self.factions[owner];if not f or not f.alive then return nil end
  if f.startCell and self:owner(f.startCell)==owner and(not coastal or self:landEnd(f.startCell))then return f.startCell end
  local skip=self.random:NextInteger(0,63);local fallback
  for id in pairs(coastal and f.shore or f.owned)do
   if self:owner(id)==owner then fallback=id;if skip<=0 then return id end;skip-=1 end
  end
  return fallback
 end
 function Game:publicStructures()
  local result={};for _,s in ipairs(self.structures)do if not s.dead then table.insert(result,{id=s.id,owner=s.owner,kind=s.kind,cell=s.cell,level=s.level,ready=s.ready,land=s.land,water=s.water,reload=(s.kind=='sam'or s.kind=='silo')and(s.nextShot or 0)>self.time and s.nextShot or nil})end end;return result
 end
end
return M
