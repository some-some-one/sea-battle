--!native
--!nonstrict
-- Geography uses compact buffers; cell records are materialized only on demand.
local Coop=require(script.Parent.Coop)
local Grid={}
Grid.__index=Grid
local function decode(rows,w,h,bytes,yieldWork)
 local out=buffer.create(w*h*bytes);local pace={t=os.clock()}
 for y,row in ipairs(rows) do
  local x=0
  local function run(n,value)
   if bytes==1 then buffer.fill(out,(y-1)*w+x,value,n)
   else for k=0,n-1 do buffer.writeu32(out,((y-1)*w+x+k)*4,value) end end
   x+=n
  end
  if type(row)=="string" then
   local step=bytes==1 and 6 or 8
   for p=1,#row,step do run(tonumber(row:sub(p,p+3),16),tonumber(row:sub(p+4,p+step-1),16)) end
  else for k=1,#row,2 do run(row[k],row[k+1]) end end
  assert(x==w,"Invalid atlas row "..y)
  if yieldWork and y%8==0 then Coop.loadPace(pace) end
 end
 assert(#rows==h,"Incomplete atlas")
 return out
end
function Grid.new(data,options)
 local yieldWork=not options or options.yieldWork~=false
 local self=setmetatable({data=data,width=data.width,height=data.height,count=data.width*data.height,regions={},basins={}},Grid)
 self.paletteIds=decode(data.rows,self.width,self.height,1,yieldWork)
 -- Water as one byte per cell (1 = water): isWater is the hottest question the match asks, millions of
 -- times a minute, and a palette lookup each time was a measurable share of a phone's frame.
 self.waterMask=buffer.create(self.count)
 do
  local palette,ids,mask=data.palette,self.paletteIds,self.waterMask;local pace={t=os.clock()}
  for i=0,self.count-1 do
   local p=palette[buffer.readu8(ids,i)];if p and p.water then buffer.writeu8(mask,i,1) end
   if yieldWork and i%65536==0 then Coop.loadPace(pace) end
  end
 end
 if data.regionRows then
  self.regionIds=decode(data.regionRows,self.width,self.height,4,yieldWork)
  self.basinIds=decode(data.basinRows,self.width,self.height,4,yieldWork)
  for _,source in ipairs(data.regions) do
   local r=table.clone(source);r.cells=table.create(r.count);table.insert(self.regions,r)
  end
  for id,size in ipairs(data.stats.basinSizes) do self.basins[id]={id=id,size=size} end
  local pace={t=os.clock()}
  for id=1,self.count do
   local rid=buffer.readu32(self.regionIds,(id-1)*4)
   if rid>0 then table.insert(self.regions[rid].cells,id) end
   if yieldWork and id%8192==0 then Coop.loadPace(pace) end
  end
 else
  -- Synthetic fixtures can calculate topology without the offline build step.
  self.regionIds=buffer.create(self.count*4);self.basinIds=buffer.create(self.count*4)
  for id=1,self.count do
   if not self:isWater(id) or self:basinId(id)>0 then continue end
   local b={id=#self.basins+1,size=0};table.insert(self.basins,b)
   local q,head={id},1;buffer.writeu32(self.basinIds,(id-1)*4,b.id)
   while head<=#q do
    local current=q[head];head+=1;b.size+=1
    for _,n in ipairs(self:neighborIds(current)) do
     if self:isWater(n) and self:basinId(n)==0 then buffer.writeu32(self.basinIds,(n-1)*4,b.id);table.insert(q,n) end
    end
   end
  end
  local size=data.sectorSize
  for id=1,self.count do
   if not self:isWater(id) or self:regionId(id)>0 then continue end
   local sx,sy=math.floor(((id-1)%self.width)/size),math.floor(math.floor((id-1)/self.width)/size)
   local r={id=#self.regions+1,cells={},neighbors={},basinId=self:basinId(id),centerX=0,centerY=0,coastal=false}
   table.insert(self.regions,r)
   local q,head={id},1;buffer.writeu32(self.regionIds,(id-1)*4,r.id)
   while head<=#q do
    local current=q[head];head+=1;table.insert(r.cells,current)
    r.centerX+=(current-1)%self.width+1;r.centerY+=math.floor((current-1)/self.width)+1
    for _,n in ipairs(self:neighborIds(current)) do
     if not self:isWater(n) then r.coastal=true end
     if self:isWater(n) and self:regionId(n)==0 and math.floor(((n-1)%self.width)/size)==sx and math.floor(math.floor((n-1)/self.width)/size)==sy then
      buffer.writeu32(self.regionIds,(n-1)*4,r.id);table.insert(q,n)
     end
    end
   end
   r.count=#r.cells;r.centerX/=r.count;r.centerY/=r.count
  end
  for _,r in ipairs(self.regions) do
   local adjacency={}
   for _,id in ipairs(r.cells) do
    for _,n in ipairs(self:neighborIds(id)) do
     local rid=self:regionId(n)
     if rid>0 and rid~=r.id then adjacency[rid]=true end
    end
   end
   for rid in pairs(adjacency) do table.insert(r.neighbors,rid) end
   table.sort(r.neighbors)
  end
 end
 return self
end
function Grid:paletteId(id) return buffer.readu8(self.paletteIds,id-1) end
function Grid:regionId(id) return buffer.readu32(self.regionIds,(id-1)*4) end
function Grid:basinId(id) return buffer.readu32(self.basinIds,(id-1)*4) end
function Grid:isWater(id) return buffer.readu8(self.waterMask,id-1)==1 end
-- The four neighbours (left, right, up, down; the order of neighborIds) as four ids, 0 where there is
-- none: the match's inner loops ask this per captured cell, and a fresh table each time kept a phone's
-- garbage collector busy.
function Grid:nb4(id)
 local w=self.width;local x=(id-1)%w
 local l,r,u,d=0,0,0,0
 if x>0 then l=id-1 elseif self.data.wrapX then l=id+w-1 end
 if x<w-1 then r=id+1 elseif self.data.wrapX then r=id-w+1 end
 if id>w then u=id-w end
 if id<=self.count-w then d=id+w end
 return l,r,u,d
end
function Grid:getCell(id)
 if type(id)~="number" or id%1~=0 or id<1 or id>self.count then return nil end
 local pid=self:paletteId(id);local p=self.data.palette[pid]
 return {id=id,x=(id-1)%self.width+1,y=math.floor((id-1)/self.width)+1,paletteId=pid,water=p.water,kind=p.kind,depth=p.depth,biome=p.biome,regionId=self:regionId(id),basinId=self:basinId(id)}
end
function Grid:cell(x,y)
 if x%1~=0 or y%1~=0 or x<1 or x>self.width or y<1 or y>self.height then return nil end
 return self:getCell((y-1)*self.width+x)
end
function Grid:neighborIds(id)
 local x,y=(id-1)%self.width,math.floor((id-1)/self.width)
 local out=table.create(4)
 if x>0 then table.insert(out,id-1) elseif self.data.wrapX then table.insert(out,id+self.width-1) end
 if x<self.width-1 then table.insert(out,id+1) elseif self.data.wrapX then table.insert(out,id-self.width+1) end
 if y>0 then table.insert(out,id-self.width) end
 if y<self.height-1 then table.insert(out,id+self.width) end
 return out
end
function Grid:neighbors(id)
 local out={};for _,n in ipairs(self:neighborIds(id)) do table.insert(out,self:getCell(n)) end;return out
end
function Grid:worldToCell(position)
 local s=self.data.tileSize
 return self:cell(math.floor(position.X/s+self.width/2)+1,math.floor(position.Z/s+self.height/2)+1)
end
function Grid:cellToWorld(x,y)
 return Vector3.new((x-.5-self.width/2)*self.data.tileSize,0,(y-.5-self.height/2)*self.data.tileSize)
end
function Grid:geoToCell(lon,lat)
 if not self.data.bounds then return nil end
 local b=self.data.bounds
 if lon<b.west or lon>b.east or lat<b.south or lat>b.north then return nil end
 return self:cell(math.min(self.width,math.floor((lon-b.west)/(b.east-b.west)*self.width)+1),math.min(self.height,math.floor((b.north-lat)/(b.north-b.south)*self.height)+1))
end
function Grid:cellToGeo(x,y)
 if not self.data.bounds then return nil end
 local b=self.data.bounds
 return b.west+(x-.5)/self.width*(b.east-b.west),b.north-(y-.5)/self.height*(b.north-b.south)
end
-- Bounded BFS memory, including routes across the Pacific date-line seam.
function Grid:findPath(startId,goalId,draft)
 draft=draft or 1
 local first,last=self:getCell(startId),self:getCell(goalId)
 if not first or not last or not first.water or not last.water or first.depth<draft or last.depth<draft or first.basinId~=last.basinId then return nil end
 local previous,queue=buffer.create(self.count*4),buffer.create(self.count*4)
 local head,tail=0,1
 buffer.writeu32(queue,0,startId);buffer.writeu32(previous,(startId-1)*4,startId)
 while head<tail do
  local id=buffer.readu32(queue,head*4);head+=1
  if id==goalId then
   local backwards={}
   while id~=startId do table.insert(backwards,id);id=buffer.readu32(previous,(id-1)*4) end
   table.insert(backwards,startId)
   local path=table.create(#backwards)
   for k=#backwards,1,-1 do table.insert(path,backwards[k]) end
   return path
  end
  for _,n in ipairs(self:neighborIds(id)) do
   local p=self.data.palette[self:paletteId(n)]
   if p.water and p.depth>=draft and buffer.readu32(previous,(n-1)*4)==0 then
    buffer.writeu32(previous,(n-1)*4,id);buffer.writeu32(queue,tail*4,n);tail+=1
   end
  end
  if head%32768==0 then task.wait() end
 end
 return nil
end
return Grid
