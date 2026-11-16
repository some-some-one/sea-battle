--!native
--!nonstrict
-- Water-front conquest. OpenFront-derived economy is installed below; attacks retain explicit target consent.
local shared=game.ReplicatedStorage.SeaBattle
local Countries=require(shared.Countries)
local Config=require(shared.ConquestConfig)
local R=require(shared.NavalRules)
local Coop=require(shared.Coop)
local PLAYER=Config.PlayerId
local PARTICIPANTS=Config.ParticipantCount
assert(#Countries==Config.BotCount,"Country roster does not match bot count")
local COLORS=require(shared.TerritoryColors)
local Game={};Game.__index=Game
local function valid(n,max)return type(n)=="number" and n==n and n%1==0 and n>=1 and n<=max end
local function push(heap,node)
 local i=#heap+1;heap[i]=node
 while i>1 do local p=math.floor(i/2);if heap[p].key<=node.key then break end;heap[i]=heap[p];i=p end
 heap[i]=node
end
local function pop(heap)
 if #heap==0 then return nil end
 local first,last=heap[1],table.remove(heap)
 if #heap>0 then
  local i=1
  while i*2<=#heap do
   local c=i*2;if c<#heap and heap[c+1].key<heap[c].key then c+=1 end
   if last.key<=heap[c].key then break end
   heap[i]=heap[c];i=c
  end
  heap[i]=last
 end
 return first
end
function Game.new(grid,seed)
 local self=setmetatable({grid=grid,coast={},coastCells={},portOptions={},sitePorts={},reservedCoast={},epoch=0},Game)
 local pace={t=os.clock()}
 for id=1,grid.count do
  local p=grid.data.palette[grid:paletteId(id)]
  if p.water and (p.kind=="sea" or p.kind=="ocean") then
   for _,n in ipairs(grid:neighborIds(id))do if not grid:isWater(n)then
    self.coast[id]=true;table.insert(self.coastCells,id)
    local rid=grid:regionId(id);self.portOptions[rid]=self.portOptions[rid] or {};table.insert(self.portOptions[rid],id);break
   end end
  end
  if id%8192==0 then Coop.loadPace(pace)end
 end
 for _,site in ipairs(grid.data.spawnSites or {})do
  local ports={}
  for _,index in ipairs(site.coastCells)do
   local id=index+1
   assert(self.coast[id],"Reserved start is not a sea coast: "..site.id)
   table.insert(ports,id);self.reservedCoast[id]=true
  end
  assert(#ports>0,"Reserved start has no coast: "..site.id)
  self.sitePorts[site.id]=ports
 end
 -- Immutable land components keep land routes from searching other continents.
 self:landComponent(1)
 self:reset(seed);return self
end
function Game:owner(id)return buffer.readu8(self.cells,id-1)end
-- (The front's inner loops below read neighbours through grid:nb4 and owners straight from the cell
-- buffer, without the per-call tables of neighborIds / getCell: 2026-11-15, a solo match was more
-- than an iPhone 7 could step in real time. Same cells in the same order, so matches play the same.)
function Game:adjacent(id,owner)
 local cells=self.cells;local a,b,c,d=self.grid:nb4(id)
 return(a>0 and buffer.readu8(cells,a-1)==owner)or(b>0 and buffer.readu8(cells,b-1)==owner)
  or(c>0 and buffer.readu8(cells,c-1)==owner)or(d>0 and buffer.readu8(cells,d-1)==owner)
end
-- Whether `who` (an owner id, 0 = nobody) has a running attack, whose queue follows the boundary.
local function attacking(self,who)
 local f=who>0 and self.factions[who];local o=f and f.orders
 if o then for _,order in pairs(o)do if order.attackOwner>0 then return true end end end
 return false
end
function Game:colorFor(port)
 local c=self.grid:getCell(port);local near={}
 for _,f in ipairs(self.factions)do if f.startCell then
  local p=self.grid:getCell(f.startCell);local dx=math.abs(c.x-p.x);if self.grid.data.wrapX then dx=math.min(dx,self.grid.width-dx)end
  table.insert(near,{d=dx^2+(c.y-p.y)^2,color=f.color})
 end end
 table.sort(near,function(a,b)return a.d<b.d end)
 local used={};for _,f in ipairs(self.factions)do if f.startCell then used[table.concat(f.color,",")]=true end end
 -- Colours close to the tribes' brown stay free for nations' sake: a nation must not look like a tribe.
 local tribe=R.TribeColor
 for _,color in ipairs(COLORS)do
  if math.sqrt((color[1]-tribe[1])^2+(color[2]-tribe[2])^2+(color[3]-tribe[3])^2)<45 then used[table.concat(color,",")]=true end
 end
 local function perceptual(c)
  local function linear(v)v/=255;return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
  local r,g,b=linear(c[1]),linear(c[2]),linear(c[3])
  local function f(v)return v>.008856 and v^(1/3)or 7.787*v+16/116 end
  local x=f((.4124564*r+.3575761*g+.1804375*b)/.95047)
  local y=f(.2126729*r+.7151522*g+.072175*b)
  local z=f((.0193339*r+.119192*g+.9503041*b)/1.08883)
  return {116*y-16,500*(x-y),200*(y-z)}
 end
 for _,n in ipairs(near)do n.lab=perceptual(n.color)end
 local best,score=COLORS[1],-1
 for _,color in ipairs(COLORS)do
  if used[table.concat(color,",")]then continue end
  local lab=perceptual(color);local minimum,sum=math.huge,0
  for i=1,math.min(8,#near)do
   local q=near[i].lab;local distance=(lab[1]-q[1])^2+(lab[2]-q[2])^2+(lab[3]-q[3])^2
   minimum=math.min(minimum,distance);sum+=distance/i
  end
  if #near==0 then minimum=0 end
  local value=minimum+sum*.12+self.random:NextNumber(0,25)
  if value>score then best,score=color,value end
 end
 return table.clone(best)
end
function Game:_assign(id,owner)
 local old=self:owner(id);if old==owner then return end
 assert(self.grid:isWater(id),"Cannot own land")
 if old>0 then
  local f=self.factions[old];f.owned[id]=nil;if f.shore then f.shore[id]=nil end;f.count-=1;f.alive=f.count>0
  if not f.alive then f.orders={};f.frontier={}end
 end
 buffer.writeu8(self.cells,id-1,owner)
 if owner>0 then
  local f=self.factions[owner];f.owned[id]=true;f.count+=1;f.alive=true;f.frontier[id]=nil
 end
 local touchesLand=false
 local grid=self.grid;local mask,cellsBuf=grid.waterMask,self.cells
 local n1,n2,n3,n4=grid:nb4(id)
 for k=1,4 do
  local n=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
  if n==0 then continue end
  local water=buffer.readu8(mask,n-1)==1
  if not water then touchesLand=true end
  local no=buffer.readu8(cellsBuf,n-1)
  if no>0 and no~=owner then self.factions[no].frontier[id]=true end
  if owner>0 and no~=owner and water then self.factions[owner].frontier[n]=true end
  if old>0 and no~=old and water then self.factions[old].frontier[n]=true end
 end
 if owner>0 and touchesLand then local f=self.factions[owner];f.shore=f.shore or {};f.shore[id]=true end
 -- Keep combat queues tied to the current boundary, not an old expansion wave. (Only when someone
 -- around has an attack running: most captures are plain expansion and need none of this.)
 local queues=false
 if not self.resetting then
  queues=attacking(self,old)or attacking(self,owner)
  for k=1,4 do
   if queues then break end
   local n=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
   if n>0 then queues=attacking(self,buffer.readu8(cellsBuf,n-1))end
  end
 end
 if queues then
  local affected={[old]=true,[owner]=true};local cells={id}
  for k=1,4 do
   local n=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
   if n>0 then affected[buffer.readu8(cellsBuf,n-1)]=true;table.insert(cells,n)end
  end
  for who in pairs(affected)do
   local f=who>0 and self.factions[who]
   if f then for _,order in pairs(Game.ordersOf(f))do
    -- (only cells this order queued or could queue: _enqueue returns at once for the others)
    if order.attackOwner>0 then local seen,target=order.seen,order.attackOwner
     for _,n in ipairs(cells)do if seen[n]or buffer.readu8(cellsBuf,n-1)==target then self:_enqueue(f,order,n,0)end end
    end
   end end
  end
 end
 -- (dirty is flat: cell, owner, cell, owner, ...)
 self.revision+=1;local dirty=self.dirty;local n=#dirty;dirty[n+1]=id;dirty[n+2]=owner
 if self.onOwnership and not self.resetting then self:onOwnership(id,old,owner)end
end
function Game:_seed(port,owner)
 -- Small rounded patch rooted at the actual coastal port, never a 16x16 square.
 local c=self.grid:getCell(port);local q,seen,head={port},{[port]=true},1
 while head<=#q do
  local id=q[head];head+=1
  if self:owner(id)~=0 then continue end
  self:_assign(id,owner)
  for _,n in ipairs(self.grid:neighborIds(id))do
   local p=self.grid:getCell(n);local dx=math.abs(c.x-p.x);if self.grid.data.wrapX then dx=math.min(dx,self.grid.width-dx)end
   if not seen[n] and p.water and dx*dx+(c.y-p.y)^2<=16 then seen[n]=true;table.insert(q,n)end
  end
 end
end
function Game:reset(seed)
 self.random=Random.new(seed or math.random(1,1000000000));self.epoch+=1;self.revision=0
 self.noiseSeed=self.random:NextNumber(0,1000)
 self.phase="choosing";self.time=0;self.controller=nil;self.cells=buffer.create(self.grid.count)
 self.factions={};self.dirty={};self.usedStarts={}
 -- Bot kinds (R.BotKinds): a share of tribes, the rest nations in three temperaments. Drawn from a
 -- generator of their own so starts and colours stay what the match seed gave before kinds existed.
 local kinds={};local kindRandom=Random.new(math.floor(self.noiseSeed*1000)+7)
 local order={};for i=1,#Countries do order[i]=i end
 for i=#order,2,-1 do local j=kindRandom:NextInteger(1,i);order[i],order[j]=order[j],order[i]end
 local tribes=math.floor(#Countries*R.TribeShare+.5);local temper={'trader','warlord','nation'}
 for n,i in ipairs(order)do kinds[i]=n<=tribes and 'tribe'or temper[(n-tribes-1)%3+1]end
 for i,profile in ipairs(Countries)do
  local a=self.grid:geoToCell(profile[2],profile[3]);local choices={}
  if profile[5] and self.grid.data.id=="earth"then
   local ports=assert(self.sitePorts[profile[5]],"Missing guaranteed bot start: "..profile[5])
   for _,id in ipairs(ports)do
    local rid=self.grid:regionId(id)
    if self:owner(id)==0 and not self.usedStarts[rid]then table.insert(choices,{id=id,rid=rid,d=0})end
   end
  else
   for rid,ports in pairs(self.portOptions)do if not self.usedStarts[rid] then
   local best,distance=nil,math.huge
   for _,id in ipairs(ports)do if self:owner(id)==0 and not self.reservedCoast[id] then
    local c=self.grid:getCell(id);local dx=math.abs(c.x-a.x);if self.grid.data.wrapX then dx=math.min(dx,self.grid.width-dx)end
    -- Antarctic coastline belongs to the two dedicated polar participants.
    if self.grid.data.id=="earth" and c.y>self.grid.height*5/6 then continue end
    local d=dx^2+(c.y-a.y)^2;if d<distance then best,distance=id,d end
   end end
   if best then table.insert(choices,{id=best,d=distance,rid=rid})end
   end end
  end
  assert(#choices>0,"No valid coastal start: "..profile[1])
  table.sort(choices,function(x,y)return x.d<y.d end)
  local limit=profile[5] and #choices or math.min(5,#choices)
  while limit>1 and choices[limit].d>choices[1].d+100 do limit-=1 end
  local pick=choices[self.random:NextInteger(1,limit)];self.usedStarts[pick.rid]=true
  -- Tribes share one muted brown; nations get their own.
  local color=self:colorFor(pick.id);if kinds[i]=='tribe'then color=table.clone(R.TribeColor)end
  self.factions[i]={id=i,name=profile[1],color=color,startCell=pick.id,owned={},frontier={},kind=kinds[i],
   region=profile[4],spawnSite=profile[5],count=0,alive=false,bot=true,nextAction=self.random:NextNumber(.5,2),credit=0}
  self:_seed(pick.id,i)
 end
 self.factions[PLAYER]={id=PLAYER,name="Your country",color=table.clone(COLORS[1]),owned={},frontier={},count=0,alive=false,bot=false,credit=0}
end
-- Hand every remaining pixel of `victim` to `by` (the attack that wore it down).
function Game:annex(victim,by)
 local cells={};for id in pairs(self.factions[victim].owned)do table.insert(cells,id)end
 for _,id in ipairs(cells)do if self:owner(id)==victim then self:_assign(id,by)end end
end
-- Smooth per-match noise (−0.5..0.5, features ~9 cells): some stretches of a front or a growing
-- coast run ahead of others, so borders come out wavy instead of straight rows and circle arcs.
function Game:waviness(id)
 local w=self.grid.width
 return math.noise(((id-1)%w)/9+.5,((id-1)//w)/9+.5,self.noiseSeed or 0)
end
-- A cell no 2×2 block of its owner covers lies on a strip one pixel wide (straight or a staircase).
function Game:thin(id,owner)
 local w,h=self.grid.width,self.grid.height
 local x,y=(id-1)%w,(id-1)//w
 local cells=self.cells
 -- owned(dx,dy) for the eight cells around, read once (false off the map)
 local function at(nx,ny)return nx>=0 and nx<w and ny>=0 and ny<h and buffer.readu8(cells,ny*w+nx)==owner end
 local left,right,up,down=at(x-1,y),at(x+1,y),at(x,y-1),at(x,y+1)
 if left and up and at(x-1,y-1)then return false end
 if right and up and at(x+1,y-1)then return false end
 if left and down and at(x-1,y+1)then return false end
 if right and down and at(x+1,y+1)then return false end
 return true
end
-- Visited marks for the searches below: one u32 per cell holding the number of the search that last
-- saw it, so a search starts with nothing to clear and no table to fill (2026-11-16: with several
-- attacks at once these searches' `seen` tables were a large share of a phone's step).
local function stampRange(self,span)
 local s=self.stampBuf
 if not s or buffer.len(s)~=self.grid.count*4 then s=buffer.create(self.grid.count*4);self.stampBuf=s;self.stampGen=0 end
 local base=self.stampGen
 if base+span>=4294967295 then buffer.fill(s,0,0);base=0 end
 self.stampGen=base+span
 return s,base
end
local function stamps(self)local s,base=stampRange(self,1);return s,base+1 end
-- A strip swept away or a cell taken by force (set aside because it splits the defender) can cut the
-- defender in parts. Every part but its main body is encircled and goes to the attacker as well, so no
-- pixel pocket is left behind. A part that keeps growing past PocketLimit counts as a main body.
-- (Each part's cells carry the part's own mark. A search that runs into another part's cells is part of
-- a main body that an earlier search left unfinished: only a main body can have unvisited cells next to
-- it. It stops there and is dropped, since a main body is never taken; before 2026-11-16 it went on to
-- PocketLimit cells again and again along the same body.)
function Game:takePockets(f,order,cells,defender)
 local limit=R.PocketLimit;local parts={}
 local span=#cells*4+1;local seen,base=stampRange(self,span);local top=base+span;local mark=base
 local grid,buf=self.grid,self.cells
 for _,from in ipairs(cells)do
  local s1,s2,s3,s4=grid:nb4(from)
  for j=1,4 do
   local start=j==1 and s1 or j==2 and s2 or j==3 and s3 or s4
   if start<=0 or buffer.readu8(buf,start-1)~=defender then continue end
   local v0=buffer.readu32(seen,(start-1)*4)
   if v0>base and v0<=top then continue end
   mark+=1
   local part={start};buffer.writeu32(seen,(start-1)*4,mark);local head=1;local joined=false
   while head<=#part and #part<=limit do
    if head%64==0 then Coop.check()end
    local id=part[head];head+=1
    local n1,n2,n3,n4=grid:nb4(id)
    for k=1,4 do
     local n=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
     if n>0 and buffer.readu8(buf,n-1)==defender then
      local v=buffer.readu32(seen,(n-1)*4)
      if v>base and v<=top then
       if v~=mark then joined=true;break end
      else buffer.writeu32(seen,(n-1)*4,mark);table.insert(part,n)end
     end
    end
    if joined then break end
   end
   if not joined then part.big=#part>limit;table.insert(parts,part)end
  end
 end
 if #parts<2 then return end
 table.sort(parts,function(a,b)if a.big~=b.big then return a.big end;return #a>#b end)
 for k=2,#parts do local part=parts[k]
  if not part.big then for _,id in ipairs(part)do if self:canEnter(f.id,id,order)then self:_assign(id,f.id)end end end
 end
end
-- Land among the eight cells around (and the cell itself); off the map counts as nothing.
local function landAround(grid,id)
 local w,h,mask=grid.width,grid.height,grid.waterMask
 local cx,cy=(id-1)%w,(id-1)//w
 for y=math.max(0,cy-1),math.min(h-1,cy+1)do
  for x=math.max(0,cx-1),math.min(w-1,cx+1)do if buffer.readu8(mask,y*w+x)==0 then return true end end
 end
 return false
end
function Game:nearLand(id)return landAround(self.grid,id)end
-- One-pixel strips of the defender touching a fresh capture fall at once, without a fight, and the
-- sweep runs on along the strip: the deferred-cell path would take such a line a cell per tick.
function Game:takeThin(f,order,from)
 local defender=order.attackOwner;local queue={from};local head=1
 local grid,buf=self.grid,self.cells
 while head<=#queue and #queue<=R.ThinSweepLimit do
  local id=queue[head];head+=1
  local n1,n2,n3,n4=grid:nb4(id)
  for k=1,4 do
   local n=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
   -- Only strips on open water: a river or a strait between shores is fought for pixel by pixel.
   if n>0 and buffer.readu8(buf,n-1)==defender and self:canEnter(f.id,n,order)and self:thin(n,defender)and not landAround(grid,n)then
    self:_assign(n,f.id);table.insert(queue,n)
   end
  end
 end
 return queue
end
-- A country's running orders by target (0: neutral expansion).
function Game.ordersOf(f)
 local o=f.orders;if not o then o={};f.orders=o end;return o
end
function Game:canEnter(owner,id,order)
 local current=buffer.readu8(self.cells,id-1)
 if current==owner or buffer.readu8(self.grid.waterMask,id-1)==0 then return false end
 -- Neutral expansion and a targeted attack are mutually exclusive orders.
 -- Recheck on execution too: a queued enemy cell that becomes neutral is skipped.
 return order~=nil and current==(order.attackOwner or 0)
end
function Game:_enqueue(f,order,id,cost,origin)
 local previous=order.seen[id]
 local buf=self.cells;local current=buffer.readu8(buf,id-1)
 -- (a cell of somebody else that this order never queued: nothing to add or drop. Most calls are these:
 -- every capture next to a front asks each running attack about five cells, 2026-11-16)
 if not previous and current~=order.attackOwner then return end
 -- support: own neighbours (none = not adjacent); canEnter inlined
 local support=0
 local me=f.id
 if current~=me and buffer.readu8(self.grid.waterMask,id-1)==1 and current==(order.attackOwner or 0)then
  local a,b,c,d=self.grid:nb4(id)
  if a>0 and buffer.readu8(buf,a-1)==me then support+=1 end
  if b>0 and buffer.readu8(buf,b-1)==me then support+=1 end
  if c>0 and buffer.readu8(buf,c-1)==me then support+=1 end
  if d>0 and buffer.readu8(buf,d-1)==me then support+=1 end
 end
 if support==0 then
  if previous then order.seen[id]=nil;order.border=math.max(0,(order.border or 1)-1)end
  return
 end
 local combat=order.attackOwner>0
 if previous and(not combat or previous.support==support)then return end
 origin=origin or id
 local key
 if combat then
  -- A shared moving front: fill supported concavities before projecting thin fingers. A
  -- cell waits (1..1.6)·(1.5−0.5·support) on the front's own clock, which runs by cells taken (a
  -- tick), not seconds: we take a whole front in a few ticks, and on the seconds clock
  -- every new cell sorted behind its column, so the front marched in straight rows.
  key=(order.clock or 0)+(1+self.random:NextNumber(0,.6))*math.max(0,1.5-.5*support)+R.FrontNoise*self:waviness(id)
 else
  local width=self.grid.width
  local dx=math.abs((id-1)%width-(origin-1)%width)
  if self.grid.data.wrapX then dx=math.min(dx,width-dx)end
  local dy=math.floor((id-1)/width)-math.floor((origin-1)/width)
  local distance=math.sqrt(dx*dx+dy*dy)
  key=.75*distance*(1+R.ExpansionNoise*self:waviness(id))+.25*cost+self.random:NextNumber(0,.35)
 end
 local node={id=id,cost=cost,origin=origin,key=key,support=support}
 if not previous then order.border=(order.border or 0)+1 end
 order.seen[id]=node;push(order.heap,node)
 -- Lazy replacement keeps updates local; compact stale entries at a bounded ratio.
 if #order.heap>math.max(128,order.border*3)then
  order.heap={};for _,current in pairs(order.seen)do push(order.heap,current)end
 end
end
-- A front must not cut a defender into pixel pockets. Most cells pass the cheap
-- local-ring check; ambiguous open-water necks use bounded reachability.
-- Rivers and shores may legitimately split a country when their narrow channel is captured.
function Game:preservesFront(id,owner)
 local grid,buf=self.grid,self.cells
 if landAround(grid,id)then return true end
 local neighbors={}
 do
  local a,b,c,d=grid:nb4(id)
  for k=1,4 do
   local n=k==1 and a or k==2 and b or k==3 and c or d
   if n>0 and buffer.readu8(buf,n-1)==owner then table.insert(neighbors,n)end
  end
 end
 if #neighbors<2 then return true end
 local w=grid.width;local cx,cy=(id-1)%w,(id-1)//w
 local function connected(limit,localOnly)
  local seen,gen=stamps(self)
  buffer.writeu32(seen,(id-1)*4,gen);buffer.writeu32(seen,(neighbors[1]-1)*4,gen)
  local q={neighbors[1]};local head,found=1,1
  local want2,want3,want4=neighbors[2],neighbors[3],neighbors[4]
  while head<=#q and head<=limit do
   local cell=q[head];head+=1
   local n1,n2,n3,n4=grid:nb4(cell)
   for k=1,4 do
    local n=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
    if n>0 and buffer.readu8(buf,n-1)==owner and buffer.readu32(seen,(n-1)*4)~=gen then
    if not localOnly or(math.abs(cx-(n-1)%w)<=1 and math.abs(cy-(n-1)//w)<=1)then
     buffer.writeu32(seen,(n-1)*4,gen);table.insert(q,n)
     if n==want2 or n==want3 or n==want4 then found+=1;if found==#neighbors then return true end end
    end
   end end
  end
  return false
 end
 return connected(8,true)or connected(512,false)
end
function Game:cancelOpposing(f,order)
 local target=order.attackOwner;local other=target>0 and self.factions[target]
 local opposing=other and Game.ordersOf(other)[f.id]
 if not opposing then return false end
 local cancelled=math.min(order.fleet,opposing.fleet)
 order.fleet-=cancelled;opposing.fleet-=cancelled
 if opposing.fleet<1 then other.orders[f.id]=nil end
 if order.fleet<1 and f.orders[target]==order then f.orders[target]=nil end
 return cancelled>0
end
function Game:order(owner,target,committed,attackOwner)
 local f=self.factions[owner]
 if not f or not f.alive then return false,"defeated"end
 local enemy=attackOwner or self:owner(target)
 if enemy>0 then
  if self:allied(owner,enemy)then return false,"alliance_required"end
  if self.time<(self.factions[enemy].protectedUntil or 0)then return false,"protected"end
  if f.bot and not self:mayBotAttack(owner,enemy)then return false,"protected"end
 end
 local amount=committed or math.floor(f.fleet*(f.ratio or .25))
 if amount<20 then return false,"fleet"end
 -- One order per target, any number of targets: the same target again reinforces its
 -- running front (a landing adds its beachhead to it); another target starts another order alongside.
 local orders=Game.ordersOf(f);local current=orders[enemy]
 if current then
  if not committed then f.fleet-=amount end
  current.fleet+=amount;current.target=target
  if committed then for _,n in ipairs(self.grid:neighborIds(target))do self:_enqueue(f,current,n,0)end end
  return true,"reinforced"
 end
 local order={target=target,attackOwner=enemy,heap={},seen={},fleet=amount,combatRate=enemy>0 and math.clamp(self.factions[enemy].count*R.CombatAreaPerSecond,1,Config.PlayerSpeed)or nil}
 for id in pairs(f.frontier)do
  if self:owner(id)==owner or not self:adjacent(id,owner)then f.frontier[id]=nil
  elseif self:canEnter(owner,id,order)then self:_enqueue(f,order,id,0)end
 end
 if #order.heap==0 then return false,"not_adjacent"end
 if not committed then f.fleet-=amount end
 order.credit=0;orders[enemy]=order;f.lastOrderEnd=nil
 if enemy>0 then f.lastAttack=enemy end
 if enemy>0 then self:recordHostility(owner,enemy)end
 local counter=self:cancelOpposing(f,order)
 return true,counter and "countered"or "advancing"
end
function Game:_bot(f)
 local target,score;local checked={};local policy=R.difficulty(self.settings.difficulty)
 local kind=R.botKind(f)
 f.ratio=math.clamp(policy.share+kind.share,.1,.6)
 for id in pairs(f.frontier)do
  local owner=self:owner(id)
  if checked[owner]then continue end
  if self:adjacent(id,f.id)and(owner==0 or(not self:allied(f.id,owner)and self:mayBotAttack(f.id,owner)))then
   checked[owner]=true
   local other=self.factions[owner]
   -- Bots leave each other alone during the opening and attack only with a clear fleet edge.
   local retaliating=other and(f.retaliation and f.retaliation[owner]or 0)>self.time
   if owner>0 and not retaliating and(not kind.strikesFirst or f.fleet<other.fleet*policy.edge*kind.edge
    or(other.bot and self.time<policy.botWarAt*kind.warAt)
    or(not other.bot and self.random:NextNumber()<math.min(.97,policy.skip*kind.skip)))then continue end
   local value=owner==0 and 100 or 30-(other.fleet/math.max(1,f.fleet))*20
   if not score or value>score then target,score=id,value end
  end
 end
 if target then self:order(f.id,target)end
end
-- One order's step: takes cells along its front while its credit, fleet and the defender's pace allow.
function Game:advance(f,order,dt)
 local enemy=order.attackOwner
 order.tickBorder=math.max(1,order.border or 1)
 -- Capture rate grows with the front: every front cell keeps moving instead of 200 px/s shared by the whole border.
 -- An attack is still held to a tenth of the defender's area per second.
 local frontRate=math.clamp(order.tickBorder*R.FrontCellsPerSecond,Config.PlayerSpeed,R.MaxCaptureRate)
 -- The tenth is of the defender's area when the attack began, not of what is left: measured on the
 -- shrinking remnant, the pace fell with every pixel and a country's last few hundred took longer
 -- than the rest of it.
 local target=order.attackOwner>0 and self.factions[order.attackOwner]
 if target then order.targetArea=math.max(order.targetArea or 0,target.count)end
 local rate=target and math.clamp(order.targetArea*R.CombatAreaPerSecond,1,frontRate)or frontRate
 rate*=f.bot and(R.difficulty(self.settings.difficulty).speed or 1)or 1
 order.credit=math.min(math.max(24,rate*.12),(order.credit or 0)+dt*rate)
 local maxAttempts=math.max(80,math.ceil(rate*.12)+20)
 order.combatCredit=(order.combatCredit or 0)+dt/.1
 local attempts=0
 while order.credit+1e-6>=1 and #order.heap>0 and attempts<maxAttempts do
  if attempts%16==15 then Coop.check()end
  local node=pop(order.heap);attempts+=1
  if order.seen[node.id]~=node then continue end
  order.seen[node.id]=nil;order.border=math.max(0,(order.border or 1)-1)
  if not self:canEnter(f.id,node.id,order)or not self:adjacent(node.id,f.id)then continue end
  local defender=self:owner(node.id)
  -- Prefer a coherent front, but only as a preference: a cell that would split the defender
  -- is set aside and taken once nothing else is left, so thin strips cannot stall an attack.
  if defender>0 and not node.force and not self:preservesFront(node.id,defender)then
   order.frontBlocked=true;order.deferred=order.deferred or {};order.deferred[node.id]=node;continue
  end
  local loss,defense,fraction,fortified=self:conquestCost(f,order,node.id)
  if not loss then continue end
  if order.fleet<loss then self:stop(f.id,false,'fleet_exhausted',enemy);break end
  local work=order.attackOwner>0 and fortified and R.DefenseSlow or 1
  if order.combatCredit+1e-6<fraction or order.credit+1e-6<work then
   order.seen[node.id]=node;order.border+=1;push(order.heap,node);break
  end
  order.combatCredit-=fraction;order.fleet-=loss
  order.clock=(order.clock or 0)+R.FrontWaves/order.tickBorder
  local old=self:owner(node.id)
  if old>0 then self.factions[old].fleet=math.max(0,self.factions[old].fleet-defense);f.hasAttacked=true end
  self:_assign(node.id,f.id);order.credit=math.max(0,order.credit-work)
  if old>0 then
   local swept=self:takeThin(f,order,node.id)
   if #swept>1 or node.force then self:takePockets(f,order,swept,old)end
  end
  -- A country worn down below AnnexBelow pixels falls whole, so its last strips and
  -- pockets do not drag on pixel by pixel. A human only once the attack outnumbers the fleet at home.
  local victim=old>0 and self.factions[old]
  if victim and victim.alive and victim.count<R.AnnexBelow and(victim.bot or order.fleet>victim.fleet)then
   self:annex(old,f.id);self:stop(f.id,false,'target_defeated',enemy);break
  end
  local n1,n2,n3,n4=self.grid:nb4(node.id)
  if n1>0 then self:_enqueue(f,order,n1,node.cost+1,node.origin)end
  if n2>0 then self:_enqueue(f,order,n2,node.cost+1,node.origin)end
  if n3>0 then self:_enqueue(f,order,n3,node.cost+1,node.origin)end
  if n4>0 then self:_enqueue(f,order,n4,node.cost+1,node.origin)end
 end
 if f.orders[enemy]==order and #order.heap==0 and order.deferred then
  local deferred=order.deferred;order.deferred=nil
  for id,node in pairs(deferred)do
   if not order.seen[id]and self:canEnter(f.id,id,order)and self:adjacent(id,f.id)then
    node.force=true;order.seen[id]=node;order.border=(order.border or 0)+1;push(order.heap,node)
   end
  end
 end
 Coop.check()
 if f.orders[enemy]==order and #order.heap==0 then
  local target=order.attackOwner>0 and self.factions[order.attackOwner]
  local reason=target and target.alive and(order.frontBlocked and 'front_blocked'or 'target_unreachable')or target and 'target_defeated'or 'expansion_finished'
  self:stop(f.id,false,reason,enemy)
 end
end
function Game:tick(dt)
 if self.phase~="playing"then return end
 self.time+=dt;self:economyTick(dt)
 -- Resolve any simultaneous/restored opposing orders before either changes ownership.
 for _,f in ipairs(self.factions)do for _,order in pairs(table.clone(Game.ordersOf(f)))do self:cancelOpposing(f,order)end end
 local total=#self.factions;local offset=self.random:NextInteger(0,total-1)
 local botSpeed=R.difficulty(self.settings.difficulty).speed or 1
 -- Choose all bot orders before moving any front this step.
 for k=1,total do
  local f=self.factions[(k+offset-1)%total+1]
  if f.alive and f.bot then
   if not next(Game.ordersOf(f))and self.time>=f.nextAction then self:_bot(f);local policy=R.difficulty(self.settings.difficulty);f.nextAction=self.time+self.random:NextNumber(policy.thinkMin,policy.thinkMax)*R.botKind(f).think end
   self:botEconomy(f)
  end
  -- On a client the step may pause here and go on in the next frame (shared/Coop); a no-op on the server.
  Coop.check()
 end
 for k=1,total do
  local f=self.factions[(k+offset-1)%total+1]
  if not f.alive then continue end
  if not next(Game.ordersOf(f))then continue end
  -- Every running order advances on its own (one attack per attacker and target, any
  -- number of targets at once, neutral expansion alongside them).
  for _,order in pairs(table.clone(f.orders))do
   if f.orders[order.attackOwner]==order then self:advance(f,order,dt)end
  end
 end
 self:aviationTick(dt);self:diplomacyTick(dt);self:matchTick(dt)
end
function Game:publicFaction(f,transit,away)
 local cap=self:cap(f.id);transit=transit or {fleet=0,count=0}
 local function tenth(v)return v and math.floor(v*10+.5)/10 or nil end
 return {id=f.id,name=f.name,color=f.color,kind=f.bot and(f.kind or 'nation')or nil,startCell=f.startCell,count=f.count,region=f.region,spawnSite=f.spawnSite,
  gold=math.floor(f.gold),fleet=math.floor(f.fleet),cap=math.floor(cap),fleetPerSecond=tenth(self:fleetGrowthPerSecond(f.id,cap,away)),ratio=f.ratio,team=f.team,
  traitorUntil=tenth(f.traitorUntil),protectedUntil=tenth(f.protectedUntil),humanGraceUntil=tenth(f.humanGraceUntil),lastOrderEnd=f.lastOrderEnd,
  committed=math.floor(self:orderFleet(f)+transit.fleet),transportFleet=math.floor(transit.fleet),transportCount=transit.count,
  alive=f.alive,bot=f.bot,advancing=next(Game.ordersOf(f))~=nil,attackOwner=self:mainAttack(f),expanding=Game.ordersOf(f)[0]~=nil}
end
-- Fleet in all of a country's running orders.
function Game:orderFleet(f)
 local n=0;for _,o in pairs(Game.ordersOf(f))do n+=o.fleet or 0 end;return n
end
-- The attack the status line names: the latest one still running, else any running attack (0: none).
function Game:mainAttack(f)
 local orders=Game.ordersOf(f)
 if f.lastAttack and orders[f.lastAttack]then return f.lastAttack end
 for e in pairs(orders)do if e>0 then return e end end
 return 0
end
function Game:transit()
 local flying={}
 for _,u in pairs(self.units)do if u.kind=='transport'and u.hp>0 then
  local a=flying[u.owner]or {fleet=0,count=0};a.fleet+=u.fleet;a.count+=1;flying[u.owner]=a
 end end
 return flying
end
function Game:publicFactions()
 local result={};local flying=self:transit();local away=self:awayFleet()
 for _,f in ipairs(self.factions)do table.insert(result,self:publicFaction(f,flying[f.id],away[f.id]or 0))end
 return result
end
require(script.Parent.NavalEconomy).install(Game)
require(script.Parent.NavalAviation).install(Game)
require(script.Parent.NavalMatch).install(Game)
require(script.Parent.NavalArsenal).install(Game)
require(script.Parent.NetSync).install(Game)
return Game
