--!nonstrict
-- Building blocks of the lobby's windows (daily bonus, shop), in the lobby's own style: the same
-- colours, rounded cards, pressable surfaces and round icon badges as shared/Lobby.
local TweenService=game:GetService("TweenService")
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local K={}
K.C={ink=Color3.fromRGB(9,18,27),card=Color3.fromRGB(20,34,45),tile=Color3.fromRGB(27,45,58),
 tileOn=Color3.fromRGB(24,70,70),accent=Theme.colors.accent,text=Theme.colors.text,muted=Theme.colors.muted,
 amber=Color3.fromRGB(255,206,96),amberDeep=Color3.fromRGB(255,140,58),white=Color3.new(1,1,1),
 silver=Color3.fromRGB(205,216,226),red=Color3.fromRGB(255,110,96),dark=Color3.fromRGB(40,20,6),
 robux=Color3.fromRGB(120,220,150)}
K.QUICK=TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
K.POP=TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
local C=K.C
function K.make(class,parent,props)
 local o=Instance.new(class)
 for k,v in pairs(props or {})do o[k]=v end
 if o:IsA('GuiObject')then o:SetAttribute('NoSkin',true)end
 o.Parent=parent;return o
end
local make=K.make
function K.corner(o,r)make('UICorner',o,{CornerRadius=UDim.new(0,r)});return o end
function K.stroke(o,color,t,th)return make('UIStroke',o,{Color=color,Transparency=t or 0,Thickness=th or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
function K.label(parent,text,size,weight,color,props)
 local o=make('TextLabel',parent,{BackgroundTransparency=1,Text=text,TextSize=size,FontFace=Theme.font(weight),TextColor3=color or C.text,
  TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,ZIndex=(parent:IsA('GuiObject')and parent.ZIndex or 1)+1})
 for k,v in pairs(props or {})do o[k]=v end
 return o
end
-- A pressable surface: grows a little under the pointer and dips when pressed; silent while not Active.
function K.pressable(parent,props,onClick)
 local b=make('TextButton',parent,{Text='',AutoButtonColor=false,BorderSizePixel=0,ZIndex=(parent:IsA('GuiObject')and parent.ZIndex or 1)+1})
 for k,v in pairs(props or {})do b[k]=v end
 local scale=make('UIScale',b,{Scale=1})
 local function to(v)TweenService:Create(scale,K.QUICK,{Scale=v}):Play()end
 b.MouseEnter:Connect(function()if b.Active then to(1.035)end end)
 b.MouseLeave:Connect(function()to(1)end)
 b.MouseButton1Down:Connect(function()if b.Active then to(.96)end end)
 b.MouseButton1Up:Connect(function()to(1)end)
 b.Activated:Connect(function()if b.Active then onClick()end end)
 return b
end
-- A round badge with one of the game's icons, lit from above.
function K.badge(parent,icon,size,color,pos)
 local z=(parent:IsA('GuiObject')and parent.ZIndex or 1)+1
 local d=K.corner(make('Frame',parent,{Size=UDim2.fromOffset(size,size),Position=pos,BackgroundColor3=color:Lerp(C.ink,.55),ZIndex=z}),size)
 make('UIStroke',d,{Color=color,Thickness=2,Transparency=.05})
 make('UIGradient',d,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(170,170,170))})
 Icons.image(d,icon,math.floor(size*.56),C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=z+1})
 return d
end
-- The amber "main action" look (Battle, Claim).
function K.primary(b)
 b.BackgroundColor3=C.white
 local g=make('UIGradient',b,{Rotation=90,Color=ColorSequence.new(C.amber,C.amberDeep)})
 make('UIStroke',b,{Color=Color3.fromRGB(255,230,170),Transparency=.35,Thickness=1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 return g
end
-- A window over the lobby: a dim layer that closes it on a click, and a card scaled to fit the screen.
-- -> {shade, card, scale, close (the round X button)}; the caller shows and hides `shade` and `card`.
function K.window(parent,name,z,width,height,onClose)
 local shade=make('TextButton',parent,{Name=name..'Shade',Text='',AutoButtonColor=false,BackgroundColor3=C.ink,BackgroundTransparency=.35,
  BorderSizePixel=0,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=z})
 shade.Activated:Connect(onClose)
 local card=K.corner(make('Frame',parent,{Name=name,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(width,height),
  BackgroundColor3=C.card,BackgroundTransparency=.02,Visible=false,Active=true,ZIndex=z+1}),20)
 K.stroke(card,C.white,.84,1)
 make('UIGradient',card,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(200,210,220))})
 local scale=make('UIScale',card,{Scale=1})
 local close=K.pressable(card,{Name='Close',AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-14,0,14),Size=UDim2.fromOffset(36,36),BackgroundColor3=C.tile},onClose)
 K.corner(close,18);K.stroke(close,C.white,.85,1)
 Icons.image(close,'close',14,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=close.ZIndex+1})
 return {shade=shade,card=card,scale=scale,close=close}
end
-- Centre a window's card in the screen under Roblox's top bar (the lobby's root reaches under the bar
-- too, so plain centring would put a tall card over Roblox's buttons on a phone).
function K.belowTopbar(card)
 card.Position=UDim2.new(.5,0,.5,math.floor(game:GetService('GuiService'):GetGuiInset().Y/2))
end
-- "12:34" hours and minutes (or minutes and seconds under an hour) until a moment.
function K.countdown(seconds)
 seconds=math.max(0,math.floor(seconds))
 if seconds>=3600 then return string.format('%d:%02d',seconds//3600,seconds%3600//60)end
 return string.format('%d:%02d',seconds//60,seconds%60)
end
return K
