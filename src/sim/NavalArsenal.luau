--!nonstrict
-- The arsenal in a match (shared/Catalog: things a player opens for silver; Robux only opens them
-- sooner). Our own rules, the same on the server and in a solo match on the device:
--  * a country carries a mask of what its player has opened (`f.arsenal`, Catalog.mask); `Game:has`
--    asks it. Bots have none: for now they play without the arsenal, whatever people have bought.
--  * mobilisation — gold for a fifth of the fleet cap at once, then a pause (R.Mobilize);
--  * coastal battery — a building on the owner's own water (2026-11-11: anywhere on it, by the author's
--    request; it stood on the shore before) that shells the fleet of a foreign country with water in range,
--    never an ally's or a protected start's (R.Battery);
--  * fast reload — platforms and missile defences reload in half the time;
--  * torpedo, cluster missile, bombers — R.Weapons.torpedo / cluster / bomb (the cluster's bomblets and
--    the bombers' way past missile defences are handled here; the torpedo's water line in NavalAviation).
local shared=game.ReplicatedStorage.SeaBattle
local R=require(shared.NavalRules)
local Catalog=require(shared.Catalog)
local compact=require(shared.NumberFormat).compact
local M={}
function M.install(Game)
 function Game:has(owner,key)
  local f=self.factions[owner]
  return f~=nil and Catalog.unlocked(f.arsenal,key)
 end
 -- Seconds until a platform or a missile defence can fire again.
 function Game:reloadTime(s)return R.reload(s.kind,s.level,self:has(s.owner,'reload2x'))end
 -- Mobilisation: how much fleet it would add now and what that costs.
 function Game:mobilizeOffer(owner)
  local f=self.factions[owner];if not f then return 0,0 end
  local cap=self:cap(owner);local away=self:awayFleet()[owner]or 0
  local gain=math.floor(math.min(cap*R.Mobilize.Share,math.max(0,cap-f.fleet-away)))
  return gain,math.ceil(gain*R.Mobilize.GoldPerFleet)
 end
 function Game:mobilize(owner)
  local f=self.factions[owner]
  if not f or not f.alive then return false,'invalid'end
  if not self:has(owner,'mobilize')then return false,'locked'end
  if(f.mobilizeAt or 0)>self.time then return false,'cooldown'end
  local gain,price=self:mobilizeOffer(owner)
  if gain<1 then return false,'fleet_full'end
  if f.gold<price then return false,'gold'end
  f.gold-=price;f.fleet+=gain;f.mobilizeAt=self.time+R.Mobilize.Cooldown
  self:notice(owner,'Extra fleet: +'..compact(gain))
  return true,'mobilized'
 end
 -- The foreign country a battery shells now: the one with the most water in range (sampled on a coarse
 -- lattice), allies and protected starts left alone. nil when there is none.
 function Game:batteryTarget(s)
  local grid=self.grid;local w,h=grid.width,grid.height
  local c=grid:getCell(s.cell);local B=R.Battery;local r2=B.Range*B.Range
  local seen={};local cells={};local best,bestCount
  for dy=-B.Range,B.Range,B.Step do
   for dx=-B.Range,B.Range,B.Step do
    local x,y=c.x+dx,c.y+dy
    if dx*dx+dy*dy<=r2 and x>=1 and y>=1 and x<=w and y<=h then
     local id=(y-1)*w+x;local o=self:owner(id)
     if o>0 and o~=s.owner then seen[o]=(seen[o]or 0)+1;cells[o]=cells[o]or {};table.insert(cells[o],id)end
    end
   end
  end
  for o,count in pairs(seen)do
   local e=self.factions[o]
   -- (a battery a bot has captured keeps the bots' own peace with people)
   if e and e.alive and not self:allied(s.owner,o)and self.time>=(e.protectedUntil or 0)
    and(not self.factions[s.owner].bot or self:mayBotAttack(s.owner,o))and(not bestCount or count>bestCount)then best,bestCount=o,count end
  end
  -- (and one of its cells in range, where the shell is drawn falling)
  return best,best and cells[best][self.random:NextInteger(1,#cells[best])]
 end
 function Game:batteryTick()
  if self.time<(self.nextBattery or 0)then return end
  self.nextBattery=self.time+1
  for _,s in ipairs(self.structures)do
   if s.kind=='battery'and not s.dead and self:activeStructure(s)and(s.nextShot or 0)<=self.time then
    s.nextShot=self.time+R.Battery.Interval
    local target,cell=self:batteryTarget(s)
    if target then
     local e=self.factions[target]
     local loss=math.min(e.fleet,math.max(R.Battery.Min,e.fleet*R.Battery.Share))
     e.fleet-=loss
     self.factions[s.owner].hasAttacked=true;self:recordHostility(s.owner,target)
     -- The shot is seen: a shell flies from the battery to the target's water and bursts there.
     if cell then self:unit(s.owner,'missile',s.cell,nil,{weapon='shell',target=cell,start=s.cell,flight=0,duration=.8,hp=1})end
     -- One notice per pair every 20 s at most, to both sides (with what this shot took).
     self.batteryNotice=self.batteryNotice or {}
     local key=s.owner..':'..target
     if self.time-(self.batteryNotice[key]or -1e9)>20 then
      self.batteryNotice[key]=self.time
      self:notice(target,'Coastal battery of '..self.factions[s.owner].name..' is shelling your fleet')
      self:notice(s.owner,'Coastal battery hits '..e.name..'\'s fleet: −'..compact(loss)..' per shot')
     end
    end
   end
  end
 end
 -- The cluster missile at its aim: an atom blast there, and its bomblets for water around it (within
 -- `spread` cells, `gap` apart), each a small warhead of its own that a missile defence can down.
 function Game:splitCluster(u)
  local spec=R.Weapons[u.weapon];local grid=self.grid;local w,h=grid.width,grid.height
  self:blast(u.owner,u.target,u.weapon)
  local c=grid:getCell(u.target);local placed={c};local gap2=spec.gap*spec.gap;local made=0
  for _=1,400 do
   if made>=spec.bomblets then break end
   local a=self.random:NextNumber()*math.pi*2;local r=spec.outer+(spec.spread-spec.outer)*math.sqrt(self.random:NextNumber())
   local x,y=c.x+math.floor(math.cos(a)*r+.5),c.y+math.floor(math.sin(a)*r+.5)
   if x>=1 and y>=1 and x<=w and y<=h then
    local id=(y-1)*w+x
    if grid:isWater(id)and self:owner(id)~=u.owner then
     local free=true
     for _,p in ipairs(placed)do if(p.x-x)^2+(p.y-y)^2<gap2 then free=false;break end end
     if free then
      made+=1;table.insert(placed,{x=x,y=y})
      self:unit(u.owner,'missile',u.target,nil,{weapon='bomblet',target=id,start=u.target,flight=0,duration=1+self.random:NextNumber(),hp=1})
     end
    end
   end
  end
 end
 -- Whether a missile defence lets this missile pass: bombers get past each defence with the chance
 -- `evade`, decided once for each defence they meet.
 function Game:evades(u,s)
  local spec=R.Weapons[u.weapon]
  if not spec or not spec.evade then return false end
  u.dodged=u.dodged or {}
  if u.dodged[s.id]==nil then u.dodged[s.id]=self.random:NextNumber()<spec.evade end
  return u.dodged[s.id]
 end
 -- Bombers leave from the owner's ready airport nearest to the target, within the weapon's range of it.
 function Game:launchBombers(owner,target,kind)
  local spec=R.Weapons[kind];local f=self.factions[owner]
  if not R.cell(target,self.grid.count)or not self.grid:isWater(target)then return false,'water_required'end
  local enemy=self:owner(target)
  if enemy==owner or(enemy>0 and self:allied(owner,enemy))then return false,'invalid'end
  if enemy>0 and(self.time<self.factions[enemy].protectedUntil or(f.bot and not self:mayBotAttack(owner,enemy)))then return false,'protected'end
  local any=self:nearestStructure(owner,'airport',target)
  if not any then return false,'airport_required'end
  local s=self:nearestStructure(owner,'airport',target,function(a)return(a.nextShot or 0)<=self.time and self:distance(a.cell,target)<=spec.range end)
  if not s then
   local inRange=self:nearestStructure(owner,'airport',target,function(a)return self:distance(a.cell,target)<=spec.range end)
   return false,inRange and 'not_ready'or 'range'
  end
  if f.gold<spec.cost then return false,'gold'end
  f.gold-=spec.cost;s.nextShot=self.time+spec.reload;self:structuresChanged();f.hasAttacked=true
  if enemy>0 then self:recordHostility(owner,enemy)end
  self:unit(owner,'missile',s.cell,nil,{weapon=kind,target=target,start=s.cell,flight=0,duration=math.max(3,self:distance(s.cell,target)/22),hp=1})
  return true,'launched'
 end
end
return M
