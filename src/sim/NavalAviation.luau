--!nonstrict
-- Water/land inversion of OpenFront transport, trade, warship and missile roles.
-- © OpenFront and Contributors. Modified 2026-11-02; see LICENSE.
local R=require(game.ReplicatedStorage.SeaBattle.NavalRules)
local Routes=require(game.ReplicatedStorage.SeaBattle.SurfaceRoutes)
local Coop=require(game.ReplicatedStorage.SeaBattle.Coop)
local M={}
function M.install(Game)
 function Game:unit(owner,kind,cell,route,extra)
  self.nextUnit+=1
  local u={id=self.nextUnit,owner=owner,kind=kind,cell=cell,route=route,index=1,progress=0,hp=1000,level=0,kills=0,nextShot=0,born=self.time}
  for k,v in pairs(extra or {})do u[k]=v end
  self.units[u.id]=u;return u
 end
 function Game:airport(owner,id)
  local s=self.structures[id]
  if not s or s.dead or s.owner~=owner or s.kind~='airport'or not s.land or not self:activeStructure(s)then return nil end
  return s
 end
 function Game:landEnd(cell)
  if not R.cell(cell,self.grid.count)or not self.grid:isWater(cell)then return nil end
  for _,id in ipairs(self.grid:neighborIds(cell))do if not self.grid:isWater(id)then return id end end
 end
 -- Connected areas of one surface, built once per grid: 'land' (dry land) and 'rail' (land joined across rivers).
 function Game:surfaceComponent(cell,mode)
  local grid=self.grid;local field=mode=='rail'and'railComponents'or'landComponents';local flag=field..'Building'
  while grid[flag]do Coop.wait()end
  if not grid[field]then
   grid[flag]=true
   local water=mode=='rail'and'rail'or false
   local comp=buffer.create(grid.count*4);local n,work=0,0;local pace={t=os.clock()}
   for id=1,grid.count do
    if Routes.passable(grid,id,water)and buffer.readu32(comp,(id-1)*4)==0 then
     n+=1;buffer.writeu32(comp,(id-1)*4,n);local q,head={id},1
     while head<=#q do
      local c=q[head];head+=1;work+=1
      for _,nb in ipairs(grid:neighborIds(c))do
       if Routes.passable(grid,nb,water)and buffer.readu32(comp,(nb-1)*4)==0 then buffer.writeu32(comp,(nb-1)*4,n);table.insert(q,nb)end
      end
      if work%4096==0 then Coop.loadPace(pace)end
     end
    end
    if id%8192==0 then Coop.loadPace(pace)end
   end
   grid[field]=comp;grid[flag]=nil
  end
  return R.cell(cell,grid.count)and buffer.readu32(grid[field],(cell-1)*4)or 0
 end
 function Game:landComponent(cell)return self:surfaceComponent(cell,'land')end
 function Game:railComponent(cell)return self:surfaceComponent(cell,'rail')end
 -- Keep only landing sides on a land mass that a source can actually reach.
 function Game:reachableTargets(sources,targets)
  local masses={};for land in pairs(sources)do masses[self:landComponent(land)]=true end
  local out={};for land,water in pairs(targets)do if masses[self:landComponent(land)]then out[land]=water end end
  return out
 end
 function Game:surfacePath(a,b,water)
  self.routes=self.routes or Routes.new(self.grid)
  if water==false and a and b and self:landComponent(a)~=self:landComponent(b)then return nil end
  if water=='rail'and a and b and self:railComponent(a)~=self:railComponent(b)then return nil end
  return self.routes:find(a,b,water)
 end
 -- Rails: the land route straightened into long horizontal and vertical runs joined at right angles.
 -- River cells count as land here: the track crosses them on bridges.
 -- Returns the cells the train rides through and the corner cells the client draws as track.
 function Game:railRoute(path)
  local grid=self.grid;local w=grid.width
  local function xy(id)return(id-1)%w,(id-1)//w end
  local function at(x,y)return y*w+x+1 end
  local function runFree(x1,y1,x2,y2)
   local dx,dy=math.sign(x2-x1),math.sign(y2-y1);local x,y=x1,y1
   while true do if not Routes.passable(grid,at(x,y),'rail')then return false end;if x==x2 and y==y2 then return true end;x+=dx;y+=dy end
  end
  -- Corner for an L from a to b over land, horizontal-first or vertical-first; nil when both cross water.
  local function corner(a,b)
   local ax,ay=xy(a);local bx,by=xy(b)
   if runFree(ax,ay,bx,ay)and runFree(bx,ay,bx,by)then return at(bx,ay)end
   if runFree(ax,ay,ax,by)and runFree(ax,by,bx,by)then return at(ax,by)end
  end
  -- A route across the date-line seam stays as it is: straight runs would cross the whole map.
  for k=2,#path do local ax=xy(path[k-1]);local bx=xy(path[k]);if math.abs(ax-bx)>1 then return path,nil end end
  local corners={path[1]};local i=1
  while i<#path do
   local best,bestCorner=i+1,nil;local misses=0
   for j=i+2,#path do
    local c=corner(path[i],path[j]);if c then best,bestCorner=j,c;misses=0 else misses+=1;if misses>24 then break end end
   end
   if bestCorner and bestCorner~=path[i]and bestCorner~=path[best]then table.insert(corners,bestCorner)end
   table.insert(corners,path[best]);i=best
  end
  -- Drop corners that sit on a straight run.
  local clean={corners[1]}
  for k=2,#corners-1 do
   local px,py=xy(clean[#clean]);local cx,cy=xy(corners[k]);local nx,ny=xy(corners[k+1])
   if not((px==cx and cx==nx)or(py==cy and cy==ny))then table.insert(clean,corners[k])end
  end
  table.insert(clean,corners[#corners])
  local cells={clean[1]}
  for k=2,#clean do
   local ax,ay=xy(clean[k-1]);local bx,by=xy(clean[k]);local dx,dy=math.sign(bx-ax),math.sign(by-ay);local x,y=ax,ay
   while x~=bx or y~=by do x+=dx;y+=dy;table.insert(cells,at(x,y))end
  end
  return cells,clean
 end
 -- Railway network: one shared tree of track per land mass. A new airport gets a single branch to the
 -- nearest existing track (cut at the first rail it meets), so lines never run on top of each other and
 -- trains between any two airports ride through the junctions in between.
 function Game:railState()
  self.rail=self.rail or {edges={},adj={},onRail={},stations={},nextEdge=0}
  return self.rail
 end
 local function cornersOf(w,cells)
  local out={cells[1]}
  for k=2,#cells-1 do
   local a,b,c=cells[k-1],cells[k],cells[k+1]
   if(b-a)~=(c-b)then table.insert(out,b)end
  end
  if #cells>1 then table.insert(out,cells[#cells])end
  return out
 end
 function Game:addRailEdge(cells)
  local r=self:railState();r.nextEdge+=1
  local e={id=r.nextEdge,a=cells[1],b=cells[#cells],cells=cells}
  r.edges[e.id]=e
  for _,node in ipairs({e.a,e.b})do r.adj[node]=r.adj[node]or {};r.adj[node][e.id]=true end
  for _,c in ipairs(cells)do if not r.onRail[c]then r.onRail[c]=e.id end end
  self.railRevision=(self.railRevision or 0)+1
  return e
 end
 -- Turn a track cell into a junction node by splitting the edge that runs through it.
 function Game:railJunction(cell)
  local r=self:railState();if r.adj[cell]then return end
  local id=r.onRail[cell];local e=id and r.edges[id];if not e then return end
  local at=table.find(e.cells,cell);if not at or at==1 or at==#e.cells then return end
  local first,second={},{}
  for k=1,at do table.insert(first,e.cells[k])end
  for k=at,#e.cells do table.insert(second,e.cells[k])end
  r.edges[id]=nil;r.adj[e.a][id]=nil;r.adj[e.b][id]=nil
  for _,c in ipairs(e.cells)do if r.onRail[c]==id then r.onRail[c]=nil end end
  self:addRailEdge(first);self:addRailEdge(second)
 end
 -- Connect an airport to the network (or, for the first two on a land mass, to each other).
 function Game:railConnect(s,partner)
  local r=self:railState();local node=s.land
  if r.stations[s.id]then return true end
  if r.onRail[node]or r.adj[node]then self:railJunction(node);r.stations[s.id]=node;return true end
  local component=self:railComponent(node);local target,best
  for c in pairs(r.onRail)do
   if self:railComponent(c)==component then local d=self:distance(node,c);if not best or d<best then target,best=c,d end end
  end
  target=target or(partner and partner.land)
  if not target then return false end
  local path=self:surfacePath(node,target,'rail');if not path then return false end
  if r.stations[s.id]then return true end
  local cells=self:railRoute(path)
  -- Stop at the first track the branch reaches: that point becomes a junction.
  local cut={}
  for _,c in ipairs(cells)do table.insert(cut,c);if c~=node and(r.onRail[c]or r.adj[c])then break end end
  local last=cut[#cut]
  if r.onRail[last]or r.adj[last]then self:railJunction(last)end
  if #cut>1 then self:addRailEdge(cut)end
  r.stations[s.id]=node
  if partner and not r.onRail[partner.land]and not r.adj[partner.land]then r.stations[partner.id]=nil end
  return true
 end
 -- Cells of the shortest ride over the network between two airports (nil when not connected).
 function Game:railTrip(a,b)
  local r=self:railState();local from,to=r.stations[a.id],r.stations[b.id]
  if not from or not to then return nil end
  local dist,prev,via,open={[from]=0},{},{},{from}
  while #open>0 do
   local bestI=1;for k=2,#open do if dist[open[k]]<dist[open[bestI]]then bestI=k end end
   local node=table.remove(open,bestI);if node==to then break end
   for id in pairs(r.adj[node]or {})do
    local e=r.edges[id];local other=e.a==node and e.b or e.a;local d=dist[node]+#e.cells
    if not dist[other]or d<dist[other]then
     if not dist[other]then table.insert(open,other)end
     dist[other]=d;prev[other]=node;via[other]=e
    end
   end
  end
  if not dist[to]then return nil end
  local chain={};local node=to
  while node~=from do table.insert(chain,1,{via[node],prev[node]});node=prev[node]end
  local cells={from}
  for _,step in ipairs(chain)do
   local e,start=step[1],step[2]
   if e.a==start then for k=2,#e.cells do table.insert(cells,e.cells[k])end
   else for k=#e.cells-1,1,-1 do table.insert(cells,e.cells[k])end end
  end
  return cells,cornersOf(self.grid.width,cells)
 end
 -- Airports that trade by land with this one (any country, own included): same land mass, nearest first.
 function Game:landPartners(s)
  local out={}
  for _,other in ipairs(self.structures)do
   if other~=s and other.kind=='airport'and self:activeStructure(other)and self:railComponent(s.land)==self:railComponent(other.land)then table.insert(out,other)end
  end
  table.sort(out,function(a,b)return self:distance(s.cell,a.cell)<self:distance(s.cell,b.cell)end)
  return out
 end
 -- Lay track for ready airports that have a trading partner, a couple per call.
 function Game:railNetworkTick()
  local r=self:railState();local laid=0
  for _,s in ipairs(self.structures)do
   if laid>=2 then break end
   if s.kind=='airport'and self:activeStructure(s)and not r.stations[s.id]then
    local partner=self:landPartners(s)[1]
    if partner then
     if not r.stations[partner.id]then self:railConnect(partner,s)end
     self:railConnect(s,partner);laid+=1
    end
   end
  end
 end
 function Game:packedRailways()
  local rows={};local w=self.grid.width
  for id,e in pairs(self:railState().edges)do table.insert(rows,{id,cornersOf(w,e.cells)})end
  return rows
 end
 -- Ships sail straight legs: the water route reduced to the fewest corners that still see each other over water.
 -- Returns the cells the ship passes and the corner cells the client draws it along.
 function Game:straightWater(path)
  local grid=self.grid;local w=grid.width
  local function line(a,b,visit)
   local ax,ay=(a-1)%w,(a-1)//w;local bx,by=(b-1)%w,(b-1)//w
   local dx,dy=bx-ax,by-ay;local n=math.max(math.abs(dx),math.abs(dy),1)
   local px,py=ax,ay
   for k=1,n do
    local x,y=math.round(ax+dx*k/n),math.round(ay+dy*k/n)
    -- A diagonal step also needs one side cell in water, so the line never cuts a land corner.
    if x~=px and y~=py then if not visit(y*w+px+1)and not visit(py*w+x+1)then return false end end
    if not visit(y*w+x+1)then return false end
    px,py=x,y
   end
   return true
  end
  local function clear(a,b)return line(a,b,function(id)return grid:isWater(id)end)end
  if not path or #path<2 then return path,nil end
  for k=2,#path do if math.abs((path[k]-1)%w-(path[k-1]-1)%w)>1 then return path,nil end end
  local corners={path[1]};local i=1
  while i<#path do
   local j=math.min(#path,i+160)
   while j>i+1 and not clear(path[i],path[j])do j-=math.max(1,(j-i)//6)end
   table.insert(corners,path[j]);i=j
  end
  local cells={corners[1]}
  for k=2,#corners do line(corners[k-1],corners[k],function(id)if grid:isWater(id)and cells[#cells]~=id then table.insert(cells,id)end;return true end)end
  if cells[#cells]~=path[#path]then table.insert(cells,path[#path])end
  return cells,corners
 end
 -- Aircraft fly straight between airports, over water as well.
 function Game:airLine(a,b)
  local w=self.grid.width;local ax,ay=(a-1)%w,(a-1)//w;local bx,by=(b-1)%w,(b-1)//w
  local steps=math.max(math.abs(bx-ax),math.abs(by-ay),1);local cells={}
  for k=0,steps do local x,y=math.round(ax+(bx-ax)*k/steps),math.round(ay+(by-ay)*k/steps);local id=y*w+x+1
   if cells[#cells]~=id then table.insert(cells,id)end end
  return cells
 end
 function Game:transportCheck(owner,target)
  local f=self.factions[owner]
  if not f or not f.alive or self.phase~='playing'then return false,'start_required'end
  if not R.cell(target,self.grid.count)or not self.grid:isWater(target)then return false,'water_required'end
  local enemy=self:owner(target)
  if enemy==owner then return false,'invalid'end
  if enemy>0 then
   if self:allied(owner,enemy)then return false,'alliance_required'end
   if self.time<(self.factions[enemy].protectedUntil or 0)or(f.bot and not self:mayBotAttack(owner,enemy))then return false,'protected'end
  end
  local n=0;for _,u in pairs(self.units)do if u.owner==owner and u.kind=='transport'and u.hp>0 then n+=1 end end
  if n>=R.TransportLimit then return false,'transport_limit'end
  local amount=math.floor(f.fleet*(f.ratio or R.AttackShare));if amount<100 then return false,'fleet'end
  return true,nil,enemy,amount
 end
 function Game:landingSides(cell)
  local result={}
  for _,n in ipairs(self.grid:neighborIds(cell))do if not self.grid:isWater(n)then result[n]=cell end end
  return result
 end
 function Game:dispatchTransport(owner,path,source,target,enemy,origin)
  local ok,reason,current,amount=self:transportCheck(owner,target)
  if not ok then return false,reason end
  if current~=enemy or self:owner(source)~=owner then return false,'stale'end
  local f=self.factions[owner];f.lastOrderEnd=nil
  f.fleet-=amount;if enemy>0 then self:recordHostility(owner,enemy)end
  -- The land route proves the flight is possible; the plane itself flies straight.
  local line=self:airLine(path[1],path[#path])
  self:unit(owner,'transport',line[1],line,{fleet=amount,target=target,attackOwner=enemy,origin=origin,source=source,rail={line[1],line[#line]}})
  return true,'land_attack_launched'
 end
 function Game:transport(owner,airportId,target)
  local s=self:airport(owner,airportId);if not s then return false,'airport_coast'end
  local ok,reason,enemy=self:transportCheck(owner,target);if not ok then return false,reason end
  local targets=self:landingSides(target);if not next(targets)then return false,'landing_coast_required'end
  local epoch=self.epoch;self.routes=self.routes or Routes.new(self.grid)
  local source=s.water or self:shoreAnchor(owner,s.land)
  if not source then return false,'own_coast_required'end
  targets=self:reachableTargets({[s.land]=source},targets);if not next(targets)then return false,'land_route'end
  local path=self.routes:between({[s.land]=source},targets,false)
  if epoch~=self.epoch or not self:airport(owner,airportId)then return false,'stale'end
  if not path then return false,'land_route'end
  return self:dispatchTransport(owner,path,source,target,enemy,s.id)
 end
 function Game:autoTransport(owner,target)
  local ok,reason,enemy=self:transportCheck(owner,target);if not ok then return false,reason end
  local f=self.factions[owner];local sources={}
  for water in pairs(f.shore or {})do if self:owner(water)==owner then
   for land in pairs(self:landingSides(water))do sources[land]=water end
  end end
  if not next(sources)then return false,'own_coast_required'end
  local targets=self:landingSides(target)
  -- Clicking the interior selects this country; choose its reachable coastal foothold.
  if not next(targets)and enemy>0 then for water in pairs(self.factions[enemy].shore or {})do
   if self:owner(water)==enemy then for land in pairs(self:landingSides(water))do targets[land]=water end end
  end end
  if not next(targets)then return false,'landing_coast_required'end
  targets=self:reachableTargets(sources,targets);if not next(targets)then return false,'land_route'end
  local epoch=self.epoch;self.routes=self.routes or Routes.new(self.grid)
  local path,source,landing=self.routes:between(sources,targets,false)
  if epoch~=self.epoch then return false,'stale'end
  if not path then return false,'land_route'end
  return self:dispatchTransport(owner,path,source,landing,enemy)
 end
 -- A fighter takes off from the airport and patrols `target` (by default the airport itself).
 function Game:launchFighter(owner,airportId,target)
  local s=self:airport(owner,airportId);if not s then return false,'airport_required'end
  local count=0;for _,u in pairs(self.units)do if u.owner==owner and u.kind=='fighter'then count+=1 end end
  local price=R.fighterCost(count);local f=self.factions[owner]
  if count>=12 then return false,'aircraft_limit'end
  if f.gold<price then return false,'gold'end
  f.gold-=price
  local u=self:unit(owner,'fighter',s.land,nil,{origin=s.id,patrol=target or s.land})
  self:flyTo(u,target or self:patrolPoint(u))
  return true,'launched'
 end
 -- A move order: a new patrol centre for one of `owner`'s fighters; it drops
 -- any chase and flies there. A fighter on its way to repairs keeps the new centre for afterwards.
 function Game:moveFighter(owner,unitId,cell)
  local u=self.units[unitId]
  if not u or u.kind~='fighter'or u.owner~=owner then return false,'invalid'end
  u.patrol=cell;u.hunt=nil
  if not u.returning then self:flyTo(u,cell)end
  return true,'fighter_moved'
 end
 -- A fighter that touches a foreign trade plane takes it over: the
 -- plane turns to the captor's nearest airport and its whole cargo goes to the captor on arrival.
 function Game:captureTradePlane(u,v)
  local s=self:nearestStructure(u.owner,'airport',v.cell);if not s or not s.land then return false end
  local victim=v.owner
  v.capturedFrom=v.capturedFrom or victim;v.owner=u.owner;v.captured=true
  v.destination=s.id;v.partner=u.owner;v.origin=nil
  local line=self:airLine(v.cell,s.land);v.route=line;v.index=1;v.progress=0;v.rail={line[1],line[#line]}
  u.kills+=1;u.level=math.min(3,math.floor(u.kills/3))
  self.captureNotice=self.captureNotice or {}
  -- One notice per victim every 15 s at most: a chase across a busy airway would flood the feed.
  if self.time-(self.captureNotice[victim]or -1e9)>15 then
   self.captureNotice[victim]=self.time
   self:notice(victim,'Fighters of '..(self.factions[u.owner]and self.factions[u.owner].name or '?')..' are intercepting your trade planes.')
  end
  self:notice(u.owner,'Trade plane intercepted: '..(self.factions[victim]and self.factions[victim].name or '?')..'. The cargo is yours.')
  return true
 end
 -- A fighter out of hit points stops fighting and flies to its nearest airport for repairs;
 -- with no airport left it is lost.
 function Game:retreat(u)
  local s=self:nearestStructure(u.owner,'airport',u.cell)
  if not s or not s.land then return false end
  u.hp=0;u.returning=true;self:flyTo(u,s.land);return true
 end
 function Game:flyTo(u,cell)
  local line=self:airLine(u.cell,cell);u.route=line;u.index=1;u.progress=0;u.rail={line[1],line[#line]}
 end
 -- Next turn of a patrol: a point inside PatrolRadius of the patrol centre, at least half the radius away,
 -- so the fighter keeps sweeping the area instead of hovering over one spot.
 function Game:patrolPoint(u)
  local w,h=self.grid.width,self.grid.height;local radius=R.PatrolRadius
  local c=self.grid:getCell(u.patrol);local here=self.grid:getCell(u.cell)
  local best,bestGap
  for _=1,6 do
   local a=self.random:NextNumber(0,math.pi*2);local r=radius*math.sqrt(self.random:NextNumber(.15,1))
   local x=math.clamp(math.floor(c.x+math.cos(a)*r+.5),1,w);local y=math.clamp(math.floor(c.y+math.sin(a)*r+.5),1,h)
   local gap=(x-here.x)^2+(y-here.y)^2
   if gap>=(radius*.5)^2 then return self.grid:cell(x,y).id end
   if not bestGap or gap>bestGap then best,bestGap=self.grid:cell(x,y).id,gap end
  end
  return best
 end
 -- The owner's ready structure of `kind` nearest to `cell` (ready(s) narrows it further).
 function Game:nearestStructure(owner,kind,cell,ready)
  local best,distance
  for _,s in ipairs(self.structures)do
   if s.owner==owner and s.kind==kind and self:activeStructure(s)and(not ready or ready(s))then
    local d=self:distance(s.cell,cell);if not distance or d<distance then best,distance=s,d end
   end
  end
  return best
 end
 function Game:launchFighterAt(owner,cell)
  local s=self:nearestStructure(owner,'airport',cell,function(s)return self:airport(owner,s.id)~=nil end)
  if not s then return false,'airport_required'end
  return self:launchFighter(owner,s.id,cell)
 end
 function Game:launchMissileAt(owner,cell,kind)
  local spec=R.Weapons[kind]
  if not spec or spec.internal then return false,'invalid'end
  -- Arsenal weapons need their unlock; bombers leave from an airport, not a platform (sim/NavalArsenal).
  if spec.arsenal and not self:has(owner,spec.arsenal)then return false,'locked'end
  if spec.airport then return self:launchBombers(owner,cell,kind)end
  local s=self:nearestStructure(owner,'silo',cell,function(s)return s.nextShot<=self.time end)
  if not s then return false,self:nearestStructure(owner,'silo',cell)and 'not_ready'or 'silo'end
  -- A torpedo: the nearest ready platform with a straight line of water to the aim.
  if spec.torpedo then
   if not R.cell(cell,self.grid.count)or not self.grid:isWater(cell)then return false,'water_required'end
   local clear=self:nearestStructure(owner,'silo',cell,function(a)return a.nextShot<=self.time and self:waterLine(a.cell,cell)end)
   if not clear then return false,'torpedo_line'end
   s=clear
  end
  return self:launchMissile(owner,s.id,cell,kind)
 end
 function Game:launchMissile(owner,source,target,kind)
  local spec=R.Weapons[kind];local s=self.structures[source];local f=self.factions[owner]
  if not spec or spec.internal or spec.airport then return false,'invalid'end
  if spec.arsenal and not self:has(owner,spec.arsenal)then return false,'locked'end
  if not s or s.dead or s.kind~='silo'or s.owner~=owner or not self:activeStructure(s)then return false,'silo'end
  if not R.cell(target,self.grid.count)or not self.grid:isWater(target)then return false,'water_required'end
  local enemy=self:owner(target)
  if enemy==owner or(enemy>0 and self:allied(owner,enemy))then return false,'invalid'end
  if enemy>0 and(self.time<self.factions[enemy].protectedUntil or(f.bot and not self:mayBotAttack(owner,enemy)))then return false,'protected'end
  local price=spec.cost+(kind=='mirv'and self.mirvs*15000000 or 0)
  if f.gold<price then return false,'gold'end
  if s.nextShot>self.time then return false,'not_ready'end
  if spec.torpedo and not self:waterLine(s.cell,target)then return false,'torpedo_line'end
  f.gold-=price;s.nextShot=self.time+self:reloadTime(s);self:structuresChanged();f.hasAttacked=true;if enemy>0 then self:recordHostility(owner,enemy)end
  if kind=='mirv'then self.mirvs+=1 end
  self:unit(owner,'missile',s.cell,nil,{weapon=kind,target=target,start=s.cell,flight=0,duration=math.max(3,self:distance(s.cell,target)/(spec.speed or 30)),hp=1})
  return true,'launched'
 end
 -- Whether a straight line from one cell to another crosses only water (the torpedo's way): every
 -- cell the line passes through, sampled at half-cell steps, is water.
 function Game:waterLine(from,to)
  local grid=self.grid;local a,b=grid:getCell(from),grid:getCell(to)
  local dx,dy=b.x-a.x,b.y-a.y;local steps=math.max(1,math.ceil(math.max(math.abs(dx),math.abs(dy))*2))
  for i=0,steps do
   local t=i/steps
   local id=grid:cell(math.floor(a.x+dx*t+.5),math.floor(a.y+dy*t+.5)).id
   if not grid:isWater(id)then return false end
  end
  return true
 end
 function Game:blast(owner,target,kind,quiet)
  local spec=R.Weapons[kind];local center=self.grid:getCell(target);local radius=spec.outer
  for y=math.max(1,center.y-radius),math.min(self.grid.height,center.y+radius)do
   for x=math.max(1,center.x-radius),math.min(self.grid.width,center.x+radius)do
    local c=self.grid:cell(x,y);local d=(x-center.x)^2+(y-center.y)^2
    local s=not c.water and d<=radius^2 and self.structureAt[c.id]
    -- Coastal land buildings inside the blast are destroyed under the same targeting rules.
    if s and not s.dead and s.owner~=owner and not self:allied(owner,s.owner)and self.time>=self.factions[s.owner].protectedUntil
     and(not self.factions[owner].bot or self:mayBotAttack(owner,s.owner))then s.dead=true;self.structureAt[c.id]=nil;self:structuresChanged()end
    if c.water and d<=radius^2 then
     local old=self:owner(c.id)
     -- Allied countries and protected starts are not collateral targets.
     if old==0 or(old~=owner and not self:allied(owner,old)and self.time>=self.factions[old].protectedUntil and(not self.factions[owner].bot or self:mayBotAttack(owner,old)))then
      self.fallout[c.id]=self.time+60
      if old>0 and(d<=spec.inner^2 or self.random:NextNumber()<.35)then
       local f=self.factions[old];f.fleet=math.max(0,f.fleet-f.fleet/math.max(1,f.count));self:_assign(c.id,0)
      end
      local s=self.structureAt[c.id];if s then s.dead=true;self.structureAt[c.id]=nil;self:structuresChanged()end
     end
    end
   end
  end
  if not quiet then self:notice(0,'Missile strike: '..spec.name)end
 end
 function Game:missileHit(u)
  if u.weapon=='mirv'then self:splitMirv(u);return end
  if R.Weapons[u.weapon].bomblets then self:splitCluster(u);return end
  if R.Weapons[u.weapon].shell then return end -- drawn only: the battery took the fleet as it fired
  self:blast(u.owner,u.target,u.weapon,u.weapon=='warhead'or u.weapon=='bomblet')
 end
 -- The MIRV carrier arrives: warheads for random cells of the target
 -- country's water within R.Mirv.spread of the aim, R.Mirv.gap apart, the aim itself first. Random tries
 -- are bounded, so a small or far-away country simply gets fewer warheads.
 function Game:splitMirv(u)
  local M=R.Mirv;local grid=self.grid;local w,h=grid.width,grid.height
  local aim=u.target;local tg=self:owner(aim)
  local targets={aim};local placed={grid:getCell(aim)}
  if tg>0 then
   local c=placed[1];local gap2=M.gap*M.gap
   for _=1,4000 do
    if #targets>=M.warheads then break end
    local a=self.random:NextNumber()*math.pi*2;local r=M.spread*math.sqrt(self.random:NextNumber())
    local x,y=c.x+math.floor(math.cos(a)*r+.5),c.y+math.floor(math.sin(a)*r+.5)
    if x>=1 and y>=1 and x<=w and y<=h then
     local id=(y-1)*w+x
     if grid:isWater(id)and self:owner(id)==tg then
      local free=true
      for _,p in ipairs(placed)do if(p.x-x)^2+(p.y-y)^2<gap2 then free=false;break end end
      if free then table.insert(targets,id);table.insert(placed,{x=x,y=y})end
     end
    end
   end
  end
  for _,id in ipairs(targets)do
   self:unit(u.owner,'missile',u.cell,nil,{weapon='warhead',target=id,start=u.cell,flight=0,duration=1.2+self.random:NextNumber()*1.3,hp=1})
  end
  self:notice(0,'Missile strike: MIRV · '..#targets..' warheads')
 end
 -- Value of one airport-to-airport run: grows with distance. Inside one country it pays 40%, once,
 -- the OpenFront train ratio for own stops (10k against 25k for another country).
 function Game:airTradeGold(s,dest)
  local gold=R.tradeGold(self:distance(s.land,dest.land))*math.min(s.level,dest.level)*R.TradeIncome
  return dest.owner==s.owner and gold*.4 or gold
 end
 -- Other ready airports, nearest first; `sameLand` keeps them on the rail-connected land (rivers bridged).
 function Game:airportsFrom(s,sameLand)
  local out={};local component=sameLand and self:railComponent(s.land)
  for _,other in ipairs(self.structures)do
   if other~=s and other.kind=='airport'and self:activeStructure(other)and(not component or self:railComponent(other.land)==component)then table.insert(out,other)end
  end
  table.sort(out,function(a,b)return self:distance(s.land,a.land)<self:distance(s.land,b.land)end)
  return out
 end
 function Game:sendPlane(s,dest)
  local route=self:airLine(s.land,dest.land)
  self:unit(s.owner,'tradeplane',route[1],route,{destination=dest.id,origin=s.id,gold=self:airTradeGold(s,dest),partner=dest.owner,visits=0,rail={route[1],route[#route]}})
 end
 -- Airports: the first plane leaves as soon as the airport is ready (to the nearest airport on the same land,
 -- so it cannot cash a long intercontinental run); then trains run often over the rails on that land
 -- and planes less often to any airport in the world.
 function Game:airportDispatch(s)
  if not s.firstFlight then
   -- Alone on its land: no first plane; the normal worldwide schedule starts instead.
   local near=self:airportsFrom(s,true)[1]
   s.firstFlight=true;s.nextFlight=self.time+R.FlightInterval;s.nextTrain=self.time+R.TrainInterval*.5
   if near then self:sendPlane(s,near)end
   return
  end
  if self.time>=(s.nextTrain or 0)then
   s.nextTrain=self.time+R.TrainInterval*self.random:NextNumber(.8,1.25)
   local partners=self:airportsFrom(s,true)
   local dest=partners[self.random:NextInteger(1,math.min(3,#partners))]
   if dest then
    local r=self:railState()
    if not r.stations[dest.id]then self:railConnect(dest,s)end
    if not r.stations[s.id]then self:railConnect(s,dest)end
    if not self:activeStructure(s)or not self:activeStructure(dest)then return end
    local cells,corners=self:railTrip(s,dest)
    if cells and #cells>1 then
     self:unit(s.owner,'train',cells[1],cells,{destination=dest.id,origin=s.id,gold=self:airTradeGold(s,dest),partner=dest.owner,visits=0,rail=corners})
    end
   end
  end
  if self.time>=(s.nextFlight or 0)then
   s.nextFlight=self.time+R.FlightInterval*self.random:NextNumber(.8,1.25)
   local all=self:airportsFrom(s,false)
   if #all>0 then self:sendPlane(s,all[self.random:NextInteger(1,#all)])end
  end
 end
 function Game:tradeDispatch(s)
  if s.kind=='airport'then if self:activeStructure(s)and self.factions[s.owner]and self.factions[s.owner].alive then self:airportDispatch(s)end;return end
  if not self:activeStructure(s)or s.nextTrade>self.time then return end
  s.nextTrade=self.time+12
  if s.kind~='oil'and s.kind~='gas'then return end
  local candidates={}
  for _,other in ipairs(self.structures)do
   if other~=s and self:activeStructure(other)then
    local allowed=other.kind=='port'and other.owner==s.owner and self:distance(s.cell,other.cell)<=R.StationRange
    if allowed then table.insert(candidates,other)end
   end
  end
  table.sort(candidates,function(a,b)return self:distance(s.cell,a.cell)<self:distance(s.cell,b.cell)end)
  local epoch=self.epoch
  for i=1,math.min(3,#candidates)do
   local dest=candidates[i]
   local route=self:surfacePath(s.cell,dest.water or dest.cell,true)
   if epoch~=self.epoch then return end
   if route and self:activeStructure(s)and self:activeStructure(dest)and self.factions[s.owner].alive then
    local gold=R.localGold(false,true)*(s.kind=='gas'and .5 or 1)*s.level*R.TradeIncome
    local cells,corners=self:straightWater(route)
    self:unit(s.owner,'merchant',cells[1],cells,{destination=dest.id,origin=s.id,gold=gold,partner=dest.owner,visits=0,rail=corners})
    return
   end
  end
 end
 function Game:arrive(u)
  if u.kind=='fighter'then
   -- A damaged fighter lands and waits at the airport until repaired; otherwise the patrol goes on.
   if u.returning then u.route=nil;return end
   -- Reached where the chased plane was: aim again at once (the chase runs right after the move).
   if u.hunt then u.huntRoute=0;return end
   self:flyTo(u,self:patrolPoint(u));return
  end
  if u.kind=='transport'then
   local f=self.factions[u.owner];local current=self:owner(u.target)
   if current~=u.attackOwner or(current>0 and((f.bot and not self:mayBotAttack(u.owner,current))or self:allied(u.owner,current)or self.time<self.factions[current].protectedUntil))then
    table.insert(self.returns,{owner=u.owner,amount=u.fleet*.75,at=self.time+2});self:notice(u.owner,'Landing called off: the target changed.');return
   end
   local enemy=current>0 and self.factions[current]or nil
   local loss,defense=R.battle(u.fleet,f,enemy,1,enemy and self:fortified(current,u.target),false)
   if u.fleet<=loss then self:notice(u.owner,'Landing repelled: the transport lost its whole fleet.');return end
   if enemy then enemy.fleet=math.max(0,enemy.fleet-defense);f.hasAttacked=true end
   self:_assign(u.target,u.owner)
   -- The landed force starts (or joins) the attack on that country; other orders run on.
   local ok=self:order(u.owner,u.target,u.fleet-loss,u.attackOwner)
   if not ok then f.fleet=math.min(self:cap(u.owner),f.fleet+u.fleet-loss)end
  else
   local s=self.structures[u.destination];local source=self.structures[u.origin]
   if u.captured then
    if s and s.owner==u.owner and self:activeStructure(s)then self.factions[u.owner].gold+=u.gold end
    return
   end
   if s and source and self:activeStructure(s)and self:activeStructure(source)and s.owner==u.partner and source.owner==u.owner then
    self.factions[u.owner].gold+=u.gold
    if u.partner~=u.owner then self.factions[u.partner].gold+=u.gold end
   end
  end
 end
 function Game:aviationTick(dt)
  -- Route searching yields; dispatch runs separately, with epoch/ownership revalidation.
  if not self.dispatchBusy then
   self.dispatchBusy=true;local epoch=self.epoch
   task.spawn(function()
    local ok,err=pcall(function()
     local n=0;for _ in pairs(self.units)do n+=1 end
     if n<320 then
      local total=#self.structures
      -- A newly ready airport sends its first plane right away instead of waiting for the cursor.
      local first=0
      for _,st in ipairs(self.structures)do
       if first>=2 or epoch~=self.epoch then break end
       if st.kind=='airport'and not st.firstFlight and self:activeStructure(st)then first+=1;self:tradeDispatch(st)end
      end
      for _=1,math.min(4,total)do
       if epoch~=self.epoch then break end
       self.dispatchCursor=(self.dispatchCursor or 0)%math.max(1,total)+1
       self:tradeDispatch(self.structures[self.dispatchCursor])
      end
     end
     if epoch==self.epoch and self.time>=(self.nextRailCheck or 0)then self.nextRailCheck=self.time+3;self:railNetworkTick()end
    end)
    self.dispatchBusy=false;if not ok then warn('[SeaBattle trade] '..tostring(err))end
   end)
  end
  local remove={}
  -- Fighters search nearby buckets instead of every unit on the map.
  local buckets={};local width=self.grid.width
  local function bucketKey(cell)return math.floor(((cell-1)%width)/32)..':'..math.floor(math.floor((cell-1)/width)/32)end
  for _,v in pairs(self.units)do if v.kind~='missile'and v.kind~='merchant'then
   local key=bucketKey(v.cell);buckets[key]=buckets[key]or {};table.insert(buckets[key],v)
  end end
  for id,u in pairs(self.units)do
   if not self.factions[u.owner].alive or(u.hp<=0 and not u.returning)then remove[id]=true;continue end
   if u.kind=='missile'then
    -- An intercepted missile stays in the air a moment so clients can draw the defence's shot at it.
    if u.hitBy then if self.time>=u.dieAt then remove[id]=true end;continue end
    u.flight+=dt;local t=math.min(1,u.flight/u.duration)
    local a,b=self.grid:getCell(u.start),self.grid:getCell(u.target)
    u.cell=self.grid:cell(math.clamp(math.floor(a.x+(b.x-a.x)*t),1,self.grid.width),math.clamp(math.floor(a.y+(b.y-a.y)*t),1,self.grid.height)).id
    for _,s in ipairs(self:nearStructures(u.cell,108))do
     if s.kind=='sam'and self:activeStructure(s)and s.owner~=u.owner and not self:allied(u.owner,s.owner)and s.nextShot<=self.time and self:distance(s.cell,u.cell)<=R.samRange(s.level)and u.weapon~='mirv'and not R.Weapons[u.weapon].torpedo and not R.Weapons[u.weapon].shell and not self:evades(u,s)then
      s.nextShot=self.time+self:reloadTime(s);self:structuresChanged();u.hitBy=s.id;u.dieAt=self.time+R.InterceptShow
      self:notice(s.owner,'Missile defense intercepted a missile');break
     end
    end
    if t>=1 and not remove[id]and not u.hitBy then self:missileHit(u);remove[id]=true end
   else
    if u.route then
     local speed=u.kind=='fighter'and R.FighterSpeed*(u.hunt and R.HuntBoost or 1)or u.kind=='train'and R.TrainSpeed or u.kind=='merchant'and 6 or R.AircraftSpeed
     u.progress+=dt*speed
     while u.progress>=1 and u.index<#u.route do u.progress-=1;u.index+=1;u.cell=u.route[u.index]end
     if u.index>=#u.route then self:arrive(u);if u.kind~='fighter'then remove[id]=true end end
    end
    if u.kind=='fighter'then
     for _,s in ipairs(self:nearStructures(u.cell,R.AirportRepairRange))do
      if s.owner==u.owner and s.kind=='airport'and self:activeStructure(s)then u.hp=math.min(1000,u.hp+dt*(self:distance(u.cell,s.land or s.cell)<3 and 80 or 12));break end
     end
     -- Repaired at the airport: back to the patrol area.
     if u.returning and not u.route and u.hp>=1000 then u.returning=nil;self:flyTo(u,self:patrolPoint(u))end
     if not u.returning then
      -- One look around per step: the nearest enemy fighter or invasion transport within FighterRange to
      -- shoot, and the nearest foreign trade plane within FighterHunt (and near the patrol area) to chase.
      local target,distance,prey,preyDistance
      local patrol=u.patrol or u.cell
      local bx,by=math.floor(((u.cell-1)%width)/32),math.floor(math.floor((u.cell-1)/width)/32)
      for yy=by-1,by+1 do for xx=bx-1,bx+1 do for _,v in ipairs(buckets[xx..':'..yy]or {})do
       local tid=v.id
       if tid~=id and self.units[tid]==v and v.owner~=u.owner and not remove[tid]and not self:allied(u.owner,v.owner)then
        if(v.kind=='fighter'or v.kind=='transport')and not v.returning then
         local d=self:distance(u.cell,v.cell);if d<=R.FighterRange and(not distance or d<distance)then target,distance=v,d end
        elseif v.kind=='tradeplane'and v.route then
         local d=self:distance(u.cell,v.cell)
         if d<=R.FighterHunt and(not preyDistance or d<preyDistance)and self:distance(patrol,v.cell)<=R.PatrolRadius+R.FighterHunt then prey,preyDistance=v,d end
        end
       end
      end end end
      if target and u.nextShot<=self.time then
       u.nextShot=self.time+1;target.hp-=R.FighterDamage*(1+u.level*.25)
       -- Each shot is numbered so clients can draw one small projectile per shot.
       u.shots=(u.shots or 0)+1;u.shot=u.shots..':'..target.id
       if target.hp<=0 and target.kind=='fighter'and self:retreat(target)then
        u.kills+=1;u.level=math.min(3,math.floor(u.kills/3))
       elseif target.hp<=0 then u.kills+=1;u.level=math.min(3,math.floor(u.kills/3));remove[target.id]=true;self:notice(u.owner,'Intercepted: '..target.kind)
        if target.kind=='transport'then self:notice(target.owner,'Transport plane shot down with its fleet.')end
       end
      end
      -- Enemy combat aircraft come first: a fighter in a dogfight does not break off to chase cargo.
      if prey and not target then
       if preyDistance<=R.CaptureRange then
        if self:captureTradePlane(u,prey)then u.hunt=nil;self:flyTo(u,self:patrolPoint(u))end
       elseif u.hunt~=prey.id or self.time>=(u.huntRoute or 0)then
        -- Re-aim at the plane's current spot twice a second.
        u.hunt=prey.id;u.huntRoute=self.time+.5;self:flyTo(u,prey.cell)
       end
      elseif u.hunt then u.hunt=nil;self:flyTo(u,self:patrolPoint(u))end
     end
    end
   end
  end
  for id in pairs(remove)do self.units[id]=nil end
 end
 function Game:publicUnits()
  local out={};for _,u in pairs(self.units)do
   local trade=u.kind=='merchant'or u.kind=='train'or u.kind=='tradeplane'
   table.insert(out,{id=u.id,owner=u.owner,kind=u.kind,cell=u.cell,hp=math.floor(u.hp),level=u.level,weapon=u.weapon,fleet=u.fleet and math.floor(u.fleet),shot=u.shot,returning=u.returning==true,hitBy=u.hitBy,patrol=u.kind=='fighter'and u.patrol or nil,captured=u.captured or nil,
    -- A missile's destination is its target cell: clients shade the area it will hit.
    origin=trade and u.origin or nil,destination=trade and u.destination or(u.kind=='missile'and u.target)or nil,rail=u.route and u.rail or nil,
    along=u.route and math.floor(((u.index or 1)-1+(u.progress or 0))*10+.5)/10 or nil,steps=u.route and #u.route-1 or nil})
  end;return out
 end
end
return M
