--!nonstrict
-- Sea Battle's own icons in the interface (no emoji: emoji look different on every phone and cannot take
-- a country's colour). The art is one atlas of white masks made by tools/make_icons.py (IconAtlas); an
-- icon is an ImageLabel showing one cell, tinted with ImageColor3.
--   Icons.image(parent, name, size, color, props)  a free-standing icon
--   Icons.set(image, name)                          show another icon in the same ImageLabel
--   Icons.lead(label, name, opts)                   an icon before a button's or label's text: centred
--                                                  text keeps text and icon centred together, left-aligned
--                                                  text starts after the icon
local Atlas=require(script.Parent.IconAtlas)
local Pixels=require(script.Parent.IconPixels)
local AssetService=game:GetService("AssetService")
local I={}
I.atlas=Atlas
-- The atlas is built here, in an EditableImage, from the alpha embedded in IconPixels: an uploaded image
-- can stay unavailable to players (phones showed none of the icons, 2026-11-07, while Studio showed them
-- to their author). The uploaded copy (Atlas.id) is only the fallback when no EditableImage can be made.
local built,content=false,nil
local function hex(s,i)local b=string.byte(s,i);return b<=57 and b-48 or b-87 end
local function build()
 built=true
 local w,h=Pixels.width,Pixels.height
 local ok,img=pcall(function()return AssetService:CreateEditableImage({Size=Vector2.new(w,h)})end)
 if not ok or not img then warn("[Icons] EditableImage unavailable, using the uploaded atlas");return end
 local buf=buffer.create(w*h*4)
 -- White everywhere (so scaled-down edges do not darken), alpha from the coded runs.
 for p=0,w*h-1 do buffer.writeu32(buf,p*4,0x00FFFFFF)end
 local d,i,pos,n=Pixels.data,1,0,#Pixels.data
 while i<=n do
  if string.byte(d,i)==122 then -- 'z': a long transparent run
   pos+=tonumber(string.sub(d,i+1,i+3),16)+1;i+=4
  else
   local a=hex(d,i)*17;local run=hex(d,i+1)+1
   if a>0 then for k=pos,pos+run-1 do buffer.writeu8(buf,k*4+3,a)end end
   pos+=run;i+=2
  end
 end
 local wrote=pcall(function()img:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),buf)end)
 if wrote then content=Content.fromObject(img)end
end
function I.has(name)return Atlas.cells[name]~=nil end
function I.set(image,name)
 local c=Atlas.cells[name]
 image.Visible=c~=nil
 if not c then return image end
 if not built then build()end
 if content then
  local k=Pixels.cell/Atlas.cell
  image.ImageContent=content;image.ImageRectSize=Vector2.new(Pixels.cell,Pixels.cell);image.ImageRectOffset=Vector2.new(c[1]*k,c[2]*k)
 else
  image.Image=Atlas.id;image.ImageRectSize=Vector2.new(Atlas.cell,Atlas.cell);image.ImageRectOffset=Vector2.new(c[1],c[2])
 end
 return image
end
function I.image(parent,name,size,color,props)
 local img=Instance.new("ImageLabel")
 img.Name="Icon";img.BackgroundTransparency=1;img.BorderSizePixel=0;img.ScaleType=Enum.ScaleType.Fit
 img.Size=UDim2.fromOffset(size or 16,size or 16);img.ImageColor3=color or Color3.new(1,1,1)
 img:SetAttribute("NoSkin",true)
 for k,v in pairs(props or {})do img[k]=v end
 I.set(img,name)
 img.Parent=parent
 return img
end
-- opts: size (px, default about the text size), color (default the text colour), gap (px, 6).
function I.lead(label,name,opts)
 opts=opts or {}
 local size=opts.size or math.floor(label.TextSize*1.15+.5)
 local gap=opts.gap or 6
 local img=label:FindFirstChild("LeadIcon")
 if not img then
  img=I.image(label,name,size,opts.color or label.TextColor3,{Name="LeadIcon",AnchorPoint=Vector2.new(1,.5),ZIndex=label.ZIndex+1})
  local pad=label:FindFirstChildOfClass("UIPadding")or Instance.new("UIPadding")
  pad.Name="LeadPadding";pad.Parent=label
  local base=pad.PaddingLeft.Offset
  img:SetAttribute("BasePad",base)
  -- TextBounds is in screen pixels, after every UIScale above the label; offsets are scaled again
  -- when drawn, so the text width is brought back to the label's own units first.
  local function scale()
   local k=1;local o=label
   while o and o:IsA("GuiBase2d")do
    local u=o:FindFirstChildOfClass("UIScale");if u then k*=u.Scale end
    o=o.Parent
   end
   return k>0 and k or 1
  end
  -- UIPadding moves the children as well as the text: positions below are inside the padded area.
  local function place()
   local s=img:GetAttribute("Size")or size
   local right=label.TextXAlignment==Enum.TextXAlignment.Right
   pad.PaddingLeft=UDim.new(0,(img:GetAttribute("BasePad")or 0)+((img.Visible and not right)and(s+gap)or 0))
   if right then
    -- Right-aligned text: the icon just before it, no padding needed.
    img.Position=UDim2.new(1,-math.ceil(label.TextBounds.X/scale())-gap,.5,0)
   elseif label.TextXAlignment==Enum.TextXAlignment.Center then
    -- Text centred in the space after the icon; the icon just before where the text begins.
    img.Position=UDim2.new(.5,-math.floor(label.TextBounds.X/scale()/2)-gap,.5,0)
   else
    img.Position=UDim2.new(0,-gap,.5,0)
   end
  end
  label:GetPropertyChangedSignal("TextBounds"):Connect(place)
  label:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
  img:GetPropertyChangedSignal("Visible"):Connect(place)
  img:SetAttribute("Size",size)
  task.defer(place);place()
 else
  I.set(img,name)
  if opts.color then img.ImageColor3=opts.color end
 end
 img.Visible=name~=nil and Atlas.cells[name]~=nil
 return img
end
return I
