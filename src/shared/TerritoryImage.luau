--!native
--!nonstrict
-- Territory as pixels: one map cell is one pixel of an EditableImage,
-- shown on flat parts through a SurfaceGui with pixelated resampling. Changing an owner rewrites
-- four bytes; per frame only the dirty rows of one image are uploaded (Roblox shows one EditableImage
-- update per frame). Replaces tens of thousands of fill and border Parts with two images.
local AssetService=game:GetService("AssetService")
local T={};T.__index=T
local TILE=720 -- per side; EditableImage allows up to 1024
-- Uploads (flush): rows per band, the most pixels one frame sends, and the column step uploads round to.
local BAND,MAX_PIXELS,ALIGN=16,720*16*4,48

-- colorFor(id) returns r,g,b,a in 0..255. There is no fallback: if the device cannot create the image the
-- client errors, so a running map is always this image.
function T.new(grid,parent,colorFor)
 local w,h,s=grid.width,grid.height,grid.data.tileSize
 local self=setmetatable({grid=grid,colorFor=colorFor,tiles={},next=1},T)
 local folder=Instance.new("Folder");folder.Name="TerritoryImage"
 for ty=0,math.ceil(h/TILE)-1 do for tx=0,math.ceil(w/TILE)-1 do
  local x0,y0=tx*TILE,ty*TILE;local tw,th=math.min(TILE,w-x0),math.min(TILE,h-y0)
  local img=AssetService:CreateEditableImage({Size=Vector2.new(tw,th)})
  assert(img,"[SeaBattle] EditableImage unavailable: enable Allow Mesh / Image APIs (Game Settings > Security)")
  local p=Instance.new("Part");p.Name="Tile";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
  -- A Top-face SurfaceGui lays canvas X along the part's -Z; turning the part -90° about Y puts
  -- canvas X along world +X (east) and canvas Y along world +Z (south), matching cell coordinates.
  p.Transparency=1;p.Size=Vector3.new(th*s,.002,tw*s)
  p.CFrame=CFrame.new((x0+tw/2-w/2)*s,.016,(y0+th/2-h/2)*s)*CFrame.Angles(0,math.rad(-90),0);p.Parent=folder
  local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
  -- Lit like the map parts underneath, so the wash stays as calm as the old part fills.
  gui.CanvasSize=Vector2.new(tw,th);gui.LightInfluence=1;gui.Brightness=1;gui.Adornee=p;gui.Parent=p
  local label=Instance.new("ImageLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
  label.ResampleMode=Enum.ResamplerMode.Pixelated;label.ImageContent=Content.fromObject(img);label.Parent=gui
  table.insert(self.tiles,{x0=x0,y0=y0,w=tw,h=th,img=img,pixels=buffer.create(tw*th*4),left={},right={},queue={},head=1})
 end end
 self.columns=math.ceil(w/TILE)
 folder.Parent=parent;self.folder=folder
 print(string.format("[SeaBattle] territory drawn as %d EditableImage tiles",#self.tiles))
 return self
end
function T:tileOf(x,y)return self.tiles[(y//TILE)*self.columns+(x//TILE)+1]end
-- Recolour one cell.
function T:paint(id)
 local w=self.grid.width;local x,y=(id-1)%w,(id-1)//w
 local t=self:tileOf(x,y);if not t then return end
 local r,g,b,a=self.colorFor(id)
 local ly=y-t.y0;local o=(ly*t.w+(x-t.x0))*4;local px=t.pixels
 if buffer.readu8(px,o+3)==a and buffer.readu8(px,o)==r and buffer.readu8(px,o+1)==g and buffer.readu8(px,o+2)==b then return end
 buffer.writeu8(px,o,r);buffer.writeu8(px,o+1,g);buffer.writeu8(px,o+2,b);buffer.writeu8(px,o+3,a)
 local lx=x-t.x0;local band=ly//BAND
 local l=t.left[band]
 if l==nil then t.left[band]=lx;t.right[band]=lx;table.insert(t.queue,band)
 else if lx<l then t.left[band]=lx end;if lx>t.right[band]then t.right[band]=lx end end
end
-- A reusable upload buffer per byte size (widths are rounded up to ALIGN columns, so there are few).
function T:scratch(bytes)
 local s=self.buffers and self.buffers[bytes]
 if not s then self.buffers=self.buffers or {};s=buffer.create(bytes);self.buffers[bytes]=s end
 return s
end
-- Upload changed pixels of the next tile that has any (Roblox shows one EditableImage update a frame).
-- (2026-11-15: this used to upload the one rectangle around every change in a tile. With eighty
-- countries growing all over the map that rectangle was most of a 720 × 720 tile, about 2 MB copied
-- into a fresh buffer and sent every frame, which an old phone could not keep up with. Now the tile
-- keeps its changes per band of BAND rows, and a frame sends at most MAX_PIXELS of them; the rest
-- follow in the next frames.)
function T:flush()
 for _=1,#self.tiles do
  local t=self.tiles[self.next];self.next=self.next%#self.tiles+1
  if t.head<=#t.queue then
   local sent=0
   while t.head<=#t.queue and sent<MAX_PIXELS do
    local band=t.queue[t.head];t.head+=1
    local left,right=t.left[band],t.right[band];t.left[band]=nil;t.right[band]=nil
    local top=band*BAND;local rows=math.min(BAND,t.h-top)
    -- widen to a multiple of ALIGN columns, kept inside the tile
    local cols=math.min(t.w,math.ceil((right-left+1)/ALIGN)*ALIGN)
    if left+cols>t.w then left=t.w-cols end
    local slice=self:scratch(rows*cols*4)
    if cols==t.w then buffer.copy(slice,0,t.pixels,top*t.w*4,rows*cols*4)
    else for r=0,rows-1 do buffer.copy(slice,r*cols*4,t.pixels,((top+r)*t.w+left)*4,cols*4)end end
    t.img:WritePixelsBuffer(Vector2.new(left,top),Vector2.new(cols,rows),slice)
    sent+=rows*cols
   end
   if t.head>#t.queue then t.queue={};t.head=1 end
   return
  end
 end
end
function T:clear()
 for _,t in ipairs(self.tiles)do
  buffer.fill(t.pixels,0,0);t.left={};t.right={};t.queue={};t.head=1
  for band=0,math.ceil(t.h/BAND)-1 do t.left[band]=0;t.right[band]=t.w-1;table.insert(t.queue,band)end
 end
end
function T:destroy()
 for _,t in ipairs(self.tiles)do pcall(function()t.img:Destroy()end)end
 self.folder:Destroy()
end
return T
