--!nonstrict
-- Shared visual style: dark translucent cards, rounded controls, one accent colour.
-- Theme.skin walks a ScreenGui and styles panels, buttons and text in place,
-- so the views keep their own layout code.
local T={}
T.colors={
 panel=Color3.fromRGB(14,24,33),
 card=Color3.fromRGB(22,36,47),
 button=Color3.fromRGB(32,50,63),
 hover=Color3.fromRGB(45,74,84),
 accent=Color3.fromRGB(111,208,186),
 text=Color3.fromRGB(233,239,235),
 muted=Color3.fromRGB(150,173,178),
 stroke=Color3.fromRGB(255,255,255),
}
local family="rbxasset://fonts/families/BuilderSans.json"
local weights={[Enum.Font.GothamBold]=Enum.FontWeight.Bold,[Enum.Font.GothamMedium]=Enum.FontWeight.Medium,
 [Enum.Font.GothamBlack]=Enum.FontWeight.Heavy,[Enum.Font.Gotham]=Enum.FontWeight.Regular}
function T.font(weight)return Font.new(family,weight or Enum.FontWeight.Regular)end
local function add(obj,class,props)
 local child=obj:FindFirstChildOfClass(class)
 if not child then child=Instance.new(class);for k,v in pairs(props)do child[k]=v end;child.Parent=obj end
 return child
end
local function restyleText(obj)
 local weight=weights[obj.Font]
 if weight then obj.FontFace=T.font(weight)end
end
function T.style(obj)
 if obj:GetAttribute("NoSkin")or obj:GetAttribute("Marker")or obj:GetAttribute("Skinned")then return end
 if obj:IsA("TextButton")then
  obj:SetAttribute("Skinned",true);restyleText(obj)
  obj.AutoButtonColor=false;obj.BorderSizePixel=0
  add(obj,"UICorner",{CornerRadius=UDim.new(0,7)})
  obj.TextSize=math.max(obj.TextSize,12)
  if obj.BackgroundTransparency<1 and obj.BackgroundColor3~=T.colors.accent then obj.BackgroundColor3=T.colors.button end
  obj.MouseEnter:Connect(function()obj:SetAttribute("Hover",true);if obj.BackgroundColor3==T.colors.button then obj.BackgroundColor3=T.colors.hover end end)
  obj.MouseLeave:Connect(function()obj:SetAttribute("Hover",false);if obj.BackgroundColor3==T.colors.hover then obj.BackgroundColor3=T.colors.button end end)
 elseif obj:IsA("TextLabel")or obj:IsA("TextBox")then
  if obj.Font~=Enum.Font.Code then restyleText(obj)end
 elseif(obj:IsA("Frame")or obj:IsA("ScrollingFrame"))and obj.BackgroundTransparency<1 then
  local size=obj.Size
  -- Thin accent bars and colour swatches keep their sharp shape.
  if(size.X.Scale==0 and size.X.Offset<=14)or(size.Y.Scale==0 and size.Y.Offset<=14)then return end
  obj:SetAttribute("Skinned",true)
  obj.BorderSizePixel=0
  local nested=obj.Parent and obj.Parent:IsA("GuiObject")
  obj.BackgroundColor3=nested and T.colors.card or T.colors.panel
  obj.BackgroundTransparency=nested and .2 or .08
  add(obj,"UICorner",{CornerRadius=UDim.new(0,nested and 8 or 12)})
  if not nested then add(obj,"UIStroke",{Color=T.colors.stroke,Transparency=.88,Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
  if obj:IsA("ScrollingFrame")then obj.ScrollBarImageColor3=T.colors.accent;obj.ScrollBarImageTransparency=.4 end
 end
end
function T.skin(root)
 for _,obj in ipairs(root:GetDescendants())do T.style(obj)end
 -- Deferred so creators can set NoSkin/Marker attributes right after parenting.
 root.DescendantAdded:Connect(function(obj)task.defer(function()if obj.Parent then T.style(obj)end end)end)
end
return T
