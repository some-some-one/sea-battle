--!nonstrict
-- Cosmetics on the screen: flags as images and water patterns as bit tiles, both from shared/CosmeticArt.
-- The flags are drawn on the device into one EditableImage (as the icons are: an uploaded image can
-- stay unavailable to players); without it a flag shows as a block of its first colour.
local AssetService=game:GetService("AssetService")
local Art=require(script.Parent.CosmeticArt)
local F={}
local FW,FH=Art.FlagWidth,Art.FlagHeight
F.Aspect=FW/FH
local order={};for id in pairs(Art.Flags)do table.insert(order,id)end;table.sort(order)
local slot={};for i,id in ipairs(order)do slot[id]=i-1 end
local COLS=4;local CW,CH=FW+2,FH+2 -- a clear pixel around each flag
local built,content=false,nil
local function build()
 built=true
 local w,h=COLS*CW,math.ceil(#order/COLS)*CH
 local ok,img=pcall(function()return AssetService:CreateEditableImage({Size=Vector2.new(w,h)})end)
 if not ok or not img then warn("[Flags] EditableImage unavailable: flags are shown as plain blocks");return end
 local buf=buffer.create(w*h*4)
 for id,i in pairs(slot)do
  local x0,y0=(i%COLS)*CW+1,(i//COLS)*CH+1
  for y,line in ipairs(Art.Flags[id])do
   for x=1,FW do
    local c=Art.Palette[string.sub(line,x,x)]or Art.Palette.K
    buffer.writeu32(buf,((y0+y-1)*w+x0+x-1)*4,c[1]+c[2]*256+c[3]*65536+255*16777216)
   end
  end
 end
 if pcall(function()img:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),buf)end)then content=Content.fromObject(img)end
end
function F.has(id)return id~=nil and Art.Flags[id]~=nil end
-- Show flag `id` in an ImageLabel (hidden when there is no such flag).
function F.set(image,id)
 if not F.has(id)then image.Visible=false;return image end
 if not built then build()end
 image.Visible=true
 if image:GetAttribute("Flag")==id then return image end
 image:SetAttribute("Flag",id)
 if content then
  local i=slot[id]
  image.ImageContent=content;image.ImageRectSize=Vector2.new(FW,FH);image.ImageRectOffset=Vector2.new((i%COLS)*CW+1,(i//COLS)*CH+1)
  image.BackgroundTransparency=1
 else
  local c=Art.Palette[string.sub(Art.Flags[id][1],1,1)]or Art.Palette.K
  image.BackgroundColor3=Color3.fromRGB(c[1],c[2],c[3]);image.BackgroundTransparency=0
 end
 return image
end
-- A flag image `height` points tall (its width follows the flag's shape).
function F.image(parent,id,height,props)
 local img=Instance.new("ImageLabel")
 img.Name="Flag";img.BackgroundTransparency=1;img.BorderSizePixel=0;img.ResampleMode=Enum.ResamplerMode.Pixelated
 img.Size=UDim2.fromOffset(math.floor(height*F.Aspect+.5),height)
 img:SetAttribute("NoSkin",true);img:SetAttribute("Marker",true)
 for k,v in pairs(props or {})do img[k]=v end
 F.set(img,id)
 img.Parent=parent
 return img
end
-- ---------------------------------------------------------------- water patterns
-- A pattern ready for the territory image: {w, h, [index] = true where the second tint goes}.
local tiles={}
function F.pattern(id)
 if id==nil then return nil end
 local t=tiles[id]
 if t==nil then
  local rows=Art.Patterns[id]
  if not rows then tiles[id]=false;return nil end
  t={w=#rows[1],h=#rows}
  for y,line in ipairs(rows)do for x=1,t.w do if string.byte(line,x)==35 then t[(y-1)*t.w+x]=true end end end
  tiles[id]=t
 end
 return t or nil
end
function F.hasPattern(id)return F.pattern(id)~=nil end
-- A swatch of water with the pattern on it, `cells` cells a side: frames in `parent` (a small preview in
-- the shop). base, tint: the water's colour and the pattern's.
function F.swatch(parent,id,cells,base,tint,z)
 local t=F.pattern(id)
 local holder=Instance.new("Frame");holder.Name="Swatch";holder.BackgroundColor3=base;holder.BorderSizePixel=0;holder.ClipsDescendants=true
 holder.Size=UDim2.fromScale(1,1);holder.ZIndex=z or 1;holder:SetAttribute("NoSkin",true)
 if t then
  local k=1/cells
  for y=0,cells-1 do
   -- (runs of lit cells in a row become one frame)
   local x=0
   while x<cells do
    if t[(y%t.h)*t.w+x%t.w+1]then
     local x1=x;while x1+1<cells and t[(y%t.h)*t.w+(x1+1)%t.w+1]do x1+=1 end
     local f=Instance.new("Frame");f.BackgroundColor3=tint;f.BorderSizePixel=0;f.ZIndex=(z or 1)+1;f:SetAttribute("NoSkin",true)
     f.Position=UDim2.fromScale(x*k,y*k);f.Size=UDim2.new((x1-x+1)*k,1,k,1);f.Parent=holder
     x=x1+1
    else x+=1 end
   end
  end
 end
 holder.Parent=parent
 return holder
end
return F
