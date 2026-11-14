--!nonstrict
-- Small interface animations shared by the HUD: a button grows a little and lights up under the pointer,
-- dips when pressed and springs back; panels fade and slide in. Tweens only (no per-frame work).
local TweenService=game:GetService("TweenService")
local A={}
A.QUICK=TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
A.SPRING=TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
A.SLIDE=TweenInfo.new(.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
function A.tween(obj,info,props)local t=TweenService:Create(obj,info,props);t:Play();return t end
local function scaleOf(obj)
 local s=obj:FindFirstChild("PressScale")
 if not s then s=Instance.new("UIScale");s.Name="PressScale";s.Parent=obj end
 return s
end
-- Hover and press feedback for any GuiButton. `light`: the background under the pointer (optional);
-- the button's own colour is read each time, so callers may recolour it (selected, disabled).
function A.button(b,opts)
 opts=opts or {}
 local s=scaleOf(b);local hover=false
 local grow,dip=opts.grow or 1.05,opts.dip or .93
 b.MouseEnter:Connect(function()hover=true;b:SetAttribute("Hover",true);A.tween(s,A.QUICK,{Scale=grow})end)
 b.MouseLeave:Connect(function()hover=false;b:SetAttribute("Hover",false);A.tween(s,A.QUICK,{Scale=1})end)
 b.MouseButton1Down:Connect(function()A.tween(s,A.QUICK,{Scale=dip})end)
 b.MouseButton1Up:Connect(function()A.tween(s,A.SPRING,{Scale=hover and grow or 1})end)
 b.Activated:Connect(function()
  -- A touch has no hover: a short pulse instead.
  if not hover then s.Scale=dip;A.tween(s,A.SPRING,{Scale=1})end
 end)
 return s
end
-- Shows or hides a panel with a short fade and slide (dy pixels below its place when hidden).
function A.reveal(panel,shown,dy)
 local s=scaleOf(panel)
 if shown then
  if not panel.Visible then panel.Visible=true;s.Scale=.94;A.tween(s,A.SPRING,{Scale=1})end
 elseif panel.Visible then
  panel.Visible=false;s.Scale=1
 end
end
return A
