--!native
--!nonstrict
-- Territory as pixels: one map cell is one pixel of an EditableImage,
-- shown on flat parts through a SurfaceGui with pixelated resampling. Changing an owner rewrites
-- four bytes; per frame only the dirty rows of one image are uploaded (Roblox shows one EditableImage
-- update per frame). Replaces tens of thousands of fill and border Parts with two images.
local AssetService=game:GetService("AssetService")
local T={};T.__index=T
local TILE=720 -- per side; EditableImage allows up to 1024

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
  table.insert(self.tiles,{x0=x0,y0=y0,w=tw,h=th,img=img,pixels=buffer.create(tw*th*4),low=nil,high=nil})
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
 local lx=x-t.x0
 if not t.low or ly<t.low then t.low=ly end
 if not t.high or ly>t.high then t.high=ly end
 if not t.left or lx<t.left then t.left=lx end
 if not t.right or lx>t.right then t.right=lx end
end
-- Upload the dirty rows of the next tile that has any.
function T:flush()
 for _=1,#self.tiles do
  local t=self.tiles[self.next];self.next=self.next%#self.tiles+1
  if t.low then
   -- Upload only the changed rectangle, not whole rows: captures touch small areas, and full-width
   -- uploads of a 720-pixel tile cost a few milliseconds a frame.
   local rows=t.high-t.low+1;local left,right=t.left or 0,t.right or t.w-1;local cols=right-left+1
   local slice=buffer.create(rows*cols*4)
   if cols==t.w then buffer.copy(slice,0,t.pixels,t.low*t.w*4,rows*cols*4)
   else for r=0,rows-1 do buffer.copy(slice,r*cols*4,t.pixels,((t.low+r)*t.w+left)*4,cols*4)end end
   t.img:WritePixelsBuffer(Vector2.new(left,t.low),Vector2.new(cols,rows),slice)
   t.low,t.high,t.left,t.right=nil,nil,nil,nil
   return
  end
 end
end
function T:clear()
 for _,t in ipairs(self.tiles)do buffer.fill(t.pixels,0,0);t.low,t.high,t.left,t.right=0,t.h-1,0,t.w-1 end
end
function T:destroy()
 for _,t in ipairs(self.tiles)do pcall(function()t.img:Destroy()end)end
 self.folder:Destroy()
end
return T
