--!nonstrict
-- The bottom command bar: the player's fleet (and its growth
-- per second; the cap is not shown), gold (with income per second), the attack share, a retreat
-- button while a front is open, and one tile per building, the fighter and the missiles (icon, price,
-- hotkey). Three layouts for the screen:
--  * wide    — one glass row at the bottom centre (a desktop);
--  * stacked — the same in two rows: resources and share above, the tiles below (laptop, tablet);
--  * compact — a slim phone strip (big icons and numbers, few words): the fleet without its cap, gold,
--              every attack share as its own button (one tap from 25% to 75%) and a Build button that
--              slides a tray of big tiles above it. A small phone held sideways (iPhone 7, 667 points)
--              keeps the one row: narrower share buttons, Build and Shop, and each rate under its number.
--              Only a phone held upright gives the shares a second row.
-- A tile under the pointer shows its name, price and what it does; an armed order shows a short hint
-- above the bar with a cancel button. Unaffordable tiles are dimmed. BattleView owns the logic.
-- The shop (2026-11-11, by the author's request): a gold tile closes the
-- row (on a phone a gold button beside Build). It shows, in turn, the icon of each arsenal item still
-- to open, a light sweeps across it now and then, and until the shop has been opened a red badge
-- counts what there is to open and the tile gives a little shake every few seconds. A press opens the
-- shop on the item it shows (cfg.onShop(key)).
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local Anim=require(script.Parent.Anim)
local NumberFormat=require(script.Parent.NumberFormat)
local compact=NumberFormat.compact
local C={panel=Theme.colors.panel,card=Theme.colors.card,button=Theme.colors.button,hover=Theme.colors.hover,
 accent=Theme.colors.accent,text=Theme.colors.text,muted=Theme.colors.muted,
 fleet=Color3.fromRGB(120,196,255),gold=Color3.fromRGB(255,206,84),grow=Color3.fromRGB(126,222,152),
 danger=Color3.fromRGB(255,128,112),shield=Color3.fromRGB(150,206,255)}
local CB={};CB.__index=CB
local function make(class,parent,props)
 local o=Instance.new(class);o:SetAttribute("NoSkin",true)
 for k,v in pairs(props or {})do o[k]=v end
 o.Parent=parent;return o
end
local function corner(o,r)make("UICorner",o,{CornerRadius=UDim.new(0,r)});return o end
local function stroke(o,color,t,th)return make("UIStroke",o,{Color=color,Transparency=t,Thickness=th or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
local function text(parent,value,size,weight,color,props)
 local o=make("TextLabel",parent,{BackgroundTransparency=1,Text=value,TextSize=size,FontFace=Theme.font(weight or Enum.FontWeight.Medium),
  TextColor3=color or C.text,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,ZIndex=22})
 for k,v in pairs(props or {})do o[k]=v end
 return o
end
-- A glass panel: dark translucent tint, a soft light rim and a sheen at the top.
local function glass(parent,props)
 local f=make("Frame",parent,{BackgroundColor3=C.panel,BackgroundTransparency=.12,BorderSizePixel=0,ZIndex=20})
 for k,v in pairs(props or {})do f[k]=v end
 corner(f,14);stroke(f,Color3.new(1,1,1),.86,1)
 make("UIGradient",f,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(205,215,225))})
 return f
end
-- Fleet or gold: icon, value, a muted tail (the cap), the growth per second; the fleet also has a fill bar.
local function stat(parent,icon,color,withBar,big)
 local s={}
 s.frame=make("Frame",parent,{BackgroundTransparency=1,ZIndex=21})
 s.icon=Icons.image(s.frame,icon,big and 26 or 22,color,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,0,.5,withBar and -3 or 0),ZIndex=22})
 s.value=text(s.frame,"0",big and 19 or 17,Enum.FontWeight.Bold,C.text,{AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromOffset(0,20),
  Position=UDim2.new(0,big and 32 or 28,.5,withBar and -13 or -10)})
 s.tail=text(s.frame,"",big and 13 or 12,Enum.FontWeight.Medium,C.muted,{AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromOffset(0,20),
  Position=UDim2.new(0,0,.5,withBar and -13 or -10)})
 s.rate=text(s.frame,"",big and 13 or 12,Enum.FontWeight.Bold,C.grow,{AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromOffset(0,20),
  Position=UDim2.new(0,0,.5,withBar and -13 or -10)})
 if withBar then
  s.bar=corner(make("Frame",s.frame,{BackgroundColor3=Color3.fromRGB(8,14,20),BackgroundTransparency=.2,BorderSizePixel=0,
   Position=UDim2.new(0,big and 32 or 28,.5,9),Size=UDim2.new(1,-(big and 32 or 28),0,5),ZIndex=22}),3)
  s.fill=corner(make("Frame",s.bar,{BackgroundColor3=color,BorderSizePixel=0,Size=UDim2.fromScale(0,1),ZIndex=23}),3)
 end
 -- The tail and the rate follow the value's width (stacked: the rate under the value).
 local function place()
  if s.stacked then
   s.tail.Text="";s.rate.Position=UDim2.new(0,s.value.Position.X.Offset,.5,2);return
  end
  local x=s.value.Position.X.Offset+s.value.AbsoluteSize.X+4
  s.tail.Position=UDim2.new(0,x,s.value.Position.Y.Scale,s.value.Position.Y.Offset)
  local x2=x+(s.tail.Text~=""and(s.tail.AbsoluteSize.X+6)or 2)
  s.rate.Position=UDim2.new(0,x2,s.value.Position.Y.Scale,s.value.Position.Y.Offset+1)
 end
 s.value:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
 s.tail:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
 function s.setStacked(on)
  if s.stacked==on then return end
  s.stacked=on;s.value.Position=UDim2.new(0,s.value.Position.X.Offset,.5,on and -19 or(withBar and -13 or -10));place()
 end
 return s
end
function CB.new(parent,cfg)
 local self=setmetatable({cfg=cfg,slots={},tiles={},flow=nil,active=nil,goldSamples={},prices={}},CB)
 -- Desktop / tablet bar.
 self.root=glass(parent,{Name="CommandBar",AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-10),Size=UDim2.fromOffset(1060,82)})
 self.res=make("Frame",self.root,{Name="Resources",BackgroundTransparency=1,ZIndex=21})
 -- (the fleet alone: its cap is internal and not shown anywhere, by the author's request)
 self.fleet=stat(self.res,"ship",C.fleet,false,false)
 self.gold=stat(self.res,"coins",C.gold,false,false)
 self.sep1=make("Frame",self.root,{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.88,BorderSizePixel=0,Size=UDim2.fromOffset(1,56),ZIndex=21})
 -- Attack share: one segment per share (25/40/50/60/75); a retreat button under them while a front is open.
 self.share=make("Frame",self.root,{Name="Share",BackgroundTransparency=1,Size=UDim2.fromOffset(204,62),ZIndex=21})
 text(self.share,"ATTACK SHARE",10,Enum.FontWeight.Bold,C.muted,{Size=UDim2.new(1,0,0,14)})
 self.shareTrack=corner(make("Frame",self.share,{BackgroundColor3=Color3.fromRGB(8,14,20),BackgroundTransparency=.25,BorderSizePixel=0,
  Position=UDim2.fromOffset(0,16),Size=UDim2.new(1,0,0,26),ZIndex=21}),8)
 self.shareButtons={}
 for i,r in ipairs(cfg.ratios)do
  local b=corner(make("TextButton",self.shareTrack,{Name="Ratio"..math.floor(r*100),Text=math.floor(r*100).."%",AutoButtonColor=false,
   BackgroundColor3=C.button,BackgroundTransparency=1,Position=UDim2.new((i-1)/#cfg.ratios,2,0,2),Size=UDim2.new(1/#cfg.ratios,-4,1,-4),
   TextSize=12,FontFace=Theme.font(Enum.FontWeight.Bold),TextColor3=C.muted,ZIndex=22}),6)
  Anim.button(b,{grow=1.04})
  b.Activated:Connect(function()cfg.onRatio(r)end)
  self.shareButtons[r]=b
 end
 self.retreat=corner(make("TextButton",self.share,{Name="Retreat",Text="Retreat",AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(120,44,40),
  Position=UDim2.fromOffset(0,45),Size=UDim2.new(1,0,0,17),TextSize=11,FontFace=Theme.font(Enum.FontWeight.Bold),TextColor3=C.text,Visible=false,ZIndex=22}),5)
 Anim.button(self.retreat,{grow=1.03})
 self.retreat.Activated:Connect(function()cfg.onRetreat()end)
 self.committed=text(self.share,"",11,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(0,45),Size=UDim2.new(1,0,0,17),TextXAlignment=Enum.TextXAlignment.Center})
 self.sep2=make("Frame",self.root,{BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.88,BorderSizePixel=0,Size=UDim2.fromOffset(1,56),ZIndex=21})
 self.tileRow=make("Frame",self.root,{Name="Tiles",BackgroundTransparency=1,ZIndex=21})
 make("UIListLayout",self.tileRow,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder,
  VerticalAlignment=Enum.VerticalAlignment.Center})
 for i,slot in ipairs(cfg.slots)do self.slots[slot.key]=slot;self:tile(self.tileRow,slot,i,54,62,28,true)end
 self.shop=self:shopButton(self.tileRow,true)
 -- Name, price and what a tile does, above the bar while the pointer rests on it.
 self.tip=glass(parent,{Name="TileTip",AnchorPoint=Vector2.new(.5,1),Size=UDim2.fromOffset(250,0),AutomaticSize=Enum.AutomaticSize.Y,Visible=false,ZIndex=40})
 make("UIPadding",self.tip,{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12),PaddingTop=UDim.new(0,9),PaddingBottom=UDim.new(0,10)})
 make("UIListLayout",self.tip,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)})
 self.tipTitle=text(self.tip,"",15,Enum.FontWeight.Bold,C.text,{Size=UDim2.new(1,0,0,18),LayoutOrder=1,ZIndex=41})
 self.tipPrice=text(self.tip,"",13,Enum.FontWeight.Bold,C.gold,{Size=UDim2.new(1,0,0,16),LayoutOrder=2,ZIndex=41})
 self.tipInfo=text(self.tip,"",12,Enum.FontWeight.Regular,C.muted,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,
  TextYAlignment=Enum.TextYAlignment.Top,LayoutOrder=3,ZIndex=41})
 -- An armed order: what to do now, and a button to drop it.
 self.hint=glass(parent,{Name="OrderHint",AnchorPoint=Vector2.new(.5,1),Size=UDim2.fromOffset(0,36),AutomaticSize=Enum.AutomaticSize.X,Visible=false,ZIndex=38})
 make("UIPadding",self.hint,{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,6)})
 make("UIListLayout",self.hint,{FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder})
 self.hintIcon=Icons.image(self.hint,"target",18,C.accent,{LayoutOrder=1,ZIndex=39})
 self.hintText=text(self.hint,"",13,Enum.FontWeight.Medium,C.text,{AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromOffset(0,36),LayoutOrder=2,ZIndex=39})
 self.hintCancel=corner(make("TextButton",self.hint,{Name="Cancel",Text="",AutoButtonColor=false,BackgroundColor3=C.button,Size=UDim2.fromOffset(26,26),LayoutOrder=3,ZIndex=39}),13)
 Icons.image(self.hintCancel,"close",12,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=40})
 Anim.button(self.hintCancel);self.hintCancel.Activated:Connect(function()cfg.onCancel()end)
 -- Start protection: a small chip over the bar's left edge while it lasts.
 -- Phone strip and its tray.
 self.strip=glass(parent,{Name="CommandStrip",AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-6),Size=UDim2.fromOffset(560,58),Visible=false})
 self.pFleet=stat(self.strip,"ship",C.fleet,false,true)
 self.pGold=stat(self.strip,"coins",C.gold,false,true)
 -- Attack shares: all of them at once, the chosen one lit.
 self.pShare=corner(make("Frame",self.strip,{Name="SharePhone",BackgroundColor3=Color3.fromRGB(8,14,20),BackgroundTransparency=.25,
  BorderSizePixel=0,Size=UDim2.fromOffset(230,44),ZIndex=21}),10)
 Icons.image(self.pShare,"swords",16,C.danger,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,8,.5,0),ZIndex=22})
 self.pShareButtons={}
 for i,r in ipairs(cfg.ratios)do
  local b=corner(make("TextButton",self.pShare,{Name="Ratio"..math.floor(r*100),Text=math.floor(r*100).."%",AutoButtonColor=false,
   BackgroundColor3=C.button,BackgroundTransparency=1,TextSize=14,FontFace=Theme.font(Enum.FontWeight.Bold),TextColor3=C.muted,ZIndex=22}),8)
  Anim.button(b,{grow=1.06})
  b.Activated:Connect(function()cfg.onRatio(r)end)
  self.pShareButtons[i]={ratio=r,button=b}
 end
 self.pRetreat=corner(make("TextButton",self.strip,{Name="RetreatPhone",Text="",AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(120,44,40),Size=UDim2.fromOffset(44,44),Visible=false,ZIndex=21}),10)
 Icons.image(self.pRetreat,"close",18,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=22})
 Anim.button(self.pRetreat);self.pRetreat.Activated:Connect(function()cfg.onRetreat()end)
 self.pBuild=corner(make("TextButton",self.strip,{Name="BuildToggle",Text="",AutoButtonColor=false,BackgroundColor3=C.accent,Size=UDim2.fromOffset(78,44),ZIndex=21}),10)
 Icons.image(self.pBuild,"factory",20,Color3.fromRGB(10,30,30),{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,4),ZIndex=22})
 text(self.pBuild,"Build",12,Enum.FontWeight.Bold,Color3.fromRGB(10,30,30),{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-3),Size=UDim2.new(1,0,0,16),
  TextXAlignment=Enum.TextXAlignment.Center})
 Anim.button(self.pBuild);self.pBuild.Activated:Connect(function()self:toggleTray()end)
 self.pShop=self:shopButton(self.strip,false)
 self.tray=glass(parent,{Name="BuildTray",AnchorPoint=Vector2.new(.5,1),Size=UDim2.fromOffset(400,160),Visible=false,ZIndex=30})
 make("UIPadding",self.tray,{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,10),PaddingBottom=UDim.new(0,10)})
 self.trayGrid=make("UIGridLayout",self.tray,{CellSize=UDim2.fromOffset(66,72),CellPadding=UDim2.fromOffset(8,8),SortOrder=Enum.SortOrder.LayoutOrder,
  HorizontalAlignment=Enum.HorizontalAlignment.Center})
 for i,slot in ipairs(cfg.slots)do self:tile(self.tray,slot,i,66,72,34,false)end
 return self
end
-- One tile: an icon, the price under it, the hotkey in the corner (desktop).
function CB:tile(parent,slot,order,w,h,iconSize,desktop)
 local b=corner(make("TextButton",parent,{Name=slot.key,Text="",AutoButtonColor=false,BackgroundColor3=C.button,BackgroundTransparency=.05,
  Size=UDim2.fromOffset(w,h),LayoutOrder=order,ZIndex=22}),10)
 local st=stroke(b,C.accent,1,2);st.Name="ActiveStroke"
 local icon=Icons.image(b,slot.icon,iconSize,C.text,{Name="Glyph",AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,desktop and 7 or 9),ZIndex=23})
 local price=text(b,"",desktop and 11 or 12,Enum.FontWeight.Bold,C.gold,{Name="Price",AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-4),
  Size=UDim2.new(1,0,0,14),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=23})
 if desktop and slot.hotkey then
  text(b,slot.hotkey,9,Enum.FontWeight.Bold,C.muted,{Name="Key",Position=UDim2.fromOffset(4,2),Size=UDim2.fromOffset(12,12),ZIndex=23})
 end
 Anim.button(b)
 b.Activated:Connect(function()
  if not desktop then self:showTray(false)end
  self.cfg.onSlot(slot.key)
 end)
 if desktop then
  b.MouseEnter:Connect(function()self:showTip(slot,b)end)
  b.MouseLeave:Connect(function()if self.tipFor==slot.key then self.tip.Visible=false;self.tipFor=nil end end)
 end
 self.tiles[slot.key]=self.tiles[slot.key]or {}
 table.insert(self.tiles[slot.key],{button=b,icon=icon,price=price,stroke=st,desktop=desktop})
 if desktop then slot.button=b end
 return b
end
-- The gold shop button (desktop: a tile closing the row; phone: beside Build).
local SHOP_GOLD,SHOP_DEEP,SHOP_INK=Color3.fromRGB(255,214,96),Color3.fromRGB(240,150,40),Color3.fromRGB(48,26,4)
function CB:shopButton(parent,desktop)
 local b=corner(make("TextButton",parent,{Name="Shop",Text="",AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),ClipsDescendants=true,
  Size=UDim2.fromOffset(desktop and 74 or 64,desktop and 62 or 44),LayoutOrder=1000,ZIndex=22}),10)
 make("UIGradient",b,{Rotation=90,Color=ColorSequence.new(SHOP_GOLD,SHOP_DEEP)})
 stroke(b,Color3.fromRGB(255,240,190),.15,2)
 local icon=Icons.image(b,"shop",desktop and 26 or 20,SHOP_INK,{Name="Glyph",AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,desktop and 7 or 4),ZIndex=24})
 local word=text(b,"Shop",desktop and 12 or 10,Enum.FontWeight.Heavy,SHOP_INK,{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,desktop and -5 or -3),
  Size=UDim2.new(1,0,0,14),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=24})
 -- The light that sweeps across.
 local shine=make("Frame",b,{Name="Shine",BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.45,BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),
  Size=UDim2.new(0,14,2,0),Rotation=20,Position=UDim2.new(-.4,0,.5,0),ZIndex=23})
 make("UIGradient",shine,{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})})
 -- The red badge: how much there is still to open (until the shop has been opened).
 local badge=corner(make("Frame",b,{Name="Badge",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-3,0,3),Size=UDim2.fromOffset(18,18),
  BackgroundColor3=Color3.fromRGB(230,52,52),Visible=false,ZIndex=26}),9)
 stroke(badge,Color3.new(1,1,1),0,1.5)
 local count=text(badge,"",11,Enum.FontWeight.Heavy,Color3.new(1,1,1),{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=27})
 local scale=make("UIScale",b,{Scale=1})
 Anim.button(b,{grow=1.06})
 local entry={button=b,icon=icon,word=word,shine=shine,badge=badge,count=count,scale=scale,desktop=desktop}
 b.Activated:Connect(function()
  if not desktop then self:showTray(false)end
  self.tip.Visible=false;self.tipFor=nil
  if self.cfg.onShop then self.cfg.onShop(self.shopShows)end
 end)
 if desktop then
  b.MouseEnter:Connect(function()
   local item=self.shopShows and self.shopNames and self.shopNames[self.shopShows]
   self:showTip({key="Shop",name="Shop",info=item and("Featured now: "..item..". Tap to see how it works.")or "Arsenal, flags, patterns and boosts."},b)
  end)
  b.MouseLeave:Connect(function()if self.tipFor=="Shop"then self.tip.Visible=false;self.tipFor=nil end end)
 end
 return entry
end
-- What the shop button shows: items still to open ({key, icon, name}, in shop order) and whether the
-- shop has been opened in this session (the badge and the shake stop then).
function CB:setShop(items,seen)
 self.shopItems=items;self.shopSeen=seen==true
 self.shopNames={};for _,it in ipairs(items)do self.shopNames[it.key]=it.name end
end
function CB:animateShop()
 local items=self.shopItems or {};local now=os.clock()
 local pick=#items>0 and items[math.floor(now/2.4)%#items+1]or nil
 self.shopShows=pick and pick.key or nil
 local icon=pick and pick.icon or "shop"
 local n=#items;local loud=n>0 and not self.shopSeen
 -- A sweep every 3.2 s; a shake every 5 s while the badge is up.
 local sweep=(now%3.2)/.7
 local wig=loud and now%5<.5 and math.sin(now%5*40)*6*(1-(now%5)/.5)or 0
 for _,e in ipairs({self.shop,self.pShop})do
  if e then
   if e.icon:GetAttribute("Icon")~=icon then e.icon:SetAttribute("Icon",icon);Icons.set(e.icon,icon)end
   -- (no light while it shakes: a rotated button does not clip its children, and the light ran out over the map)
   e.shine.Visible=wig==0
   e.shine.Position=UDim2.new(sweep<1 and(-.4+1.8*sweep)or -.4,0,.5,0)
   e.badge.Visible=loud;e.count.Text=tostring(n)
   e.button.Rotation=wig
  end
 end
end
function CB:showTip(slot,b)
 self.tipFor=slot.key
 self.tipTitle.Text=slot.name;self.tipInfo.Text=slot.info or ""
 local p=self.prices[slot.key];self.tipPrice.Text=p and(compact(p).." gold")or ""
 local origin=self.tip.Parent.AbsolutePosition
 local pos=b.AbsolutePosition-origin
 self.tip.Position=UDim2.fromOffset(math.clamp(pos.X+b.AbsoluteSize.X/2,130,self.tip.Parent.AbsoluteSize.X-130),self.root.AbsolutePosition.Y-origin.Y-8)
 self.tip.Visible=true
end
function CB:toggleTray()self:showTray(not self.tray.Visible)end
function CB:showTray(shown)Anim.reveal(self.tray,shown)end
-- Gold income per second, measured from the gold itself (spending is not income: only rises count).
function CB:goldRate(gold)
 local now=os.clock();local s=self.goldSamples
 if self.lastGold and gold>self.lastGold then table.insert(s,{now,gold-self.lastGold})end
 self.lastGold=gold
 while #s>0 and now-s[1][1]>4 do table.remove(s,1)end
 local sum=0;for _,e in ipairs(s)do sum+=e[2]end
 local span=math.max(1,math.min(4,now-(self.rateSince or now)))
 self.rateSince=self.rateSince or now
 return sum/span
end
-- Values for this frame: f is the player's faction row; prices maps tile keys to their price.
function CB:update(f,prices)
 self.prices=prices
 local fleet,gold=f.fleet or 0,f.gold or 0
 local growth=NumberFormat.perSecond(f.fleetPerSecond or 0)
 local rate=self:goldRate(gold)
 local goldRate=rate>=1 and("+"..compact(rate).."/s")or ""
 for _,s in ipairs({self.fleet,self.pFleet})do s.value.Text=compact(fleet);s.tail.Text="";s.rate.Text=growth~="0/s"and growth or ""end
 for _,s in ipairs({self.gold,self.pGold})do s.value.Text=compact(gold);s.tail.Text="";s.rate.Text=goldRate end
 local ratio=f.ratio or .25
 for r,b in pairs(self.shareButtons)do
  local on=math.abs(r-ratio)<.001
  b.BackgroundTransparency=on and 0 or 1;b.BackgroundColor3=on and C.accent or C.button;b.TextColor3=on and Color3.fromRGB(10,30,30)or C.muted
 end
 for _,e in ipairs(self.pShareButtons)do
  local on=math.abs(e.ratio-ratio)<.001
  e.button.BackgroundTransparency=on and 0 or 1;e.button.BackgroundColor3=on and C.accent or C.button
  e.button.TextColor3=on and Color3.fromRGB(10,30,30)or C.text
 end
 local attacking=f.advancing==true
 self.retreat.Visible=attacking;self.pRetreat.Visible=attacking
 self.committed.Visible=not attacking and(f.committed or 0)>0
 self.committed.Text=(f.committed or 0)>0 and("en route "..compact(f.committed))or ""
 for key,list in pairs(self.tiles)do
  local p=prices[key];local afford=p and gold>=p
  for _,t in ipairs(list)do
   t.price.Text=p and compact(p)or "";t.price.TextColor3=afford and C.gold or Color3.fromRGB(190,120,110)
   t.icon.ImageTransparency=afford and 0 or .5
   local on=self.active==key
   t.stroke.Transparency=on and 0 or 1
   t.button.BackgroundColor3=on and C.accent:Lerp(C.button,.55)or(t.button:GetAttribute("Hover")and C.hover or C.button)
  end
 end
 if self.tipFor and self.tip.Visible and self.tipFor~="Shop"then local p=prices[self.tipFor];self.tipPrice.Text=p and(compact(p).." gold")or ""end
 self:animateShop()
end
function CB:setActive(key)self.active=key end
-- Show or hide a tile (arsenal tiles appear once opened); the bar is laid out again.
function CB:setShown(key,shown)
 self.hidden=self.hidden or {}
 self.hidden[key]=not shown or nil
 for _,t in ipairs(self.tiles[key]or {})do t.button.Visible=shown end
 self.tileCount=nil
end
function CB:setHint(value,icon)
 self.hint.Visible=value~=nil and value~=""
 if self.hint.Visible then self.hintText.Text=value;Icons.set(self.hintIcon,icon or "target")end
end
-- Positions for this screen (size: the interface's size; small: a phone).
function CB:layout(size,small,shown)
 -- Tiles shown now; the bar is as wide as they need, and they narrow when the screen is not.
 local n=0;for _,slot in ipairs(self.cfg.slots)do if not(self.hidden and self.hidden[slot.key])then n+=1 end end
 local tw=54
 -- (the shop tile closes the row: 74 wide)
 local wideW=492+n*(tw+6)+80
 local flow=small and "compact"or(size.X>=wideW+20 and "wide"or "stacked")
 local rowW=n*(tw+6)-6+80
 if flow=="stacked"and rowW+30>size.X-20 then tw=math.max(30,math.floor((size.X-20-30+6-80)/n)-6);rowW=n*(tw+6)-6+80 end
 if flow~="compact"then
  for _,list in pairs(self.tiles)do for _,t in ipairs(list)do if t.desktop then
   t.button.Size=UDim2.fromOffset(tw,62);local side=math.min(28,tw-10);t.icon.Size=UDim2.fromOffset(side,side)
  end end end
 end
 self.root.Visible=shown and flow~="compact";self.strip.Visible=shown and flow=="compact"
 if not shown then self.tray.Visible=false;self.tip.Visible=false;self.hint.Visible=false end
 local top
 if flow=="compact"then
  -- One row: fleet · gold · shares · (retreat) · Build. Too narrow for that (a phone held upright):
  -- the shares fill a second row under the rest.
  -- (`ns`, not `n`: n is the number of tiles, which sizes the Build tray below)
  local ns=#self.pShareButtons
  local shareW=30+ns*40
  local resW=290
  local buildW,shopW=78,64
  -- (the retreat button floats above the strip's right end: an attack never changes the strip itself)
  local need=10+resW+shareW+(buildW+6)+(shopW+6)+8
  local avail=size.X-12
  local tight=need>avail
  if tight then
   -- a small phone sideways: narrower buttons, the shares down to 34 each, the rates under the numbers
   buildW,shopW=64,58
   local rest=avail-(10+(buildW+6)+(shopW+6)+8+6)
   local shareMin,resMin=30+ns*34,190
   if rest>=shareMin+resMin then shareW=math.min(shareW,rest-resMin) end
   need=10+resMin+shareMin+(buildW+6)+(shopW+6)+8
  end
  local w=math.min(avail,math.max(need,560))
  local twoRows=need>avail
  if twoRows or tight then w=avail end
  for _,st in ipairs({self.pFleet,self.pGold})do st.setStacked(tight)end
  self.pBuild.Size=UDim2.fromOffset(buildW,44);self.pShop.button.Size=UDim2.fromOffset(shopW,44)
  local h=twoRows and 108 or 58
  self.strip.Size=UDim2.fromOffset(w,h)
  local x=w-8
  local function dock(obj,width)x-=width;obj.Position=UDim2.fromOffset(x,7);x-=6 end
  dock(self.pShop.button,shopW);dock(self.pBuild,buildW)
  self.pRetreat.Position=UDim2.fromOffset(w-8-44,-50)
  if twoRows then
   self.pShare.Position=UDim2.fromOffset(8,58);self.pShare.Size=UDim2.fromOffset(w-16,44)
  else
   dock(self.pShare,shareW);self.pShare.Size=UDim2.fromOffset(shareW,44)
  end
  local bw=(self.pShare.Size.X.Offset-30-4)/ns
  for i,e in ipairs(self.pShareButtons)do
   e.button.Position=UDim2.fromOffset(30+(i-1)*bw,4);e.button.Size=UDim2.fromOffset(bw-4,36)
  end
  local free=x-10
  local fw=math.floor(free*.45)
  self.pFleet.frame.Position=UDim2.fromOffset(10,4);self.pFleet.frame.Size=UDim2.fromOffset(fw,50)
  self.pGold.frame.Position=UDim2.fromOffset(16+fw,4);self.pGold.frame.Size=UDim2.fromOffset(free-fw-6,50)
  local cols=math.max(3,math.floor((math.min(size.X-24,560)-20+8)/74))
  local rows=math.ceil(n/cols)
  self.tray.Size=UDim2.fromOffset(cols*74-8+20,rows*80-8+20)
  self.tray.Position=UDim2.new(.5,0,1,-(h+12))
  top=size.Y-h-6
 elseif flow=="wide"then
  self.root.Size=UDim2.fromOffset(wideW,82)
  self.res.Position=UDim2.fromOffset(14,10);self.res.Size=UDim2.fromOffset(214,62)
  self.fleet.frame.Position=UDim2.fromOffset(0,0);self.fleet.frame.Size=UDim2.fromOffset(214,34)
  self.gold.frame.Position=UDim2.fromOffset(0,36);self.gold.frame.Size=UDim2.fromOffset(214,26)
  self.sep1.Position=UDim2.fromOffset(238,13)
  self.share.Position=UDim2.fromOffset(250,10)
  self.sep2.Position=UDim2.fromOffset(466,13)
  self.tileRow.Position=UDim2.fromOffset(478,10);self.tileRow.Size=UDim2.fromOffset(rowW,62)
  top=size.Y-92
 else
  self.root.Size=UDim2.fromOffset(math.max(690,rowW+30),144)
  self.res.Position=UDim2.fromOffset(14,8);self.res.Size=UDim2.fromOffset(450,56)
  self.fleet.frame.Position=UDim2.fromOffset(0,8);self.fleet.frame.Size=UDim2.fromOffset(250,40)
  self.gold.frame.Position=UDim2.fromOffset(262,8);self.gold.frame.Size=UDim2.fromOffset(186,40)
  self.sep1.Position=UDim2.fromOffset(-10,0);self.sep1.Visible=false
  self.share.Position=UDim2.fromOffset(474,4)
  self.sep2.Visible=false
  self.tileRow.Position=UDim2.fromOffset(15,72);self.tileRow.Size=UDim2.fromOffset(rowW,62)
  top=size.Y-154
 end
 if flow~="stacked"then self.sep1.Visible=true;self.sep2.Visible=flow=="wide"end
 if flow~="compact"then self.tray.Visible=false end
 self.flow=flow
 self.hint.Position=UDim2.new(.5,0,0,top-8-(self.tray.Visible and self.tray.AbsoluteSize.Y or 0))
 self.top=top
end
function CB:isUI(obj)
 for _,p in ipairs({self.root,self.strip,self.tray,self.hint,self.tip})do
  if p.Visible and(obj==p or obj:IsDescendantOf(p))then return true end
 end
 return false
end
return CB
