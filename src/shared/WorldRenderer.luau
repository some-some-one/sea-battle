--!nonstrict
-- The baked overview fills river channels with land to keep continents clear.
-- Detailed full-resolution chunks restore the real rivers and their banks
-- only near the camera, and evicted when the player explores another region.
local Coop=require(script.Parent.Coop)
local Renderer={}
Renderer.__index=Renderer
local CHUNK=48
function Renderer.new(grid)
	local self=setmetatable({grid=grid,data=grid.data,cache={},clock=0,busy=false,
		overview=workspace:WaitForChild("SeaBattleWorld"),root=Instance.new("Folder")},Renderer)
	-- Optional display raster is independent of water, depth and territory data.
	if grid.data.displayRows then
		self.displayIds=buffer.create(grid.count);local pace={t=os.clock()}
		for y,row in ipairs(grid.data.displayRows) do
			local x=0
			for k=1,#row,6 do
				local count=tonumber(row:sub(k,k+3),16)
				local pid=tonumber(row:sub(k+4,k+5),16)
				buffer.fill(self.displayIds,(y-1)*grid.width+x,pid,count);x+=count
			end
			assert(x==grid.width,"Invalid display row")
			if y%8==0 then Coop.loadPace(pace) end
		end
	end
	return self
end
function Renderer:displayId(id)
	return self.displayIds and buffer.readu8(self.displayIds,id-1) or self.grid:paletteId(id)
end
function Renderer:build(cx,cy)
	local d=self.data;local s=d.tileSize
	local x0,y0=cx*CHUNK,cy*CHUNK
	local x1,y1=math.min(d.width,x0+CHUNK),math.min(d.height,y0+CHUNK)
	local model=Instance.new("Folder");model.Name=string.format("Detail_%d_%d",cx,cy)
	local active={};local completed={}
	for y=y0,y1-1 do
		local current={};local x=x0
		while x<x1 do
			local pid=self:displayId(y*d.width+x+1)
			local finish=x+1
			while finish<x1 and self:displayId(y*d.width+finish+1)==pid do finish+=1 end
			local key=x..":"..finish..":"..pid
			local rect=active[key]
			if rect then active[key]=nil;rect.h+=1 else rect={x=x,y=y,w=finish-x,h=1,pid=pid} end
			current[key]=rect;x=finish
		end
		for _,rect in pairs(active) do table.insert(completed,rect) end
		active=current
	end
	for _,rect in pairs(active) do table.insert(completed,rect) end
	for _,r in ipairs(completed) do
		local p=Instance.new("Part")
		p.Name="PixelSpan";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
		p.Material=Enum.Material.SmoothPlastic
		p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
		p.Size=Vector3.new(r.w*s,.006,r.h*s)
		p.Position=Vector3.new((r.x+r.w/2-d.width/2)*s,.012,(r.y+r.h/2-d.height/2)*s)
		p.Color=Color3.fromRGB(table.unpack((d.displayPalette or d.palette)[r.pid].color))
		p.Parent=model
	end
	return model
end
-- Chunks kept built (shown or not): enough for the whole view at the detail zoom plus a margin, so
-- panning back and forth reuses them instead of building them again.
local CACHE=400
-- Building work per frame; chunks already built are shown at once, at no cost.
local BUDGET=.006
function Renderer:update(focus,halfX,halfY,zoom)
	if self.busy then return end
	if not self.root.Parent then self.root.Name="SeaBattleDetailedWorld";self.root.Parent=workspace end
	-- Never downsample river channels into scattered overview pixels.
	if self.data.overviewStride<=1 or zoom>(self.data.detailZoom or .38) then
		for _,entry in pairs(self.cache) do entry.model.Parent=nil end
		return
	end
	self.busy=true;self.clock+=1
	local s=self.data.tileSize;local w,h=self.data.width,self.data.height
	local fx,fy=focus.X/s+w/2,focus.Y/s+h/2
	-- The view and one chunk around it (ready before it scrolls in).
	local minCX=math.max(0,math.floor((fx-halfX/s)/CHUNK)-1);local maxCX=math.min(math.floor((w-1)/CHUNK),math.floor((fx+halfX/s)/CHUNK)+1)
	local minCY=math.max(0,math.floor((fy-halfY/s)/CHUNK)-1);local maxCY=math.min(math.floor((h-1)/CHUNK),math.floor((fy+halfY/s)/CHUNK)+1)
	local list,needed={},{}
	for cy=minCY,maxCY do for cx=minCX,maxCX do
		local key=cx..":"..cy;needed[key]=true
		local dx,dy=(cx+.5)*CHUNK-fx,(cy+.5)*CHUNK-fy
		table.insert(list,{key=key,cx=cx,cy=cy,d=dx*dx+dy*dy})
	end end
	-- The middle of the screen first, then outwards: no sweep of rows across the view.
	table.sort(list,function(a,b)return a.d<b.d end)
	local began=os.clock()
	for _,c in ipairs(list)do
		local entry=self.cache[c.key]
		if not entry then
			if os.clock()-began>BUDGET then task.wait();began=os.clock() end
			entry={model=self:build(c.cx,c.cy)};self.cache[c.key]=entry
		end
		entry.used=self.clock
		if entry.model.Parent~=self.root then entry.model.Parent=self.root end
	end
	local count=0;local hidden={}
	for key,entry in pairs(self.cache) do
		count+=1
		if not needed[key] then
			if entry.model.Parent then entry.model.Parent=nil end
			table.insert(hidden,{key=key,used=entry.used})
		end
	end
	table.sort(hidden,function(a,b) return a.used<b.used end)
	for _,old in ipairs(hidden) do
		if count<=CACHE then break end
		self.cache[old.key].model:Destroy();self.cache[old.key]=nil;count-=1
	end
	self.busy=false
end
return Renderer
