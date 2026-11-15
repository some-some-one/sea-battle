--!native
--!nonstrict
-- Surface-constrained A*: no range cutoff, bounded map, cached immutable geography.
local Coop=require(script.Parent.Coop)
local Routes={};Routes.__index=Routes
-- Paths kept (trade runs between the same buildings repeat every few seconds; a late match has
-- hundreds of them, and a smaller cache was emptied before they came round again).
local CACHE=1024
function Routes.new(grid)return setmetatable({grid=grid,cache={},count=0},Routes)end
local function push(h,n)
 local i=#h+1;while i>1 do local p=math.floor(i/2);if h[p].f<=n.f then break end;h[i]=h[p];i=p end;h[i]=n
end
local function pop(h)
 local top,last=h[1],table.remove(h);if #h>0 then local i=1
 while i*2<=#h do local c=i*2;if c<#h and h[c+1].f<h[c].f then c+=1 end;if last.f<=h[c].f then break end;h[i]=h[c];i=c end;h[i]=last end;return top
end
-- `water` is true (sea routes), false (land) or 'rail' (land plus river cells: rails cross rivers on bridges).
local function passable(g,id,water)
 local wet=buffer.readu8(g.waterMask,id-1)==1
 if water=='rail'then return not wet or g.data.palette[g:paletteId(id)].kind=='river'end
 return wet==water
end
Routes.passable=passable
function Routes:find(a,b,water)
 if not a or not b then return nil end
 if self.count>CACHE then self.cache={};self.count=0 end
 local key=a..":"..b..":"..tostring(water)
 if self.cache[key]~=nil then return self.cache[key]or nil end
 local g=self.grid;if not a or not b or not passable(g,a,water)or not passable(g,b,water)then return nil end
 if a==b then return {a}end
 local w=g.width;local bx,by=(b-1)%w,(b-1)//w
 -- (2026-11-15, for phones: the heap holds ids and scores in two arrays instead of a table per node,
 -- and neighbours come from grid:nb4; the same pushes and pops in the same order, so the same paths)
 local hid,hf={a},{math.abs((a-1)%w-bx)+math.abs((a-1)//w-by)}
 local from,score,done={[a]=0},{[a]=0},{};local visits=0;local pace={t=os.clock()}
 while #hid>0 do
  -- pop
  local id=hid[1];local n=#hid;local lastId,lastF=hid[n],hf[n];hid[n]=nil;hf[n]=nil;n-=1
  if n>0 then
   local i=1
   while i*2<=n do
    local c=i*2;if c<n and hf[c+1]<hf[c]then c+=1 end
    if lastF<=hf[c]then break end
    hid[i]=hid[c];hf[i]=hf[c];i=c
   end
   hid[i]=lastId;hf[i]=lastF
  end
  if done[id]then continue end;done[id]=true
  if id==b then
   local reverse={};while id~=0 do table.insert(reverse,id);id=from[id]end
   local path=table.create(#reverse);for i=#reverse,1,-1 do table.insert(path,reverse[i])end
   if self.count>CACHE then self.cache={};self.count=0 end
   self.cache[key]=path;self.count+=1;return path
  end
  local n1,n2,n3,n4=g:nb4(id)
  for k=1,4 do
   local nextId=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
   if nextId>0 and not done[nextId]and passable(g,nextId,water)then
    local cost=score[id]+1
    if not score[nextId]or cost<score[nextId]then
     score[nextId]=cost;from[nextId]=id
     -- push
     local f=cost+math.abs((nextId-1)%w-bx)+math.abs((nextId-1)//w-by)
     local i=#hid+1
     while i>1 do local p=i//2;if hf[p]<=f then break end;hid[i]=hid[p];hf[i]=hf[p];i=p end
     hid[i]=nextId;hf[i]=f
    end
   end
  end
  -- Long searches give the frame back after a slice of work (Coop.pace), not after a fixed count.
  visits+=1;if visits%256==0 then Coop.pace(pace)end
 end
 self.cache[key]=false;self.count+=1;return nil
end
-- Multi-source surface search: all valid shores/landing sides participate.
-- The geography is immutable; ownership is revalidated by the caller after yielding.
function Routes:between(sources,targets,water)
 local g=self.grid;local q,from,root={},{},{}
 for id,source in pairs(sources)do if g:isWater(id)==water then from[id]=0;root[id]=source;table.insert(q,id)end end
 local head=1;local pace={t=os.clock()}
 while head<=#q do
  local id=q[head];head+=1
  if targets[id]then
   local finish=id;local reverse={}
   while id~=0 do table.insert(reverse,id);id=from[id]end
   local path={};for i=#reverse,1,-1 do table.insert(path,reverse[i])end
   return path,root[finish],targets[finish]
  end
  local n1,n2,n3,n4=g:nb4(id)
  for k=1,4 do
   local n=k==1 and n1 or k==2 and n2 or k==3 and n3 or n4
   if n>0 and from[n]==nil and g:isWater(n)==water then from[n]=id;root[n]=root[id];table.insert(q,n)end
  end
  if head%256==0 then Coop.pace(pace)end
 end
 return nil
end
return Routes
