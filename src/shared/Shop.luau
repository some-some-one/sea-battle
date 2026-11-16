--!nonstrict
-- The shop: a window with tabs and a grid of cards (from the lobby, and from the match's own shop
-- button: the window lives beside the lobby, not in it, so it opens over a match too). A card shows the thing, its name and one
-- button that says what a tap does now: the price (a second tap confirms the purchase), "Wear" for a
-- thing owned, "Worn" for the one worn (a tap takes it off).
-- The client only names the item: prices and ownership are the server's (commands "buy" and "equip").
-- Tabs with nothing to show are hidden, so the shop grows as the catalog does.
-- The "Arsenal" tab is a list and one item at a time (2026-11-11, by the author's
-- request): the items on the left (each with what it takes: OPEN, or its silver price), the chosen one on
-- the right playing what it does in a match (ArsenalDemo), its name, what kind of thing it is, one plain
-- sentence, two facts, and the prices: silver (a second tap confirms) and Robux at once.
local Kit=require(script.Parent.Kit)
local Icons=require(script.Parent.Icons)
local Flags=require(script.Parent.Flags)
local Catalog=require(script.Parent.Catalog)
local Sfx=require(script.Parent.Sfx)
local Store=require(script.Parent.Store)
local Products=require(script.Parent.Products)
local ArsenalDemo=require(script.Parent.ArsenalDemo)
local compact=require(script.Parent.NumberFormat).compact
local C,make,corner,stroke,label,pressable=Kit.C,Kit.make,Kit.corner,Kit.stroke,Kit.label,Kit.pressable

local S={};S.__index=S
local Z=50
local TABS={{key='arsenal',title='Arsenal',icon='rocket'},{key='flag',title='Flags',icon='flag'},{key='pattern',title='Patterns',icon='pattern'},{key='boost',title='Boosts',icon='bolt'}}
-- Offers that are not catalog items (the "Boosts" tab): bought for Robux only.
local OFFERS={
 {id='silver2x',product='silver2x',icon='bolt',color=Color3.fromRGB(255,206,96),title='×2 Silver',sub='Forever: twice as much from every match'},
 {id='starter_pack',product='starter_pack',icon='gift',color=Color3.fromRGB(176,140,255),title='Starter Pack',
  sub='×2 silver, '..compact(Products.Starter.silver)..' silver, a flag, a pattern, torpedo and cluster missile'},
}
local WATER,TINT=Color3.fromRGB(58,120,150),Color3.fromRGB(110,170,196)
local REASONS={silver='Not enough silver',owned='Already bought',store='Could not save. Try again.',
 not_owned='Buy it first',no_reply='No answer from the server'}
local function rgb(t)return Color3.fromRGB(t[1],t[2],t[3])end
-- A silver price carries the coin at the button's left: the text then starts after it (on a narrow
-- phone button a centred price ran under the coin).
local function coinRoom(text,coin,on)
 coin.Visible=on
 local pos,size=on and UDim2.fromOffset(28,0)or UDim2.new(),on and UDim2.new(1,-36,1,0)or UDim2.fromScale(1,1)
 if text.Position~=pos then text.Position=pos;text.Size=size end
end

function S.new(lobby)
 local self=setmetatable({lobby=lobby,v=lobby.v,open=false,tab='arsenal',cards={},busy=false,clock=0},S)
 local w=Kit.window(lobby.root.Parent,'Shop',Z,700,470,function()self:show(false)end)
 self.shade,self.card,self.scale,self.close=w.shade,w.card,w.scale,w.close
 -- (beside the lobby the dim layer must reach under Roblox's top bar itself)
 local inset=game:GetService('GuiService'):GetGuiInset().Y
 self.shade.Position=UDim2.fromOffset(0,-inset);self.shade.Size=UDim2.new(1,0,1,inset)
 self.badge=Kit.badge(self.card,'shop',40,C.accent,UDim2.fromOffset(20,14))
 self.title=label(self.card,'SHOP',20,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(72,14),Size=UDim2.fromOffset(160,40)})
 -- The balance, left of the close button.
 self.wallet=corner(make('Frame',self.card,{Name='Wallet',AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-62,0,18),Size=UDim2.fromOffset(90,28),
  BackgroundColor3=C.ink,BackgroundTransparency=.25,ZIndex=Z+2}),14)
 stroke(self.wallet,C.silver,.55,1)
 Icons.image(self.wallet,'coins',16,C.silver,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,8,.5,0),ZIndex=Z+3})
 self.walletText=label(self.wallet,'',14,Enum.FontWeight.Heavy,C.silver,{Position=UDim2.fromOffset(29,0),Size=UDim2.new(1,-36,1,0)})
 -- Tabs.
 self.tabs={}
 for _,t in ipairs(TABS)do
  local b=pressable(self.card,{Name='Tab_'..t.key,BackgroundColor3=C.tile,Size=UDim2.fromOffset(120,34),ZIndex=Z+2},function()self.tab=t.key;self.confirm=nil;self.list.CanvasPosition=Vector2.zero end)
  corner(b,12)
  local text=label(b,t.title,14,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
  Icons.lead(text,t.icon,{size=16,gap=7})
  self.tabs[t.key]={button=b,stroke=stroke(b,C.white,.85,1),text=text}
 end
 self.list=make('ScrollingFrame',self.card,{Name='Items',BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=C.accent,
  ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ZIndex=Z+2})
 self.grid=make('UIGridLayout',self.list,{CellPadding=UDim2.fromOffset(12,12),SortOrder=Enum.SortOrder.LayoutOrder})
 make('UIPadding',self.list,{PaddingTop=UDim.new(0,3),PaddingLeft=UDim.new(0,3),PaddingRight=UDim.new(0,8),PaddingBottom=UDim.new(0,6)})
 self.note=label(self.card,'',13,Enum.FontWeight.Medium,C.amber,{TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+2})
 for order,id in ipairs(Catalog.CosmeticOrder)do self:addCard(Catalog.Cosmetics[id],order)end
 self:buildArsenal()
 for order,offer in ipairs(OFFERS)do self:addOffer(offer,order)end
 -- A purchase window closed: say so; the thing itself comes with the profile.
 Store.onFinished(function(_,purchased)if self.open and purchased then Sfx.play('build');self:say('Payment received, delivering…')end end)
 return self
end
-- The player's own country (an ISO code from Roblox): its flag leads the "Flags" tab.
local home,asked=nil,false
local function homeCountry()
 while asked==nil do task.wait()end
 if asked then return home end
 asked=nil
 local ok,code=pcall(function()
  return game:GetService('LocalizationService'):GetCountryRegionForPlayerAsync(game:GetService('Players').LocalPlayer)
 end)
 home=ok and type(code)=='string'and string.upper(code)or nil;asked=true
 return home
end
function S:addCard(item,order)
 local rarity=Catalog.Rarity[item.rarity]or Catalog.Rarity.common
 local frame=corner(make('Frame',self.list,{Name=item.id,BackgroundColor3=C.tile,LayoutOrder=order,ZIndex=Z+3}),14)
 local c={item=item,frame=frame,stroke=stroke(frame,rgb(rarity.color),.55,1),baseOrder=order}
 make('UIGradient',frame,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(185,190,200))})
 -- The thing itself: a flag, or a piece of water with the pattern on it.
 c.preview=corner(make('Frame',frame,{Name='Preview',AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,10),BackgroundColor3=C.ink,BackgroundTransparency=.35,ClipsDescendants=true,ZIndex=Z+4}),10)
 if item.kind=='flag'then
  c.flag=Flags.image(c.preview,item.id,40,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+5})
 else
  Flags.swatch(c.preview,item.id,16,WATER,TINT,Z+5);c.preview.BackgroundTransparency=0
 end
 c.title=label(frame,item.title,13,Enum.FontWeight.Bold,C.text,{TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+4})
 c.rarity=label(frame,rarity.title,10,Enum.FontWeight.Bold,rgb(rarity.color),{TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+4})
 c.button=pressable(frame,{Name='Action',BackgroundColor3=C.card,ZIndex=Z+4},function()self:act(c)end)
 corner(c.button,10);c.buttonStroke=stroke(c.button,C.white,.8,1)
 c.buttonText=label(c.button,'',13,Enum.FontWeight.Heavy,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 c.coin=Icons.image(c.button,'coins',14,C.silver,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,10,.5,0),ZIndex=Z+5,Visible=false})
 -- The same thing for Robux (shown only when its product exists and the thing is not owned).
 c.product='cos_'..item.id
 c.robux=pressable(frame,{Name='Robux',BackgroundColor3=C.card,ZIndex=Z+4,Visible=false},function()if not self.busy then Store.prompt(c.product)end end)
 corner(c.robux,10);stroke(c.robux,C.robux,.5,1)
 c.robuxText=label(c.robux,'',12,Enum.FontWeight.Heavy,C.robux,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 -- (country flags have a tab of their own; the player's own country comes first there)
 c.tab = item.kind
 if item.country then task.spawn(function()if homeCountry()==item.country then c.baseOrder=-1;c.rarity.Text='Your country'end end)end
 table.insert(self.cards,c)
 return c
end
-- The "Arsenal" tab: the list of items and the chosen one's page.
local ARSENAL_COLOR={weapon=Color3.fromRGB(255,120,96),building=Color3.fromRGB(86,170,255),action=Color3.fromRGB(126,222,152),boost=Color3.fromRGB(255,206,96)}
local KIND={weapon='Weapon',building='Building',action='Order',boost='Boost'}
function S:buildArsenal()
 self.pick=Catalog.ArsenalOrder[1]
 self.pane=make('Frame',self.card,{Name='Arsenal',BackgroundTransparency=1,Visible=false,ZIndex=Z+2})
 self.rowList=make('ScrollingFrame',self.pane,{Name='List',BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.accent,
  ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ZIndex=Z+2})
 make('UIListLayout',self.rowList,{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
 make('UIPadding',self.rowList,{PaddingTop=UDim.new(0,2),PaddingLeft=UDim.new(0,2),PaddingRight=UDim.new(0,6),PaddingBottom=UDim.new(0,4)})
 self.rows={}
 for order,key in ipairs(Catalog.ArsenalOrder)do
  local item=Catalog.Arsenal[key];local color=ARSENAL_COLOR[item.kind]or C.accent
  local row=pressable(self.rowList,{Name=key,BackgroundColor3=C.tile,LayoutOrder=order,Size=UDim2.new(1,0,0,48),ZIndex=Z+3},function()
   if self.pick~=key then self.pick=key;self.confirm=nil;Sfx.play('click')end
  end)
  corner(row,12)
  local r={row=row,item=item,stroke=stroke(row,C.white,.85,1),baseOrder=order}
  r.badge=Kit.badge(row,item.icon,34,color,UDim2.fromOffset(7,7))
  r.title=label(row,item.title,13,Enum.FontWeight.Bold,C.text,{Position=UDim2.fromOffset(48,6),Size=UDim2.new(1,-54,0,18),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+4})
  r.status=label(row,'',11,Enum.FontWeight.Bold,C.silver,{Position=UDim2.fromOffset(48,24),Size=UDim2.new(1,-54,0,16),ZIndex=Z+4})
  self.rows[key]=r
 end
 local d=corner(make('Frame',self.pane,{Name='Item',BackgroundColor3=C.tile,ZIndex=Z+3}),14)
 make('UIGradient',d,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(185,190,200))})
 self.detail=d
 self.demo=ArsenalDemo.new(d,self.pick,Z+4)
 self.dTitle=label(d,'',18,Enum.FontWeight.Heavy,C.text,{TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+4})
 self.dKind=label(d,'',11,Enum.FontWeight.Bold,C.accent,{TextXAlignment=Enum.TextXAlignment.Right,ZIndex=Z+4})
 self.dPlain=label(d,'',12,Enum.FontWeight.Medium,C.text,{TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=Z+4})
 self.dFacts={}
 for i=1,2 do self.dFacts[i]=label(d,'',11,Enum.FontWeight.Medium,C.muted,{TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+4})end
 self.dBuy=pressable(d,{Name='Silver',BackgroundColor3=C.card,ZIndex=Z+4},function()self:actArsenal(Catalog.Arsenal[self.pick])end)
 corner(self.dBuy,10);self.dBuyStroke=stroke(self.dBuy,C.silver,.6,1)
 self.dBuyText=label(self.dBuy,'',13,Enum.FontWeight.Heavy,C.silver,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 self.dCoin=Icons.image(self.dBuy,'coins',14,C.silver,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,10,.5,0),ZIndex=Z+5,Visible=false})
 self.dRobux=pressable(d,{Name='Robux',BackgroundColor3=C.robux,ZIndex=Z+4,Visible=false},function()
  local item=Catalog.Arsenal[self.pick];if item and not self.busy then Store.prompt(item.product)end
 end)
 corner(self.dRobux,10)
 self.dRobuxText=label(self.dRobux,'',13,Enum.FontWeight.Heavy,C.dark,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
end
-- Open the shop on a tab (and an arsenal item): the match's shop button.
function S:openOn(tab,key)
 if tab then self.tab=tab end
 if key and Catalog.Arsenal[key]then self.pick=key end
 self.confirm=nil
 self:show(true)
end
-- Open an arsenal item for silver: the price, then a second tap to confirm.
function S:actArsenal(item)
 local p=self.v.profile;if not p or self.busy or not item then return end
 if p.unlocks and p.unlocks[item.key]then return end
 if(p.silver or 0)<item.silver then Sfx.play('deny');self:say(REASONS.silver..': you need '..compact(item.silver-(p.silver or 0))..' more');return end
 if self.confirm~=item.key or os.clock()>(self.confirmUntil or 0)then self.confirm=item.key;self.confirmUntil=os.clock()+4;return end
 self.confirm=nil
 self:ask('buy',{id=item.key},function()Sfx.play('build');self:say('Unlocked forever: '..item.title..(self.lobby.mode=='menu'and''or'. Already in your match panel.'))end)
end
-- A card of the "Boosts" tab: an icon, what it gives, and its price in Robux.
function S:addOffer(offer,order)
 local frame=corner(make('Frame',self.list,{Name=offer.id,BackgroundColor3=C.tile,LayoutOrder=1000+order,ZIndex=Z+3}),14)
 local c={offer=offer,tab='boost',frame=frame,stroke=stroke(frame,offer.color,.5,1)}
 make('UIGradient',frame,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(185,190,200))})
 c.badge=Kit.badge(frame,offer.icon,48,offer.color,UDim2.new(.5,-24,0,12))
 c.title=label(frame,offer.title,13,Enum.FontWeight.Bold,C.text,{TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+4})
 c.rarity=label(frame,offer.sub,10,Enum.FontWeight.Medium,C.muted,{TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=Z+4})
 c.button=pressable(frame,{Name='Action',BackgroundColor3=C.card,ZIndex=Z+4},function()if not self.busy and not c.owned then Store.prompt(offer.product)end end)
 corner(c.button,10);c.buttonStroke=stroke(c.button,C.robux,.5,1)
 c.buttonText=label(c.button,'',13,Enum.FontWeight.Heavy,C.robux,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 table.insert(self.cards,c)
 return c
end
-- Whether an offer of the "Boosts" tab is shown now, and its button's text.
function S:offerState(c,p,now)
 local id=c.offer.id
 if id=='silver2x'then
  local owned=p and p.boosts and p.boosts.silver2x==true
  return owned or Store.available('silver2x'),owned,owned and 'Active'or Store.label('silver2x')
 elseif id=='starter_pack'then
  if not Store.available('starter_pack')or not Products.starterOpen(p,now)then return false end
  -- Its 48 hours start when it is first seen; the server keeps the time.
  if p and not p.starter and not self.starterAsked then
   self.starterAsked=true;task.spawn(function()self.v:request('starter_seen')end)
  end
  local left=p and p.starter and(p.starter.ends-now)
  return true,false,Store.label('starter_pack'),left and(Kit.countdown(left)..' left')or nil
 end
 return false
end
function S:say(text)self.noteText=text;self.noteUntil=os.clock()+4 end
-- A tap on a card's button: wear or take off what is owned; buy with a second tap what is not.
function S:act(c)
 local p=self.v.profile;if not p or self.busy then return end
 local item=c.item
 if p.owned and p.owned[item.id]then
  local wearing=p.equipped and p.equipped[item.kind]==item.id
  self:ask('equip',{slot=item.kind,id=not wearing and item.id or false})
  return
 end
 if not item.silver then return end
 if(p.silver or 0)<item.silver then Sfx.play('deny');self:say(REASONS.silver..': you need '..compact(item.silver-(p.silver or 0))..' more');return end
 if self.confirm~=item.id or os.clock()>(self.confirmUntil or 0)then self.confirm=item.id;self.confirmUntil=os.clock()+4;return end
 self.confirm=nil
 self:ask('buy',{id=item.id},function()Sfx.play('build');self:say('Bought: '..item.title)end)
end
function S:ask(action,value,done)
 self.busy=true
 task.spawn(function()
  local r=self.v:request(action,value)
  self.busy=false
  if r.ok then if done then done()end
  else Sfx.play('deny');self:say(REASONS[r.reason]or 'Not available')end
 end)
end
function S:layout(size)
 -- (its own measure of a phone: over a match the lobby does not lay itself out)
 local phone=size.X<900 or size.Y<520
 if self.lastSize==size and self.lastPhone==phone then return end
 self.lastSize=size;self.lastPhone=phone
 local W,H=phone and 580 or 700,phone and 330 or 490
 -- (cards are taller: the Robux price above the silver one)
 local cw,ch=phone and 122 or 150,phone and 170 or 190
 local top=phone and 52 or 64
 self.card.Size=UDim2.fromOffset(W,H)
 -- The header's row: on a phone the tabs take the title's place (there is no room for both), and the
 -- tabs, the balance and the close button share one centre line; on a computer the title, the balance
 -- and the close button do, the tabs are under them.
 local mid=phone and 28 or 34
 self.badge.Visible=not phone;self.title.Visible=not phone
 self.title.Position=UDim2.fromOffset(72,mid-20);self.title.TextSize=20
 self.wallet.Position=UDim2.new(1,-62,0,mid-14)
 self.close.Position=UDim2.new(1,-14,0,mid-18)
 local x=phone and 16 or 22
 local tw=phone and 86 or 116
 for _,t in ipairs(TABS)do
  local b=self.tabs[t.key].button
  b.Visible=self.tabShown==nil or self.tabShown[t.key]==true
  if b.Visible then b.Position=UDim2.fromOffset(x,phone and mid-17 or top);b.Size=UDim2.fromOffset(tw,34);x+=tw+(phone and 6 or 8)end
 end
 local listTop=phone and top or top+46
 self.list.Position=UDim2.fromOffset(20,listTop);self.list.Size=UDim2.fromOffset(W-32,H-listTop-30)
 self.note.Position=UDim2.fromOffset(20,H-28);self.note.Size=UDim2.fromOffset(W-40,20)
 self.grid.CellSize=UDim2.fromOffset(cw,ch)
 self.cellW,self.cellH=cw,ch
 -- The arsenal: the list on the left, the chosen item on the right.
 local pw,ph=W-40,H-listTop-30
 self.pane.Position=UDim2.fromOffset(20,listTop);self.pane.Size=UDim2.fromOffset(pw,ph)
 local lw=phone and 170 or 212;local rowH=phone and 40 or 48
 self.rowList.Size=UDim2.fromOffset(lw,ph)
 for _,r in pairs(self.rows)do
  r.row.Size=UDim2.new(1,0,0,rowH);local b=phone and 28 or 34
  r.badge.Size=UDim2.fromOffset(b,b);r.badge.Position=UDim2.fromOffset(6,math.floor((rowH-b)/2))
  r.title.Position=UDim2.fromOffset(b+12,phone and 3 or 6);r.title.TextSize=phone and 12 or 13
  r.status.Position=UDim2.fromOffset(b+12,phone and 20 or 24);r.status.Size=UDim2.new(1,-b-18,0,16)
 end
 local dx=lw+10;local dw,dh=pw-dx,ph
 self.detail.Position=UDim2.fromOffset(dx,0);self.detail.Size=UDim2.fromOffset(dw,dh)
 local demoH=phone and math.floor(dh*.33)or 128
 self.demo.frame.Position=UDim2.fromOffset(8,8);self.demo.frame.Size=UDim2.fromOffset(dw-16,demoH)
 local y=demoH+(phone and 12 or 16)
 self.dTitle.Position=UDim2.fromOffset(14,y);self.dTitle.Size=UDim2.fromOffset(dw-120,22);self.dTitle.TextSize=phone and 15 or 18
 self.dKind.Position=UDim2.fromOffset(dw-114,y);self.dKind.Size=UDim2.fromOffset(100,22)
 y+=phone and 22 or 26
 self.dPlain.Position=UDim2.fromOffset(14,y);self.dPlain.Size=UDim2.fromOffset(dw-28,phone and 30 or 34);self.dPlain.TextSize=phone and 11 or 12
 y+=phone and 30 or 36
 for i,f in ipairs(self.dFacts)do
  f.Visible=not phone;f.Position=UDim2.fromOffset(14,y+(i-1)*17);f.Size=UDim2.fromOffset(dw-28,16)
 end
 local bh=phone and 30 or 34
 -- (two rows of buttons: Robux above, silver below)
 self.dButtonsY=dh-bh-10;self.dButtonH=bh;self.dWidth=dw
 for _,c in ipairs(self.cards)do
  local ph=phone and 52 or 64
  if c.preview then c.preview.Size=UDim2.fromOffset(c.item.kind=='flag'and cw-20 or ph,ph)end
  c.title.Position=UDim2.fromOffset(6,ph+14);c.title.Size=UDim2.new(1,-12,0,18)
  c.rarity.Position=UDim2.fromOffset(6,ph+31);c.rarity.Size=UDim2.new(1,-12,0,c.offer and 30 or 14)
  c.button.Position=UDim2.fromOffset(10,ch-38);c.button.Size=UDim2.fromOffset(cw-20,28)
  if c.flag then local fh=phone and 32 or 40;c.flag.Size=UDim2.fromOffset(math.floor(fh*Flags.Aspect),fh)end
 end
 self.fit=math.clamp(math.min((size.X-24)/W,(size.Y-24)/H),.5,1.3);self.scale.Scale=self.fit
 -- (centred in the interface itself: beside the lobby it already starts under Roblox's top bar)
 self.card.Position=UDim2.fromScale(.5,.5)
end
function S:show(open)
 open=open==true
 if open==self.open then return end
 self.open=open;self.shade.Visible=open;self.card.Visible=open
 if open then
  self.noteText=nil;self.lastSize=nil;self:layout(self.v.gui.AbsoluteSize)
  self.scale.Scale=(self.fit or 1)*.92;game:GetService('TweenService'):Create(self.scale,Kit.POP,{Scale=self.fit or 1}):Play()
 end
end
-- The arsenal tab this frame: the rows' status, the chosen item's page and its buttons.
function S:updateArsenal(p,unlocks,silver)
 for key,r in pairs(self.rows)do
  local on=key==self.pick;local has=unlocks[key]==true
  -- (what is opened stands at the top of the list, 2026-11-16, by the author's request)
  local order=(has and -1000 or 0)+r.baseOrder
  if r.row.LayoutOrder~=order then r.row.LayoutOrder=order end
  r.row.BackgroundColor3=on and C.tileOn or C.tile
  r.stroke.Color=on and C.accent or C.white;r.stroke.Transparency=on and 0 or .85;r.stroke.Thickness=on and 2 or 1
  local status=has and 'Unlocked'or('Silver '..compact(r.item.silver))
  if r.status.Text~=status then r.status.Text=status end
  r.status.TextColor3=has and C.accent or(silver>=r.item.silver and C.silver or C.muted)
 end
 local item=Catalog.Arsenal[self.pick];if not item then return end
 self.demo:show(item.key);self.demo:step(self.clock)
 self.dTitle.Text=item.title;self.dKind.Text=(KIND[item.kind]or'')..' · forever'
 self.dKind.TextColor3=ARSENAL_COLOR[item.kind]or C.accent
 self.dPlain.Text=item.plain
 for i,f in ipairs(self.dFacts)do f.Text=item.facts[i]and('•  '..item.facts[i])or''end
 local has=unlocks[item.key]==true
 local forRobux=not has and Store.available(item.product)
 local dw=self.dWidth or 400;local full=dw-28;local y,bh=self.dButtonsY or 280,self.dButtonH or 36
 self.dBuy.Position=UDim2.fromOffset(14,y);self.dBuy.Size=UDim2.fromOffset(full,bh)
 self.dRobux.Visible=forRobux==true
 if forRobux then
  self.dRobux.Position=UDim2.fromOffset(14,y-bh-6);self.dRobux.Size=UDim2.fromOffset(full,bh)
  self.dRobuxText.Text='Buy now · '..Store.label(item.product);self.dRobux.Active=not self.busy
 end
 local confirm=self.confirm==item.key
 local text=has and 'Unlocked forever'or confirm and 'Unlock?'or(silver>=item.silver and('Unlock for '..compact(item.silver))or(compact(silver)..' of '..compact(item.silver)))
 if self.dBuyText.Text~=text then self.dBuyText.Text=text end
 coinRoom(self.dBuyText,self.dCoin,not has and not confirm)
 self.dBuy.BackgroundColor3=has and C.accent or confirm and C.amber or C.card
 self.dBuyText.TextColor3=has and C.ink or confirm and C.dark or(silver>=item.silver and C.silver or C.muted)
 self.dBuyStroke.Color=has and C.accent or confirm and C.amber or C.silver
 self.dBuy.Active=not self.busy and not has
end
-- Every frame (the lobby calls it over a match too); does nothing while the window is closed.
function S:update(dt)
 if not self.open then return end
 self.clock+=dt
 self:layout(self.v.gui.AbsoluteSize)
 local p=self.v.profile
 local owned=p and p.owned or {};local equipped=p and p.equipped or {};local silver=p and p.silver or 0
 self.walletText.Text=p and compact(silver)or '…'
 for key,t in pairs(self.tabs)do
  local on=key==self.tab
  t.button.BackgroundColor3=on and C.tileOn or C.tile
  t.stroke.Color=on and C.accent or C.white;t.stroke.Transparency=on and 0 or .85;t.stroke.Thickness=on and 2 or 1
 end
 if self.confirm and os.clock()>(self.confirmUntil or 0)then self.confirm=nil end
 local now=workspace:GetServerTimeNow()
 local tabShown={arsenal=true}
 local unlocks=p and p.unlocks or {}
 local cell=UDim2.fromOffset(self.cellW or 150,self.cellH or 166)
 if self.grid.CellSize~=cell then self.grid.CellSize=cell end
 local arsenal=self.tab=='arsenal'
 self.pane.Visible=arsenal;self.list.Visible=not arsenal
 if arsenal then self.seenArsenal=true;self:updateArsenal(p,unlocks,silver)end
 for _,c in ipairs(self.cards)do
  if c.offer then
   -- An offer for Robux: shown while it can be bought (or is already owned).
   local shown,has,text,note=self:offerState(c,p,now)
   if shown then tabShown.boost=true end
   local show=shown==true and self.tab=='boost'
   if c.frame.Visible~=show then c.frame.Visible=show end
   if show then
    c.owned=has==true
    c.buttonText.Text=text or '';c.buttonText.TextColor3=has and C.ink or C.robux
    c.button.BackgroundColor3=has and C.accent or C.card;c.buttonStroke.Color=has and C.accent or C.robux
    c.button.Active=not self.busy and not has
    local sub=note and(c.offer.sub..'\n'..note)or c.offer.sub
    if c.rarity.Text~=sub then c.rarity.Text=sub end
   end
   continue
  end
  local item=c.item
  -- (what the player owns — bought, from a chest or a reward — stands at the top of its tab, in catalog
  -- order; 2026-11-16, by the author's request)
  local order=(owned[item.id]and -100000 or 0)+(c.baseOrder or 0)
  if c.frame.LayoutOrder~=order then c.frame.LayoutOrder=order end
  local forRobux=not owned[item.id]and Store.available(c.product)
  local buyable=owned[item.id]or item.silver~=nil or forRobux
  if buyable then tabShown[c.tab]=true end
  local show=c.tab==self.tab and buyable
  if c.frame.Visible~=show then c.frame.Visible=show end
  if show then
   -- (one under the other, full width: Robux above, silver below; one alone sits at the bottom)
   local cw=self.cellW or 150;local ch=self.cellH or 190;local full=cw-20
   c.robux.Visible=forRobux==true
   c.button.Visible=owned[item.id]or item.silver~=nil
   c.button.Size=UDim2.fromOffset(full,28)
   if forRobux then
    c.robux.Size=UDim2.fromOffset(full,28);c.robux.Position=UDim2.fromOffset(10,c.button.Visible and ch-70 or ch-38)
    c.robuxText.Text=Store.label(c.product);c.robux.Active=not self.busy
   end
  end
  if show and c.button.Visible then
   local text,bg,fg,line
   if owned[item.id]then
    if equipped[item.kind]==item.id then text,bg,fg,line='Worn',C.accent,C.ink,C.accent
    else text,bg,fg,line='Wear',C.card,C.text,C.white end
   elseif self.confirm==item.id then text,bg,fg,line='Buy?',C.amber,C.dark,C.amber
   else text,bg,fg,line=compact(item.silver),C.card,silver>=item.silver and C.silver or C.muted,C.silver end
   if c.buttonText.Text~=text then c.buttonText.Text=text end
   -- (a price carries the coin at the button's left end)
   coinRoom(c.buttonText,c.coin,not owned[item.id]and self.confirm~=item.id)
   c.button.BackgroundColor3=bg;c.buttonText.TextColor3=fg;c.buttonStroke.Color=line
   c.button.Active=not self.busy
  end
 end
 -- Tabs with nothing in them are hidden; a hidden tab is never the one shown.
 local changed=false
 for _,t in ipairs(TABS)do if(self.tabShown and self.tabShown[t.key]or false)~=(tabShown[t.key]or false)then changed=true end end
 if changed or not self.tabShown then self.tabShown=tabShown;self.lastSize=nil end
 if not tabShown[self.tab]then for _,t in ipairs(TABS)do if tabShown[t.key]then self.tab=t.key;break end end end
 local note=self.noteText and os.clock()<(self.noteUntil or 0)and self.noteText or ''
 if self.note.Text~=note then self.note.Text=note end
end
return S
