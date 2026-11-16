--!nonstrict
-- The starter pack's own window (2026-11-16, by the author's request): for its 48 hours it opens by
-- itself once a visit, after the daily reward is closed (Lobby), and a gold tile at the lobby's left edge
-- with the time left opens it again. It has to look like a treat and say plainly what is inside:
--  * a gold frame with a light running round it, a few twinkling sparks, a title in gold;
--  * six tiles: silver, ×2 silver forever, the player's own country flag (drawn when the country is
--    known), a water pattern, the torpedo and the cluster missile;
--  * the price: what the things cost one by one crossed out (Products.starterWorth), the pack's price in
--    gold, how much is saved, and a gold Buy button with a shine sweeping across it.
-- The purchase is Roblox's window (Store.prompt); the grant is the server's (server/Purchases). The
-- pattern is a legendary one only rarely (Catalog.starterPattern), which the window does not say.
local TweenService=game:GetService("TweenService")
local Kit=require(script.Parent.Kit)
local Icons=require(script.Parent.Icons)
local Flags=require(script.Parent.Flags)
local Catalog=require(script.Parent.Catalog)
local Products=require(script.Parent.Products)
local Store=require(script.Parent.Store)
local Sfx=require(script.Parent.Sfx)
local compact=require(script.Parent.NumberFormat).compact
local C,make,corner,stroke,label,pressable=Kit.C,Kit.make,Kit.corner,Kit.stroke,Kit.label,Kit.pressable

local O={};O.__index=O
local Z=60
local W,H=600,376
local GOLD=Color3.fromRGB(255,206,96)
local GOLD_LIGHT=Color3.fromRGB(255,244,200)
local GOLD_DEEP=Color3.fromRGB(214,128,30)
local NAVY=Color3.fromRGB(14,24,40)
local WATER,TINT=Color3.fromRGB(58,120,150),Color3.fromRGB(110,170,196)
-- A gold sequence with a bright band at `at` (0..1): the light running round the frame and the title.
-- A layer over a rounded button that holds its sweeping shine: a CanvasGroup clips to the button's own
-- rounded corners (a frame's ClipsDescendants clips to a rectangle, and the shine showed in the corners).
local function shineLayer(button,radius,z)
 local layer=make('CanvasGroup',button,{Name='ShineLayer',BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=z})
 corner(layer,radius)
 return layer
end
local function shine(at)
 local a=math.clamp(at-.12,0,1);local b=math.clamp(at,0,1);local c=math.clamp(at+.12,0,1)
 local points={ColorSequenceKeypoint.new(0,GOLD_DEEP)}
 if a>0 and a<1 then table.insert(points,ColorSequenceKeypoint.new(a,GOLD))end
 if b>0 and b<1 and b>a then table.insert(points,ColorSequenceKeypoint.new(b,GOLD_LIGHT))end
 if c>0 and c<1 and c>b then table.insert(points,ColorSequenceKeypoint.new(c,GOLD))end
 table.insert(points,ColorSequenceKeypoint.new(1,GOLD_DEEP))
 return ColorSequence.new(points)
end

function O.new(lobby)
 local self=setmetatable({lobby=lobby,v=lobby.v,open=false,clock=0},O)
 local parent=lobby.root.Parent
 local w=Kit.window(parent,'StarterOffer',Z,W,H,function()self:show(false)end)
 self.shade,self.card,self.scale,self.close=w.shade,w.card,w.scale,w.close
 local inset=game:GetService('GuiService'):GetGuiInset().Y
 self.shade.Position=UDim2.fromOffset(0,-inset);self.shade.Size=UDim2.new(1,0,1,inset)
 local card=self.card
 card.BackgroundColor3=NAVY;card.ClipsDescendants=false
 card:FindFirstChildOfClass('UIGradient').Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(150,160,190))
 -- The gold frame and its running light.
 local frame=card:FindFirstChildOfClass('UIStroke');frame.Color=Color3.new(1,1,1);frame.Transparency=0;frame.Thickness=3
 self.frameGradient=make('UIGradient',frame,{Color=shine(.5)})
-- (the frame breathes a little: see update)
 self.frame=frame
 -- Title.
 self.ribbonBadge=Kit.badge(card,'gift',52,GOLD,UDim2.fromOffset(22,16))
 self.title=label(card,'STARTER PACK',30,Enum.FontWeight.Heavy,C.white,{Position=UDim2.fromOffset(88,14),Size=UDim2.fromOffset(330,36),ZIndex=Z+3})
 self.titleGradient=make('UIGradient',self.title,{Rotation=90,Color=ColorSequence.new(GOLD_LIGHT,GOLD)})
 label(card,'A one-time welcome deal for new admirals',13,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(90,48),Size=UDim2.fromOffset(330,18),ZIndex=Z+3})
 -- Time left.
 self.timer=corner(make('Frame',card,{Name='Timer',AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-60,0,20),Size=UDim2.fromOffset(120,30),
  BackgroundColor3=Color3.fromRGB(70,22,22),ZIndex=Z+3}),15)
 stroke(self.timer,C.red,.3,1.5)
 Icons.image(self.timer,'clock',16,C.red,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,10,.5,0),ZIndex=Z+4})
 self.timerText=label(self.timer,'',14,Enum.FontWeight.Heavy,Color3.fromRGB(255,190,180),{Position=UDim2.fromOffset(32,0),Size=UDim2.new(1,-38,1,0),ZIndex=Z+4})
 -- What is inside: six tiles in two rows.
 local items={
  {icon='coins',color=C.silver,title=compact(Products.Starter.silver)..' Silver',sub='Spend it in the arsenal'},
  {icon='bolt',color=GOLD,title='×2 Silver',sub='Forever, from every match'},
  {icon='flag',color=Color3.fromRGB(255,120,96),title="Your country's flag",sub='Next to your name',flag=true},
  {icon='pattern',color=Color3.fromRGB(176,140,255),title='A water pattern',sub='On your country\'s water',pattern=true},
  {icon='torpedo',color=Color3.fromRGB(86,170,255),title='Torpedo',sub='Unseen by missile defense'},
  {icon='cluster',color=Color3.fromRGB(255,120,96),title='Cluster Missile',sub='Six warheads at once'},
 }
 self.tiles={}
 local tw,th,gap=176,64,10
 for i,it in ipairs(items)do
  local col,rowN=(i-1)%3,(i-1)//3
  local t=corner(make('Frame',card,{Name='Item'..i,Position=UDim2.fromOffset(22+col*(tw+gap),82+rowN*(th+gap)),Size=UDim2.fromOffset(tw,th),
   BackgroundColor3=Color3.fromRGB(26,40,60),ZIndex=Z+2}),12)
  stroke(t,it.color,.55,1)
  make('UIGradient',t,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(170,175,190))})
  -- (the pattern's water in a CanvasGroup: a plain frame clips its children to a square, not to its
  -- rounded corners, and the swatch stuck out of the round frame)
  local holder=corner(make(it.pattern and 'CanvasGroup'or 'Frame',t,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,8,.5,0),Size=UDim2.fromOffset(46,46),
   BackgroundColor3=it.color:Lerp(NAVY,.6),ClipsDescendants=true,ZIndex=Z+3}),23)
  stroke(holder,it.color,.1,1.5)
  local tile={frame=t,holder=holder}
  if it.pattern then
   holder.BackgroundColor3=WATER
   Flags.swatch(holder,'pat_wave',12,WATER,TINT,Z+4)
  else
   tile.icon=Icons.image(holder,it.icon,24,C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+4})
  end
  tile.flagged=it.flag
  label(t,it.title,13,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(62,12),Size=UDim2.fromOffset(tw-68,18),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+3})
  label(t,it.sub,10,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(62,32),Size=UDim2.fromOffset(tw-68,16),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+3})
  self.tiles[i]=tile
 end
 -- The price row.
 local priceY=244
 self.worth=label(card,'',16,Enum.FontWeight.Bold,C.muted,{Position=UDim2.fromOffset(24,priceY),Size=UDim2.fromOffset(120,22),ZIndex=Z+3})
 self.strike=make('Frame',self.worth,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.fromScale(0,.5),Size=UDim2.new(0,60,0,2),BackgroundColor3=C.red,BorderSizePixel=0,ZIndex=Z+4})
 self.price=label(card,'',40,Enum.FontWeight.Heavy,C.white,{Position=UDim2.fromOffset(22,priceY+20),Size=UDim2.fromOffset(200,46),ZIndex=Z+3})
 self.priceGradient=make('UIGradient',self.price,{Rotation=90,Color=ColorSequence.new(GOLD_LIGHT,GOLD)})
 self.save=corner(make('Frame',card,{Name='Save',Position=UDim2.fromOffset(150,priceY-2),Size=UDim2.fromOffset(92,24),BackgroundColor3=C.red,Rotation=-4,ZIndex=Z+4}),8)
 self.saveText=label(self.save,'',13,Enum.FontWeight.Heavy,C.white,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+5})
 -- Buy: gold, with a shine sweeping across now and then.
 self.buy=pressable(card,{Name='Buy',BackgroundColor3=C.white,Position=UDim2.fromOffset(W-22-290,priceY+4),Size=UDim2.fromOffset(290,68),ClipsDescendants=true,ZIndex=Z+3},function()self:purchase()end)
 corner(self.buy,18);Kit.primary(self.buy)
 self.buyText=label(self.buy,'BUY NOW',22,Enum.FontWeight.Heavy,C.dark,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+5})
 self.sweep=make('Frame',shineLayer(self.buy,18,Z+4),{Name='Shine',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(-.3,0,.5,0),Size=UDim2.new(0,46,2,0),Rotation=20,
  BackgroundColor3=C.white,BackgroundTransparency=.55,BorderSizePixel=0,ZIndex=Z+4})
 make('UIGradient',self.sweep,{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})})
 self.note=label(card,'Once per account · only for '..Products.Starter.hours..' hours',11,Enum.FontWeight.Medium,C.muted,
  {Position=UDim2.fromOffset(0,H-26),Size=UDim2.new(1,0,0,16),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+3})
 -- Sparks: small white stars twinkling around the title and the price.
 self.sparks={}
 for i,p in ipairs({{70,14},{410,22},{250,6},{560,96},{14,236},{300,240},{560,230},{120,330}})do
  local s=make('Frame',card,{Name='Spark',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(p[1],p[2]),Size=UDim2.fromOffset(10,10),
   Rotation=45,BackgroundColor3=GOLD_LIGHT,BorderSizePixel=0,ZIndex=Z+6})
  self.sparks[i]={frame=s,phase=i*.77}
 end
 -- The lobby's gold tile: the pack and the time left; a tap opens the window.
 local tile=pressable(parent,{Name='StarterTile',AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,12,.5,0),Size=UDim2.fromOffset(112,104),
  BackgroundColor3=C.white,Visible=false,ClipsDescendants=true,ZIndex=41},function()self:show(true)end)
 corner(tile,16);Kit.primary(tile)
 self.tile=tile
 self.tileScale=make('UIScale',tile,{Scale=1})
 self.tileIcon=Icons.image(tile,'gift',36,C.dark,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,10),ZIndex=42})
 label(tile,'STARTER PACK',12,Enum.FontWeight.Heavy,C.dark,{Position=UDim2.fromOffset(0,50),Size=UDim2.new(1,0,0,16),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=42})
 self.tileTime=label(tile,'',12,Enum.FontWeight.Heavy,Color3.fromRGB(120,30,20),{Position=UDim2.fromOffset(0,68),Size=UDim2.new(1,0,0,16),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=42})
 self.tilePrice=label(tile,'',11,Enum.FontWeight.Bold,C.dark,{Position=UDim2.fromOffset(0,84),Size=UDim2.new(1,0,0,14),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=42})
 self.tileSweep=make('Frame',shineLayer(tile,16,43),{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(-.3,0,.5,0),Size=UDim2.new(0,30,2,0),Rotation=20,
  BackgroundColor3=C.white,BackgroundTransparency=.5,BorderSizePixel=0,ZIndex=43})
 make('UIGradient',self.tileSweep,{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})})
 Store.onFinished(function(key,purchased)
  if key=='starter_pack'and purchased then Sfx.play('build');self:show(false)end
 end)
 return self
end
-- After the purchase: what came out of the pack (2026-11-16, by the author's request). Gold rays turn behind
-- a card, "YOU GOT IT!", and the six things pop in one after another — the real flag and pattern drawn,
-- with their names and rarity — then a button closes it. data = {items = {ids}, silver} from the server.
function O:reward(data)
 local parent=self.lobby.root.Parent
 self.starterReward=nil
 if self.rewardLayer then self.rewardLayer:Destroy()end
 self:show(false)
 -- (nothing else over it: the daily reward, the shop and the chest close)
 local lobby=self.lobby
 if lobby.daily and lobby.daily.open then lobby.daily:show(false)end
 if lobby.shop and lobby.shop.open then lobby.shop:show(false)end
 if lobby.chest and lobby.chest.open then lobby.chest:setOpen(false)end
 local layer=make('TextButton',parent,{Name='StarterReward',Text='',AutoButtonColor=false,BackgroundColor3=C.ink,BackgroundTransparency=.25,
  Size=UDim2.new(1,0,1,80),Position=UDim2.fromOffset(0,-80),ZIndex=Z+20})
 self.rewardLayer=layer
 local center=make('Frame',layer,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,.5,40),Size=UDim2.fromOffset(560,330),ZIndex=Z+21})
 local scale=make('UIScale',center,{Scale=.6})
 local size=self.v.gui.AbsoluteSize
 local fit=math.clamp(math.min((size.X-24)/600,(size.Y-24)/360),.45,1.3)
 TweenService:Create(scale,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=fit}):Play()
 -- rays: gold bands through the middle, turning slowly behind everything (a frame turns about its own
 -- centre, so each band is centred on the burst and fades towards both ends)
 local rays=make('Frame',center,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(10,10),ZIndex=Z+21})
 for i=1,6 do
  local r=make('Frame',rays,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(54,900),Rotation=i*30,
   BackgroundColor3=GOLD,BackgroundTransparency=.8,BorderSizePixel=0,ZIndex=Z+21})
  make('UIGradient',r,{Rotation=90,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.35,.3),
   NumberSequenceKeypoint.new(.5,.6),NumberSequenceKeypoint.new(.65,.3),NumberSequenceKeypoint.new(1,1)})})
 end
 local title=label(center,'YOU GOT IT!',38,Enum.FontWeight.Heavy,C.white,{Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,46),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+24})
 make('UIGradient',title,{Rotation=90,Color=ColorSequence.new(GOLD_LIGHT,GOLD)})
 label(center,'Starter Pack · yours forever',14,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(0,46),Size=UDim2.new(1,0,0,18),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+24})
 -- what to show: the flag and the pattern actually given (or "silver" when they were owned already)
 local flag,pattern
 for _,id in ipairs(type(data.items)=='table'and data.items or {})do
  local item=Catalog.Cosmetics[id]
  if item and item.kind=='flag'then flag=id elseif item and item.kind=='pattern'then pattern=id end
 end
 local things={
  {icon='coins',color=C.silver,title=compact(math.max(Products.Starter.silver,tonumber(data.silver)or 0))..' Silver',sub='Added to your balance'},
  {icon='bolt',color=GOLD,title='×2 Silver',sub='Forever, from every match'},
  {icon='flag',color=Color3.fromRGB(255,120,96),flag=flag,title=flag and Catalog.Cosmetics[flag].title or 'Flag',sub=flag and 'Flag · next to your name'or 'Owned already: silver'},
  {icon='pattern',color=Color3.fromRGB(176,140,255),pattern=pattern,title=pattern and Catalog.Cosmetics[pattern].title or 'Pattern',
   sub=pattern and(Catalog.Rarity[Catalog.Cosmetics[pattern].rarity].title..' pattern')or 'Owned already: silver',
   rarity=pattern and Catalog.Cosmetics[pattern].rarity},
  {icon='torpedo',color=Color3.fromRGB(86,170,255),title='Torpedo',sub='Unlocked in your arsenal'},
  {icon='cluster',color=Color3.fromRGB(255,120,96),title='Cluster Missile',sub='Unlocked in your arsenal'},
 }
 local tw,th,gap=176,70,10
 for i,it in ipairs(things)do
  local col,row=(i-1)%3,(i-1)//3
  local t=corner(make('Frame',center,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(8+tw/2+col*(tw+gap),96+th/2+row*(th+gap)),Size=UDim2.fromOffset(tw,th),
   BackgroundColor3=Color3.fromRGB(26,40,60),ZIndex=Z+24}),12)
  local line=it.rarity and Color3.fromRGB(table.unpack(Catalog.Rarity[it.rarity].color))or it.color
  stroke(t,line,.2,1.5)
  local s=make('UIScale',t,{Scale=0})
  local holder=corner(make(it.pattern and 'CanvasGroup'or 'Frame',t,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,10,.5,0),Size=UDim2.fromOffset(48,48),
   BackgroundColor3=it.color:Lerp(NAVY,.6),ZIndex=Z+25}),24)
  if it.pattern then holder.BackgroundColor3=WATER;Flags.swatch(holder,it.pattern,12,WATER,TINT,Z+26)
  elseif it.flag then holder.BackgroundColor3=NAVY;Flags.image(holder,it.flag,24,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+26})
  else Icons.image(holder,it.icon,26,C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+26})end
  stroke(holder,line,.1,1.5)
  label(t,it.title,14,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(66,14),Size=UDim2.fromOffset(tw-72,18),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+25})
  label(t,it.sub,10,Enum.FontWeight.Medium,it.rarity and line or C.muted,{Position=UDim2.fromOffset(66,36),Size=UDim2.fromOffset(tw-72,16),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+25})
  task.delay(.35+i*.14,function()
   if t.Parent then TweenService:Create(s,TweenInfo.new(.38,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()end
  end)
 end
 local done=pressable(center,{Name='Done',BackgroundColor3=C.white,AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,272),Size=UDim2.fromOffset(240,54),ZIndex=Z+24},function()
  if self.rewardLayer then self.rewardLayer:Destroy();self.rewardLayer=nil end
  self.starterReward=nil
 end)
 corner(done,16);Kit.primary(done)
 label(done,'AWESOME!',20,Enum.FontWeight.Heavy,C.dark,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+25})
 self.starterReward={rays=rays,title=title,t=0}
end
-- On offer for this profile now (the product exists, not bought yet, inside the 48 hours).
function O:available()
 local p=self.v.profile
 return p~=nil and Store.available('starter_pack')and Products.starterOpen(p,workspace:GetServerTimeNow())
end
function O:purchase()
 if not self:available()then return end
 Sfx.play('click');Store.prompt('starter_pack')
end
function O:show(open)
 -- (never under the reward window: the offer is gone once bought, and it must not show behind it)
 open=open==true and self:available()and not self.rewardLayer
 if open==self.open then return end
 self.open=open;self.shade.Visible=open;self.card.Visible=open
 if open then
  -- Its 48 hours start at the first showing; the server keeps the time.
  local p=self.v.profile
  if p and not p.starter and not self.seenAsked then self.seenAsked=true;task.spawn(function()self.v:request('starter_seen')end)end
  -- (the player's own flag on its tile, once the country is known)
  if not self.flagShown then
   self.flagShown=true
   task.spawn(function()
    local ok,code=pcall(function()return game:GetService('LocalizationService'):GetCountryRegionForPlayerAsync(game:GetService('Players').LocalPlayer)end)
    local id=ok and Catalog.countryFlag(code)
    local tile=self.tiles[3]
    if id and tile then tile.icon.Visible=false;tile.holder.BackgroundColor3=NAVY;Flags.image(tile.holder,id,22,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+4})end
   end)
  end
  self:layout(self.v.gui.AbsoluteSize)
  self.scale.Scale=(self.fit or 1)*.85;TweenService:Create(self.scale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=self.fit or 1}):Play()
 end
end
function O:layout(size)
 if self.lastSize==size then return end
 self.lastSize=size
 self.fit=math.clamp(math.min((size.X-24)/(W+40),(size.Y-24)/(H+40)),.45,1.3);self.scale.Scale=self.fit
 local phone=size.X<900 or size.Y<520
 -- (on a phone above the strip at the left edge, smaller)
 self.tileScale.Scale=phone and .8 or 1
 self.tile.Position=phone and UDim2.new(0,8,.42,0)or UDim2.new(0,12,.5,0)
end
function O:isUI(obj)
 if self.open or self.rewardLayer then return true end
 return self.tile.Visible and(obj==self.tile or obj:IsDescendantOf(self.tile))
end
-- Every frame from the lobby: `menu` while the lobby's home page is up.
function O:update(dt,menu)
 self.clock+=dt
 local reward=self.starterReward
 if reward and reward.rays.Parent then
  reward.t+=dt
  reward.rays.Rotation=reward.t*18
  reward.title.Rotation=math.sin(reward.t*2.4)*2
 end
 local available=self:available()
 if self.open and not available then self:show(false)end
 local p=self.v.profile
 local left=p and p.starter and p.starter.ends and(p.starter.ends-workspace:GetServerTimeNow())or Products.Starter.hours*3600
 local time=Kit.countdown(left)..(left>=3600 and ' h'or '')..' left'
 local tileOn=available and menu
 if self.tile.Visible~=tileOn then self.tile.Visible=tileOn end
 if tileOn then
  self:layout(self.v.gui.AbsoluteSize)
  if self.tileTime.Text~=time then self.tileTime.Text=time end
  self.tilePrice.Text=Store.label('starter_pack')
  -- a little hop every few seconds and a shine across
  local beat=self.clock%3.2
  self.tileIcon.Position=UDim2.new(.5,0,0,10-(beat<.4 and math.sin(beat/.4*math.pi)*6 or 0))
  self.tileSweep.Position=UDim2.new(-.3+math.clamp((self.clock%2.6)/1.1,0,1)*1.6,0,.5,0)
 end
 if not self.open then return end
 self:layout(self.v.gui.AbsoluteSize)
 self.timerText.Text=time
 -- The light runs round the frame; the sparks twinkle; the shine sweeps the Buy button.
 self.frameGradient.Rotation=(self.clock*90)%360
 self.titleGradient.Color=shine((self.clock*.45)%1.6-.3)
 self.frame.Thickness=3+math.max(0,math.sin(self.clock*2.4))*1.5
 for _,s in ipairs(self.sparks)do
  local k=math.max(0,math.sin(self.clock*2.2+s.phase*3))
  local d=math.floor(4+k*8);s.frame.Size=UDim2.fromOffset(d,d);s.frame.BackgroundTransparency=1-k*.95
 end
 self.sweep.Position=UDim2.new(-.3+math.clamp((self.clock%2.4)/.9,0,1)*1.6,0,.5,0)
 local pulse=1+math.max(0,math.sin(self.clock*3))*.025
 self.buyText.TextSize=math.floor(22*pulse+.5)
 -- Prices: Roblox's own price once known.
 local price=Store.robux('starter_pack')or Products.list.starter_pack.robux
 local worth=Products.starterWorth()
 local worthText=worth..' R$'
 if self.worth.Text~=worthText then
  self.worth.Text=worthText
  self.strike.Size=UDim2.new(0,self.worth.TextBounds.X+4,0,2)
 end
 self.strike.Size=UDim2.new(0,self.worth.TextBounds.X+4,0,2)
 self.price.Text=price..' R$'
 local save=math.floor((1-price/worth)*100+.5)
 self.save.Visible=save>0
 self.saveText.Text='SAVE '..save..'%'
 self.buy.Active=available
end
return O
