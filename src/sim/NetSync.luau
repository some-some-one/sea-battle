--!native
--!nonstrict
-- Network state: ownership deltas every step, shared state at a slower cadence,
-- prices and attack intel only for the player they belong to.
local shared=game.ReplicatedStorage.SeaBattle
local P=require(shared.Protocol)
local R=require(shared.NavalRules)
local M={}
function M.install(Game)
 -- Cell changes since the previous call, deduplicated and packed into a buffer.
 function Game:changes()
  local dirty=self.dirty;self.dirty={}
  local latest,order={},{}
  for k=1,#dirty,2 do local id=dirty[k];if latest[id]==nil then table.insert(order,id)end;latest[id]=dirty[k+1]end
  local cells=buffer.create(#order*P.CellBytes)
  for i,id in ipairs(order)do
   buffer.writeu32(cells,(i-1)*P.CellBytes,id);buffer.writeu8(cells,(i-1)*P.CellBytes+4,latest[id])
  end
  return {epoch=self.epoch,revision=self.revision,phase=self.phase,time=self.time,cells=cells}
 end
 function Game:packedRoster()
  local rows,keys={},{}
  for _,f in ipairs(self.factions)do
   local row=P.pack(f,P.RosterFields);table.insert(rows,row);table.insert(keys,P.signature(row))
  end
  return rows,table.concat(keys,';')
 end
 function Game:packedFactionRows()
  local rows={};local flying=self:transit();local away=self:awayFleet()
  for _,f in ipairs(self.factions)do table.insert(rows,{f.id,P.pack(self:publicFaction(f,flying[f.id],away[f.id]or 0),P.FactionFields)})end
  return rows
 end
 function Game:packedStructures()
  local rows={};for _,s in ipairs(self:publicStructures())do table.insert(rows,P.pack(s,P.StructureFields))end;return rows
 end
 function Game:packedUnits()
  local rows={};for _,u in ipairs(self:publicUnits())do table.insert(rows,P.pack(u,P.UnitFields))end;return rows
 end
 function Game:sharedState()
  local requests={};for _,q in pairs(self.requests)do table.insert(requests,{from=q.from,to=q.to,expires=q.expires})end
  -- UserIds become string keys: sparse numeric dictionaries do not survive remotes reliably.
  local clients={};for user,id in pairs(self.clients)do clients[tostring(user)]=id end
  return {settings=self.settings,clients=clients,alliances=self.alliances,requests=requests,events=self.events,
   winner=self.winner,controller=self.controller,mirvs=self.mirvs,countdownEnds=self.countdownEnds,maxHumans=R.MaxHumans}
 end
 -- Active fronts of one country: its own targeted attack and every attack aimed at it.
 -- Loss per pixel uses the live battle formula, so the client can say whether the force suffices.
 function Game:frontInfo(owner)
  local f=self.factions[owner];local out={}
  local mine=f and Game.ordersOf(f)or {}
  for enemy,order in pairs(mine)do
   local e=enemy>0 and self.factions[enemy]
   if e and e.alive then
    local loss=R.battle(order.fleet,f,e,math.max(1,order.tickBorder or order.border or 1),false,false)
    local o=Game.ordersOf(e)[owner];local counter=o and o.fleet or 0
    table.insert(out,P.pack({enemy=e.id,mode='attack',mine=math.floor(order.fleet),theirs=math.floor(e.fleet),loss=math.max(1,math.floor(loss)),
     cells=e.count,counter=math.floor(counter)},P.FrontFields))
   end
  end
  for _,e in ipairs(self.factions)do
   local o=e.alive and Game.ordersOf(e)[owner]
   if o and not mine[e.id]then
    local loss=R.battle(o.fleet,e,f,math.max(1,o.tickBorder or o.border or 1),false,false)
    table.insert(out,P.pack({enemy=e.id,mode='defense',mine=math.floor(f.fleet),theirs=math.floor(o.fleet),loss=math.max(1,math.floor(loss)),
     cells=f.count,counter=0},P.FrontFields))
   end
  end
  return out
 end
 function Game:privateState(owner,full)
  local f=self.factions[owner];if not f then return nil end
  local flying=self:transit()
  local out={owner=owner,row=P.pack(self:publicFaction(f,flying[owner],self:awayFleet()[owner]or 0),P.FactionFields),fronts=self:frontInfo(owner)}
  if full then
   local prices={};for kind in pairs(R.Buildings)do prices[kind]=self:buildingCost(owner,kind)end
   local borders={}
   for cell in pairs(f.frontier)do local target=self:owner(cell);if target>0 and self:adjacent(cell,owner)then borders[target]=true end end
   local options={};local amount=0
   for _,enemy in ipairs(self.factions)do if enemy.id~=owner and enemy.alive then
    local a=self:attackAssessment(owner,enemy.id,borders);amount=a.amount;options[tostring(enemy.id)]=P.pack(a,P.AttackFields)
   end end
   out.prices=prices;out.attack={amount=amount,options=options}
  end
  return out
 end
 function Game:snapshot()
  local owners=buffer.create(self.grid.count);buffer.copy(owners,0,self.cells)
  local roster=self:packedRoster()
  return {epoch=self.epoch,revision=self.revision,phase=self.phase,time=self.time,cellOwners=owners,
   roster=roster,rows=self:packedFactionRows(),structures=self:packedStructures(),units=self:packedUnits(),railways=self:packedRailways(),
   shared=self:sharedState(),recordFrames=self.phase=='finished'and self.recordFrames or nil}
 end
 -- What one receiver already holds (all clients of the server, or the lobby's local demo view);
 -- only differences are sent again. Cadence: cells every call, units every 2nd, shared state and
 -- buildings every 5th, country rows every 10th (changed rows only).
 function Game:newNet()return {step=0,rows={},force=true}end
 function Game:syncPacket(net)
  net.step+=1;local step,force=net.step,net.force;net.force=false
  local packet=self:changes()
  if step%2==0 or force then packet.units=self:packedUnits()end
  if step%5==0 or force then
   local state=self:sharedState()
   local events=state.events;local newest=events[#events]
   local key=#events..':'..(newest and newest.time or 0)..':'..(newest and newest.text or '')
   if key==net.events then state.events=nil else net.events=key end
   packet.shared=state
   if self.structureRevision~=net.structures then net.structures=self.structureRevision;packet.structures=self:packedStructures()end
   if self.railRevision~=net.railways then net.railways=self.railRevision;packet.railways=self:packedRailways()end
  end
  if step%10==0 or force then
   local roster,key=self:packedRoster()
   if key~=net.rosterKey then net.rosterKey=key;packet.roster=roster;net.rows={}end
   local rows={}
   for _,entry in ipairs(self:packedFactionRows())do
    local signature=P.signature(entry[2])
    if net.rows[entry[1]]~=signature then net.rows[entry[1]]=signature;table.insert(rows,entry)end
   end
   if #rows>0 then packet.rows=rows end
  end
  return packet,step,force
 end
end
return M
