--!nonstrict
-- Independent geometry for pixel ownership, outside borders and country label placement.
local G={}
function G.owner(owners,id)return id and buffer.readu8(owners,id-1) or 0 end
-- yieldWork: spread the search over frames, at most ~1.5 ms of work per frame (phones felt longer slices).
function G.largest(grid,owners,owned,owner,yieldWork)
 local seen={};local best=nil;local work=0;local width=grid.width;local slice=os.clock()
 local function pause()if os.clock()-slice>.0015 then task.wait();slice=os.clock()end end
 for start in pairs(owned)do
  if seen[start] or G.owner(owners,start)~=owner then continue end
  local queue,head={start},1;seen[start]=true
  local origin=(start-1)%width;local sx,sy=0,0
  local minX,maxX,minY,maxY=math.huge,-math.huge,math.huge,-math.huge
  while head<=#queue do
   local id=queue[head];head+=1;work+=1
   local x,y=(id-1)%width,math.floor((id-1)/width)
   if grid.data.wrapX then x=origin+((x-origin+width/2)%width-width/2)end
   sx+=x;sy+=y;minX=math.min(minX,x);maxX=math.max(maxX,x);minY=math.min(minY,y);maxY=math.max(maxY,y)
   for _,n in ipairs(grid:neighborIds(id))do
    if not seen[n] and G.owner(owners,n)==owner then seen[n]=true;table.insert(queue,n)end
   end
   if yieldWork and work%128==0 then pause()end
  end
  if not best or #queue>best.area then
   local cx,cy=sx/#queue,sy/#queue;local cell,distance=start,math.huge
   for k,id in ipairs(queue)do
    if yieldWork and k%512==0 then pause()end
    local x,y=(id-1)%width,math.floor((id-1)/width)
    if grid.data.wrapX then x=origin+((x-origin+width/2)%width-width/2)end
    local d=(x-cx)^2+(y-cy)^2
    if d<distance then cell,distance=id,d end
   end
   best={cell=cell,area=#queue,width=maxX-minX+1,height=maxY-minY+1}
  end
 end
 return best
end
function G.chunk(grid,owners,x0,y0,size)
 local w,h=grid.width,grid.height
 local x1,y1=math.min(w,x0+size),math.min(h,y0+size)
 local active,rects={},{}
 for y=y0,y1-1 do
  local current={};local x=x0
  while x<x1 do
   local owner=G.owner(owners,y*w+x+1);local finish=x+1
   while finish<x1 and G.owner(owners,y*w+finish+1)==owner do finish+=1 end
   if owner>0 then
    local key=x..":"..finish..":"..owner;local r=active[key]
    if r then active[key]=nil;r.h+=1 else r={x=x,y=y,w=finish-x,h=1,owner=owner}end
    current[key]=r
   end
   x=finish
  end
  for _,r in pairs(active)do table.insert(rects,r)end;active=current
 end
 for _,r in pairs(active)do table.insert(rects,r)end
 local horizontal,vertical={},{}
 -- Edges keep the neighbour too, so a view can style the boundary between two specific countries.
 local function edge(t,line,at,owner,other)
  local key=line..":"..owner..":"..other;local e=t[key]
  if not e then e={line=line,owner=owner,other=other,values={}};t[key]=e end
  table.insert(e.values,at)
 end
 local function ownerAt(x,y)
  if y<0 or y>=h then return 0 end
  if grid.data.wrapX then x=x%w elseif x<0 or x>=w then return 0 end
  return G.owner(owners,y*w+x+1)
 end
 local function boundary(owner,other)
  -- Shared boundaries are drawn once, avoiding coplanar opaque surfaces.
  return owner~=other and (other==0 or owner<other)
 end
 for y=y0,y1-1 do for x=x0,x1-1 do
  local owner=ownerAt(x,y)
  if owner>0 then
   local up,down,left,right=ownerAt(x,y-1),ownerAt(x,y+1),ownerAt(x-1,y),ownerAt(x+1,y)
   if boundary(owner,up)then edge(horizontal,y,x,owner,up)end
   if boundary(owner,down)then edge(horizontal,y+1,x,owner,down)end
   if boundary(owner,left)then edge(vertical,x,y,owner,left)end
   if boundary(owner,right)then edge(vertical,x+1,y,owner,right)end
  end
 end end
 for orientation,t in ipairs({horizontal,vertical})do
  for _,e in pairs(t)do
   table.sort(e.values);local first,last
   local function flush()
    if first then
     table.insert(rects,orientation==1 and {x=first,y=e.line-.1,w=last-first+1,h=.2,owner=e.owner,other=e.other,border=true}
      or {x=e.line-.1,y=first,w=.2,h=last-first+1,owner=e.owner,other=e.other,border=true})
    end
   end
   for _,at in ipairs(e.values)do
    if last and at==last+1 then last=at else flush();first,last=at,at end
   end
   flush()
  end
 end
 return rects
end
return G
