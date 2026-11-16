--!nonstrict
-- The chest window (2026-11-12, by the author's request): a chest that gives one random flag or water
-- pattern the player does not own yet. Since 2026-11-16 (the author's decision) chests are free — they drop
-- from won matches and online top places (Catalog.chestDrops) — and each takes a golden key to open; the
-- keys are what is sold.
--  * left: the chest itself and the "Open" button (it buys a key when there is a chest but no key);
--  * right: the player's own odds by rarity, how much is left to collect, and the three key offers for
--    Robux (1, 3 or 10 keys; an offer whose product has no id yet says so instead of a price).
--  * top: how many chests and keys wait.
-- Opening is a short show over the window: the chest shakes, glows in the colour of the rarity drawn,
-- bursts open, and a card turns up with the thing, its rarity and name: wear it, open the next one, or done.
-- The server draws the item (command "chest_open", server/Account.openChest); the show starts at once and
-- waits for the answer. The chest art is our own, drawn with frames.
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

local K={};K.__index=K
local Z=54
local W,H=640,404
local WATER,TINT=Color3.fromRGB(58,120,150),Color3.fromRGB(110,170,196)
local WOOD,WOOD_DARK,GOLD=Color3.fromRGB(150,92,44),Color3.fromRGB(96,56,26),Color3.fromRGB(240,188,72)
local BUILD={common=.35,rare=.6,epic=.95,legendary=1.5}   -- seconds of rising glow before the burst
local OFFER_TEXT={chest_1={'1','key'},chest_3={'3','keys'},chest_10={'10','keys'}}
local REASONS={no_chest='No chests yet: win matches to get them',no_key='You need a golden key',store='Could not save. Try again.',no_reply='No answer from the server'}
-- (Luau's string.upper leaves Cyrillic as it is)
local UPPER={common='COMMON',rare='RARE',epic='EPIC',legendary='LEGENDARY'}
local function rgb(t)return Color3.fromRGB(t[1],t[2],t[3])end
local function rarityColor(r)return rgb((Catalog.Rarity[r]or Catalog.Rarity.common).color)end

-- The golden key: the author's own pictures (2026-11-16, made from docs/trailer/goldenkey.png: a gold key and
-- a charcoal one, the hole cut out). Gold on the window's dark tiles, charcoal on the gold tile. They are
-- built here in an EditableImage from the pixels in shared/KeyPixels (tools/make_keys.py): the uploaded
-- copies stay private to the author (players saw no key in the published game, Studio did), so they are only
-- the fallback when no EditableImage can be made. `s`: the picture's side in points.
local KeyPixels=require(script.Parent.KeyPixels)
local KEY_GOLD,KEY_CHARCOAL='rbxassetid://82194758169670','rbxassetid://125786457127449'
local keyContent={}
local function hexAt(str,i)local b=string.byte(str,i);return b<=57 and b-48 or b-87 end
local function buildKey(name)
 if keyContent[name]~=nil then return keyContent[name]end
 keyContent[name]=false
 local side=KeyPixels.side;local data=KeyPixels[name]
 local ok,img=pcall(function()return game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(side,side)})end)
 if not ok or not img then return false end
 local buf=buffer.create(side*side*4)
 local i,pos,n=1,0,#data
 while i<=n do
  if string.byte(data,i)==122 then pos+=tonumber(string.sub(data,i+1,i+3),16)+1;i+=4
  else
   local r,g,b,a=hexAt(data,i)*17,hexAt(data,i+1)*17,hexAt(data,i+2)*17,hexAt(data,i+3)*17
   local run=hexAt(data,i+4)+1
   for k=pos,pos+run-1 do buffer.writeu8(buf,k*4,r);buffer.writeu8(buf,k*4+1,g);buffer.writeu8(buf,k*4+2,b);buffer.writeu8(buf,k*4+3,a)end
   pos+=run;i+=5
  end
 end
 if pcall(function()img:WritePixelsBuffer(Vector2.zero,Vector2.new(side,side),buf)end)then keyContent[name]=Content.fromObject(img)end
 return keyContent[name]
end
local function setKey(image,gold)
 local content=buildKey(gold and 'gold'or 'charcoal')
 if content then image.ImageContent=content else image.Image=gold and KEY_GOLD or KEY_CHARCOAL end
end
local function keyArt(parent,s,color,z)
 local img=make('ImageLabel',parent,{Name='Key',AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Size=UDim2.fromOffset(s,s),ZIndex=z})
 setKey(img,color==GOLD)
 return {root=img,gold=color==GOLD}
end
local function tintKey(key,color)
 local gold=color==GOLD
 if key.gold~=gold then key.gold=gold;setKey(key.root,gold)end
end
-- The chest drawn with frames, `s` points wide: {root, lid, body, glow (three rings behind it)}.
local function chestArt(parent,s,z)
 local root=make('Frame',parent,{Name='Chest',AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Size=UDim2.fromOffset(s,s*.9),ZIndex=z})
 local glow={}
 for i,k in ipairs({1.9,1.45,1.05})do
  glow[i]=corner(make('Frame',root,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.55),Size=UDim2.fromOffset(s*k,s*k),
   BackgroundColor3=C.amber,BackgroundTransparency=1,ZIndex=z}),s)
 end
 local body=corner(make('Frame',root,{Name='Body',AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,s*.4),Size=UDim2.fromOffset(s,s*.48),BackgroundColor3=WOOD,ZIndex=z+1}),math.floor(s*.05))
 make('UIStroke',body,{Color=WOOD_DARK,Thickness=math.max(2,s*.025)})
 make('UIGradient',body,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(150,150,150))})
 for i=1,2 do make('Frame',body,{Position=UDim2.new(0,0,i/3,0),Size=UDim2.new(1,0,0,math.max(1,s*.015)),BackgroundColor3=WOOD_DARK,BorderSizePixel=0,ZIndex=z+2})end
 local lid=corner(make('Frame',root,{Name='Lid',AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,0,s*.42),Size=UDim2.fromOffset(s*1.04,s*.34),BackgroundColor3=WOOD,ZIndex=z+3}),math.floor(s*.12))
 make('UIStroke',lid,{Color=WOOD_DARK,Thickness=math.max(2,s*.025)})
 make('UIGradient',lid,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(175,175,175))})
 -- gold bands over lid and body, a rim between them and the lock
 for _,x in ipairs({.2,.8})do
  make('Frame',body,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(x,0),Size=UDim2.new(0,s*.07,1,0),BackgroundColor3=GOLD,BorderSizePixel=0,ZIndex=z+3})
  make('Frame',lid,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(.5+(x-.5)*.96,0),Size=UDim2.new(0,s*.07,1,0),BackgroundColor3=GOLD,BorderSizePixel=0,ZIndex=z+4})
 end
 make('Frame',lid,{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,s*.05),BackgroundColor3=GOLD,BorderSizePixel=0,ZIndex=z+4})
 local lock=corner(make('Frame',root,{Name='Lock',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,s*.45),Size=UDim2.fromOffset(s*.16,s*.2),BackgroundColor3=GOLD,ZIndex=z+5}),math.floor(s*.03))
 make('UIStroke',lock,{Color=Color3.fromRGB(150,104,30),Thickness=math.max(1,s*.015)})
 corner(make('Frame',lock,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.45),Size=UDim2.fromOffset(s*.05,s*.08),BackgroundColor3=Color3.fromRGB(60,36,12),ZIndex=z+6}),math.floor(s*.025))
 return {root=root,lid=lid,body=body,lock=lock,glow=glow,size=s}
end

function K.new(lobby)
 local self=setmetatable({lobby=lobby,v=lobby.v,open=false,busy=false,clock=0},K)
 local w=Kit.window(lobby.root.Parent,'ChestWindow',Z,W,H,function()if not self.show then self:setOpen(false)end end)
 self.shade,self.card,self.scale=w.shade,w.card,w.scale
 local inset=game:GetService('GuiService'):GetGuiInset().Y
 self.shade.Position=UDim2.fromOffset(0,-inset);self.shade.Size=UDim2.new(1,0,1,inset)
 Kit.badge(self.card,'chest',40,C.amber,UDim2.fromOffset(20,14))
 label(self.card,'CHEST',20,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(72,14),Size=UDim2.fromOffset(200,40)})
 -- How many chests and keys wait, left of the close button.
 self.countPill=corner(make('Frame',self.card,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-62,0,18),Size=UDim2.fromOffset(110,28),BackgroundColor3=C.ink,BackgroundTransparency=.25,ZIndex=Z+2}),14)
 stroke(self.countPill,C.amber,.55,1)
 Icons.image(self.countPill,'chest',16,C.amber,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,9,.5,0),ZIndex=Z+3})
 self.countText=label(self.countPill,'',13,Enum.FontWeight.Heavy,C.amber,{Position=UDim2.fromOffset(30,0),Size=UDim2.new(1,-36,1,0)})
 self.keyPill=corner(make('Frame',self.card,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-180,0,18),Size=UDim2.fromOffset(96,28),BackgroundColor3=C.ink,BackgroundTransparency=.25,ZIndex=Z+2}),14)
 stroke(self.keyPill,GOLD,.45,1)
 local pk=keyArt(self.keyPill,18,GOLD,Z+3);pk.root.Position=UDim2.new(0,18,.5,0)
 self.keyText=label(self.keyPill,'',13,Enum.FontWeight.Heavy,GOLD,{Position=UDim2.fromOffset(31,0),Size=UDim2.new(1,-37,1,0)})
 -- Left: the stage with the chest, the open button under it.
 self.stage=corner(make('Frame',self.card,{Name='Stage',Position=UDim2.fromOffset(20,68),Size=UDim2.fromOffset(268,246),BackgroundColor3=C.ink,BackgroundTransparency=.3,ClipsDescendants=true,ZIndex=Z+2}),16)
 stroke(self.stage,C.amber,.75,1)
 make('UIGradient',self.stage,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(150,150,160))})
 self.art=chestArt(self.stage,128,Z+3);self.art.root.Position=UDim2.fromScale(.5,.5)
 for i,g in ipairs(self.art.glow)do g.BackgroundTransparency=.8+i*.04 end
 self.openButton=pressable(self.card,{Name='Open',Position=UDim2.fromOffset(20,326),Size=UDim2.fromOffset(268,56),ZIndex=Z+2},function()self:openOne()end)
 corner(self.openButton,16);Kit.primary(self.openButton)
 self.openText=label(self.openButton,'OPEN',18,Enum.FontWeight.Heavy,C.dark,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 -- Right: what it gives and the odds.
 label(self.card,'A random flag or pattern',17,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(308,66),Size=UDim2.fromOffset(312,22)})
 -- (where chests come from, under the stage)
 self.how=label(self.card,'Win matches for chests · a golden key opens one',11,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(20,384),Size=UDim2.fromOffset(268,14),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+2})
 -- "Details": the chance of every item (Roblox's rule for paid random items: every outcome's odds before
 -- the purchase, behind a button with a word on it; a bare "?" is not enough).
 self.oddsButton=pressable(self.card,{Name='Odds',AnchorPoint=Vector2.new(1,0),Position=UDim2.fromOffset(620,63),Size=UDim2.fromOffset(92,28),BackgroundColor3=C.tile,ZIndex=Z+3},function()
  if not self.show then self:showOdds(true)end
 end)
 corner(self.oddsButton,14);stroke(self.oddsButton,C.white,.75,1)
 label(self.oddsButton,'Details',13,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+4})
 self.oddsRows={}
 local oddsTop, rowHeight, rowGap = 96, 32, 4
 for i,rarity in ipairs(Catalog.RarityOrder)do
  local y = oddsTop + (i-1)*(rowHeight+rowGap)
  local row=corner(make('Frame',self.card,{Position=UDim2.fromOffset(308,y),Size=UDim2.fromOffset(312,rowHeight),BackgroundColor3=C.tile,BackgroundTransparency=.3,ZIndex=Z+2}),8)
  corner(make('Frame',row,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,8,.5,0),Size=UDim2.fromOffset(10,10),BackgroundColor3=rarityColor(rarity),ZIndex=Z+3}),5)
  label(row,Catalog.Rarity[rarity].title,13,Enum.FontWeight.Bold,rarityColor(rarity),{Position=UDim2.fromOffset(26,0),Size=UDim2.fromOffset(100,32)})
  local value=label(row,'',13,Enum.FontWeight.Heavy,C.text,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,0),Size=UDim2.new(.4,0,1,0),TextXAlignment=Enum.TextXAlignment.Right})
  self.oddsRows[rarity]=value
 end
 self.left=label(self.card,'',12,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(308,244),Size=UDim2.fromOffset(312,18)})
 self.note=label(self.card,'',12,Enum.FontWeight.Bold,C.amber,{Position=UDim2.fromOffset(308,244),Size=UDim2.fromOffset(312,18),Visible=false})
 -- The offers for Robux.
 self.offers={}
 local ow=(312-2*8)/3
 for i,key in ipairs(Products.ChestOffers)do
  local o={key=key}
  o.button=pressable(self.card,{Name=key,Position=UDim2.fromOffset(308+(i-1)*(ow+8),268),Size=UDim2.fromOffset(ow,114),BackgroundColor3=C.tile,ZIndex=Z+2},function()
   if self.restricted then Sfx.play('deny');self:say('Chest purchases are not available for your account');return end
   -- (the single chest is the first-price product while the account still has some at 15)
   if not self.busy and not self.show then Store.prompt(i==1 and self:singleKey()or key)end
  end)
  corner(o.button,14);o.stroke=stroke(o.button,C.robux,.55,1)
  make('UIGradient',o.button,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(175,180,190))})
  o.keyIcon=keyArt(o.button,40,GOLD,Z+3);o.keyIcon.root.Position=UDim2.new(.5,0,0,24)
  o.count=label(o.button,OFFER_TEXT[key][1],22,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(0,47),Size=UDim2.new(1,0,0,22),TextXAlignment=Enum.TextXAlignment.Center})
  o.sub=label(o.button,OFFER_TEXT[key][2],11,Enum.FontWeight.Bold,C.muted,{Position=UDim2.fromOffset(0,67),Size=UDim2.new(1,0,0,12),TextXAlignment=Enum.TextXAlignment.Center})
  o.price=corner(make('Frame',o.button,{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-8),Size=UDim2.new(1,-14,0,26),BackgroundColor3=C.card,ZIndex=Z+3}),9)
  o.priceStroke=stroke(o.price,C.robux,.5,1)
  o.priceText=label(o.price,'',13,Enum.FontWeight.Heavy,C.robux,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
  -- (the larger packs say what they save against single chests; the single one says "first 2" while it
  -- is at the first price)
  o.tag=corner(make('Frame',o.button,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,4,0,-6),Size=UDim2.fromOffset(i==1 and 50 or 46,18),BackgroundColor3=C.red,Visible=false,ZIndex=Z+4}),9)
  o.tagText=label(o.tag,'',10,Enum.FontWeight.Heavy,C.white,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
  self.offers[i]=o
 end
 self:buildShow()
 self:buildOdds()
 -- Paid random items are not allowed for some accounts (Roblox's PolicyService): the offers turn off,
 -- chests already owned still open. (Until Roblox answers they count as off.)
 self.restricted=true
 task.spawn(function()
  local ok,info=pcall(function()
   return game:GetService('PolicyService'):GetPolicyInfoForPlayerAsync(game:GetService('Players').LocalPlayer)
  end)
  self.restricted=not ok or type(info)~='table'or info.ArePaidRandomItemsRestricted==true
 end)
 Store.onFinished(function(key,purchased)
  if self.open and purchased and key and string.sub(key,1,6)=='chest_'then Sfx.play('build');self:say('Paid, the keys are yours')end
 end)
 return self
end

-- The opening show: a layer over the whole card.
-- The odds page: every item the chest can give this player now and its chance, by rarity.
function K:buildOdds()
 local o=corner(make('TextButton',self.card,{Name='OddsPage',Text='',AutoButtonColor=false,Size=UDim2.fromScale(1,1),BackgroundColor3=C.card,Visible=false,ZIndex=Z+15}),20)
 self.oddsPage=o
 label(o,'DROP CHANCES',18,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(24,18),Size=UDim2.new(1,-90,0,30),ZIndex=Z+16})
 local close=pressable(o,{Name='Close',AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-14,0,14),Size=UDim2.fromOffset(36,36),BackgroundColor3=C.tile,ZIndex=Z+16},function()self:showOdds(false)end)
 corner(close,18);stroke(close,C.white,.85,1)
 Icons.image(close,'close',14,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+17})
 self.oddsList=make('ScrollingFrame',o,{Position=UDim2.fromOffset(20,62),Size=UDim2.new(1,-40,1,-78),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,
  ScrollBarImageColor3=C.accent,ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ZIndex=Z+16})
 make('UIListLayout',self.oddsList,{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder})
 make('UIPadding',self.oddsList,{PaddingRight=UDim.new(0,8),PaddingTop=UDim.new(0,2)})
end
function K:showOdds(open)
 self.oddsPage.Visible=open
 if not open then return end
 for _,c in ipairs(self.oddsList:GetChildren())do if c:IsA('GuiObject')then c:Destroy()end end
 local p=self.v.profile
 local pool=Catalog.chestPool(p and p.owned or {})
 local odds=Catalog.chestOdds(p and p.owned or {})
 local function percent(x)
  local t=string.format(x<.01 and '%.3f'or x<1 and '%.2f'or '%.1f',x)
  return (t:gsub('0+$',''):gsub('%.$',''))..'%'
 end
 -- One plain list, the likeliest first (2026-11-12, the author's request: no pictures, no groups).
 local rows={}
 for _,rarity in ipairs(Catalog.RarityOrder)do
  local ids=pool[rarity]
  if ids and #ids>0 then
   for _,id in ipairs(ids)do table.insert(rows,{id=id,chance=odds[rarity]/#ids*100})end
  end
 end
 table.sort(rows,function(a,b)if a.chance~=b.chance then return a.chance>b.chance end return a.id<b.id end)
 for order,r in ipairs(rows)do
  local item=Catalog.Cosmetics[r.id]
  local row=corner(make('Frame',self.oddsList,{Size=UDim2.new(1,0,0,28),BackgroundColor3=C.tile,BackgroundTransparency=.35,LayoutOrder=order,ZIndex=Z+17}),8)
  label(row,item.title..(item.kind=='flag'and ' · flag'or ' · pattern'),13,Enum.FontWeight.Medium,C.text,{Position=UDim2.fromOffset(12,0),Size=UDim2.new(1,-110,1,0),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+18})
  label(row,percent(r.chance),13,Enum.FontWeight.Heavy,C.text,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,0),Size=UDim2.fromOffset(80,28),TextXAlignment=Enum.TextXAlignment.Right,ZIndex=Z+18})
 end
 -- (Roblox asks for this line when the shown percentages are rounded)
 label(self.oddsList,'Chances are rounded, so their sum may differ slightly from 100%.',11,Enum.FontWeight.Medium,C.muted,{Size=UDim2.new(1,0,0,22),LayoutOrder=#rows+1,ZIndex=Z+17})
end
function K:buildShow()
 local o=corner(make('TextButton',self.card,{Name='Show',Text='',AutoButtonColor=false,Size=UDim2.fromScale(1,1),BackgroundColor3=C.ink,BackgroundTransparency=.04,Visible=false,ZIndex=Z+20}),20)
 o.Activated:Connect(function()if self.show and self.show.phase=='card'then self.show.hold=0 end end)
 self.showLayer=o
 self.showArt=chestArt(o,170,Z+21);self.showArt.root.Position=UDim2.fromScale(.5,.56)
 self.flash=corner(make('Frame',o,{Size=UDim2.fromScale(1,1),BackgroundColor3=C.white,BackgroundTransparency=1,ZIndex=Z+30}),20)
 self.sparks={}
 for i=1,24 do self.sparks[i]=corner(make('Frame',o,{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(6,6),BackgroundColor3=C.amber,Visible=false,ZIndex=Z+29}),3)end
 self.showTitle=label(o,'',13,Enum.FontWeight.Heavy,C.muted,{Position=UDim2.fromOffset(0,22),Size=UDim2.new(1,0,0,20),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+22})
 -- The card that turns up.
 local card=corner(make('Frame',o,{Name='Reveal',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.45),Size=UDim2.fromOffset(250,250),BackgroundColor3=C.tile,Visible=false,ZIndex=Z+24}),18)
 self.revealStroke=stroke(card,C.amber,0,2)
 make('UIGradient',card,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(170,175,185))})
 self.revealScale=make('UIScale',card,{Scale=1})
 self.reveal=card
 self.revealNew=corner(make('Frame',card,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,0),Size=UDim2.fromOffset(78,22),BackgroundColor3=C.red,ZIndex=Z+27}),11)
 label(self.revealNew,'NEW!',12,Enum.FontWeight.Heavy,C.white,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 self.revealBox=corner(make('Frame',card,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,26),Size=UDim2.fromOffset(150,110),BackgroundColor3=C.ink,BackgroundTransparency=.3,ClipsDescendants=true,ZIndex=Z+25}),12)
 self.revealRarity=label(card,'',13,Enum.FontWeight.Heavy,C.amber,{Position=UDim2.fromOffset(0,146),Size=UDim2.new(1,0,0,18),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+25})
 self.revealName=label(card,'',22,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(10,166),Size=UDim2.new(1,-20,0,28),TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+25})
 self.revealKind=label(card,'',12,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(10,198),Size=UDim2.new(1,-20,0,34),TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=Z+25})
 -- What to do next.
 self.choice=make('Frame',o,{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-18),Size=UDim2.fromOffset(460,46),BackgroundTransparency=1,Visible=false,ZIndex=Z+24})
 local function button(name,x,w,text,primary,fn)
  local b=pressable(self.choice,{Name=name,Position=UDim2.fromOffset(x,0),Size=UDim2.fromOffset(w,46),BackgroundColor3=C.tile,ZIndex=Z+25},fn)
  corner(b,14)
  if primary then Kit.primary(b)else stroke(b,C.white,.8,1)end
  local t=label(b,text,15,Enum.FontWeight.Heavy,primary and C.dark or C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+26})
  return b,t
 end
 self.wearButton,self.wearText=button('Wear',0,150,'WEAR',false,function()self:wear()end)
 self.nextButton,self.nextText=button('Next',158,150,'AGAIN',true,function()self:openOne()end)
 self.doneButton=button('Done',316,144,'DONE',false,function()self:endShow()end)
end

-- The single chest's product now: the first price while the account has some left (and it is on sale).
function K:singleKey()
 local p=self.v.profile
 if Products.chestFirstLeft(p)>0 and Store.available('chest_first')then return 'chest_first'end
 return 'chest_1'
end
function K:say(text)self.noteText=text;self.noteUntil=os.clock()+4 end
function K:chests()local p=self.v.profile;return p and p.credits and p.credits.chest or 0 end
function K:keys()local p=self.v.profile;return p and p.credits and p.credits.key or 0 end

-- Open one chest: the show starts now, the server's answer arrives during it.
function K:openOne()
 if self.busy then return end
 if self:chests()<1 then Sfx.play('deny');self:say(REASONS.no_chest);if self.show then self:endShow()end;return end
 -- A chest but no key: the button buys one (the single key's offer).
 if self:keys()<1 then
  if self.show then self:endShow()end
  if self.restricted then Sfx.play('deny');self:say('Key purchases are not available for your account');return end
  Store.prompt(self:singleKey());return
 end
 self.busy=true
 local show={t=0,phase='shake',hold=.6}
 self.show=show
 self.showLayer.Visible=true;self.reveal.Visible=false;self.choice.Visible=false
 self.showArt.root.Visible=true;self.showArt.lid.Position=UDim2.new(.5,0,0,self.showArt.size*.42);self.showArt.lid.Rotation=0;self.showArt.lid.BackgroundTransparency=0
 for _,g in ipairs(self.showArt.glow)do g.BackgroundColor3=C.amber end
 self.showTitle.Text='OPENING THE CHEST…';self.showTitle.TextColor3=C.muted
 Sfx.play('click')
 task.spawn(function()
  local r=self.v:request('chest_open')
  self.busy=false
  if self.show~=show then return end
  if r and r.ok then show.result=r
  else show.failed=(r and REASONS[r.reason])or 'The chest did not open. It is saved, try again.'end
 end)
end
function K:endShow()
 self.show=nil;self.showLayer.Visible=false
end
function K:wear()
 local r=self.show and self.show.result;local id=r and r.item;local item=id and Catalog.Cosmetics[id]
 if not item or self.busy then return end
 self.busy=true
 task.spawn(function()
  local res=self.v:request('equip',{slot=item.kind,id=id})
  self.busy=false
  if res and res.ok then Sfx.play('build');if self.show and self.show.result==r then self.show.worn=true end end
 end)
end
-- Fill the card with what came out.
function K:fillReveal(r)
 for _,c in ipairs(self.revealBox:GetChildren())do if c:IsA('GuiObject')then c:Destroy()end end
 local item=r.item and Catalog.Cosmetics[r.item]
 if item then
  local color=rarityColor(item.rarity)
  self.revealStroke.Color=color;self.revealRarity.TextColor3=color
  self.revealRarity.Text=UPPER[item.rarity]or UPPER.common
  self.revealName.Text=item.title
  if item.kind=='flag'then
   Flags.image(self.revealBox,item.id,70,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+26})
   self.revealKind.Text='Flag · next to your country\'s name'
  else
   Flags.swatch(self.revealBox,item.id,16,WATER,TINT,Z+26)
   self.revealKind.Text='Pattern · on your country\'s water'
  end
  self.revealNew.Visible=true
 else
  self.revealStroke.Color=C.silver;self.revealRarity.TextColor3=C.silver
  self.revealRarity.Text='ALL COLLECTED'
  self.revealName.Text='+'..compact(r.silver or Catalog.ChestSilver)..' silver'
  Icons.image(self.revealBox,'coins',64,C.silver,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+26})
  self.revealKind.Text='You have every flag and pattern from the chest'
  self.revealNew.Visible=false
 end
end

-- The show, one frame.
function K:stepShow(dt)
 local s=self.show;s.t+=dt
 local art=self.showArt;local size=art.size
 local result=s.result
 local rarity=result and result.item and Catalog.Cosmetics[result.item]and Catalog.Cosmetics[result.item].rarity or 'common'
 local color=result and(result.item and rarityColor(rarity)or C.silver)or C.amber
 if s.phase=='shake'then
  if s.failed then self:say(s.failed);Sfx.play('deny');self:endShow();return end
  if s.t>12 then self:say('The chest did not open. It is saved, try again.');self:endShow();return end
  local build=result and BUILD[rarity]or 0
  local amp=math.min(12,3+s.t*6)
  art.root.Rotation=math.sin(s.t*(result and 46 or 26))*amp*(result and 1 or .5)
  local k=result and math.clamp((s.t-s.hold)/math.max(.01,build),0,1)or 0
  for i,g in ipairs(art.glow)do
   g.BackgroundColor3=C.amber:Lerp(color,k)
   g.BackgroundTransparency=.88-k*(.3-i*.05)+math.sin(s.t*8+i)*.03
  end
  if result and s.t>=s.hold+build then
   s.phase='burst';s.t=0
   if result.item then self.showTitle.Text=(UPPER[rarity]or UPPER.common)..'!'else self.showTitle.Text='ALL COLLECTED'end
   self.showTitle.TextColor3=color
   Sfx.play(rarity=='legendary'and 'found'or 'build')
   self.flash.BackgroundTransparency=.15
   local n=({common=10,rare=14,epic=19,legendary=24})[rarity]or 10
   for i,p in ipairs(self.sparks)do
    p.Visible=i<=n;p.BackgroundColor3=i%3==0 and C.white or color
    local a=(i/n)*math.pi*2+math.random()*.4
    p:SetAttribute('dx',math.cos(a));p:SetAttribute('dy',math.sin(a));p:SetAttribute('v',140+math.random()*120)
    p.Position=UDim2.fromScale(.5,.5);p.BackgroundTransparency=0
   end
   self:fillReveal(result)
  end
 elseif s.phase=='burst'then
  art.root.Rotation=0
  local k=math.clamp(s.t/.45,0,1)
  art.lid.Position=UDim2.new(.5,-k*size*.25,0,size*.42-k*size*.55)
  art.lid.Rotation=-k*35;art.lid.BackgroundTransparency=k*.2
  self.flash.BackgroundTransparency=.15+k*.85
  for _,p in ipairs(self.sparks)do if p.Visible then
   local d=p:GetAttribute('v')*s.t
   p.Position=UDim2.new(.5,p:GetAttribute('dx')*d,.56,p:GetAttribute('dy')*d)
   p.BackgroundTransparency=k
  end end
  if s.t>=.45 then
   s.phase='card';s.t=0
   for _,p in ipairs(self.sparks)do p.Visible=false end
   art.root.Visible=false
   self.reveal.Visible=true;self.revealScale.Scale=.2
   TweenService:Create(self.revealScale,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
  end
 elseif s.phase=='card'then
  if s.t>=.35 and not self.choice.Visible then self.choice.Visible=true end
  -- (a slow shine on rare things)
  self.revealNew.Rotation=math.sin(s.t*3)*6
 end
 if self.choice.Visible then
  local item=result and result.item and Catalog.Cosmetics[result.item]
  local p=self.v.profile
  local wearing=item and p and p.equipped and p.equipped[item.kind]==item.id
  self.wearButton.Visible=item~=nil
  self.wearText.Text=wearing and 'WORN'or 'WEAR'
  self.wearButton.Active=not wearing and not self.busy
  local left=math.min(self:chests(),self:keys())
  self.nextText.Text=left>0 and('AGAIN ('..left..')')or 'AGAIN'
  self.nextButton.Visible=left>0
 end
end

function K:layout(size)
 local phone=size.X<900 or size.Y<520
 if self.lastSize==size and self.lastPhone==phone then return end
 self.lastSize=size;self.lastPhone=phone
 self.fit=math.clamp(math.min((size.X-24)/W,(size.Y-24)/H),.5,1.3);self.scale.Scale=self.fit
 self.card.Position=UDim2.fromScale(.5,.5)
end
function K:setOpen(open)
 open=open==true
 if open==self.open then return end
 self.open=open;self.shade.Visible=open;self.card.Visible=open
 if open then
  self.noteText=nil;self.lastSize=nil;self:layout(self.v.gui.AbsoluteSize)
  self.scale.Scale=(self.fit or 1)*.92;TweenService:Create(self.scale,Kit.POP,{Scale=self.fit or 1}):Play()
 else self:endShow();self:showOdds(false)end
end
-- Every frame from the lobby; nothing while closed.
function K:update(dt)
 if not self.open then return end
 self.clock+=dt
 self:layout(self.v.gui.AbsoluteSize)
 local p=self.v.profile
 local n=self:chests();local keys=self:keys()
 self.countText.Text=n>0 and(n..(n==1 and ' chest'or ' chests'))or 'No chests'
 self.keyText.Text=keys..(keys==1 and ' key'or ' keys')
 local owned=p and p.owned or {}
 local odds,left=Catalog.chestOdds(owned)
 for rarity,value in pairs(self.oddsRows)do
  local share=odds[rarity]or 0
  local percent=string.format(share<.1 and '%.1f' or '%.0f',share*100):gsub('%.0$','')
  value.Text=share>0 and (percent..'%') or 'all owned'
  value.TextColor3=share>0 and C.text or C.muted
 end
 local note=self.noteText and os.clock()<(self.noteUntil or 0)and self.noteText or nil
 self.note.Visible=note~=nil;self.left.Visible=note==nil
 if note then self.note.Text=note end
 local firstLeft=self:singleKey()=='chest_first'and Products.chestFirstLeft(p)or 0
 self.left.Text=firstLeft>0 and('First 2 keys for '..(Store.robux('chest_first')or 15)..' R$ each · '..firstLeft..' left')
  or left>0 and('Not collected yet: '..left)or 'You collected everything, chests now give silver'
 self.left.TextColor3=firstLeft>0 and C.amber or C.muted
 -- The open button and the idle chest.
 local ready=math.min(n,keys)
 self.openText.Text=ready>1 and('OPEN ('..ready..')')or ready==1 and 'OPEN'or n>0 and('BUY A KEY · '..Store.label(self:singleKey()))or 'WIN MATCHES FOR CHESTS'
 self.openText.TextSize=ready>0 and 18 or 15
 self.openButton.Active=n>0 and not self.busy
 self.openText.TextTransparency=n>0 and 0 or .45
 local wiggle=n>0 and math.max(0,math.sin(self.clock*2.2))^8 or 0
 self.art.root.Rotation=math.sin(self.clock*30)*wiggle*7
 self.art.root.Position=UDim2.new(.5,0,.5,math.sin(self.clock*1.6)*4)
 -- Offers: the price for Robux, or "Soon" while the product has no id.
 local single=Store.robux('chest_1')or 0
 for i,o in ipairs(self.offers)do
  local key=i==1 and self:singleKey()or o.key
  local first=key=='chest_first'
  local available=Store.available(key)
  local price=Store.robux(key)
  o.priceText.Text=self.restricted and 'Unavailable'or available and(price..' R$')or 'Soon'
  o.button.Active=available and not self.restricted and not self.busy and not self.show
  -- The first-price chest in gold, the rest in the window's own colours.
  o.button.BackgroundColor3=first and C.amber or C.tile
  o.stroke.Color=first and Color3.fromRGB(255,230,170)or C.robux;o.stroke.Transparency=first and .1 or .55
  tintKey(o.keyIcon,first and C.dark or GOLD)
  o.count.TextColor3=first and C.dark or C.text;o.sub.TextColor3=first and C.dark or C.muted
  o.price.BackgroundColor3=first and Color3.fromRGB(70,40,8)or C.card
  o.priceStroke.Color=first and C.amber or C.robux
  o.priceText.TextColor3=first and C.amber or(available and C.robux or C.muted)
  if i==1 then
   o.tag.Visible=first;o.tagText.Text='FIRST 2'
  else
   local count=Products.list[o.key].count or 1
   local save=single>0 and price and math.floor((1-price/(single*count))*100+.5)or 0
   o.tag.Visible=save>0;o.tagText.Text='−'..save..'%'
  end
 end
 if self.show then self:stepShow(dt)end
end
return K
