--!nonstrict
-- Lobby over the map, a title screen: a wordmark and one card with two choices.
--  * Solo — the bots' difficulty, then "Battle": the player's own match runs on this device
--    (shared/LocalMatch), so a server holds any number of solo players.
--  * Online — a search across all servers (server/Matchmaker): when enough people wait, or the first has
--    waited R.QueueWait seconds, everyone found is teleported to a fresh server and the match starts
--    there for all at once. On that match server the lobby opens straight on the start banner.
-- Every match has the same rules (free for all, 65% of the water wins). Behind the menu the map shows
-- the lobby's demo match (LocalMatch "demo"); `source()` tells the view what to show. One layout per
-- screen shape, scaled to fit, so a phone, a tablet and a computer all see the whole card. A phone gets
-- the logo at the top and the menu as one slim strip at the bottom, so the demo match shows between.
local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local Sfx=require(script.Parent.Sfx)
local Logo=require(script.Parent.Logo)
local R=require(script.Parent.NavalRules)
local compact=require(script.Parent.NumberFormat).compact
local DailyCard=require(script.Parent.DailyCard)
local Shop=require(script.Parent.Shop)
local Chest=require(script.Parent.Chest)
local PartyPanel=require(script.Parent.PartyPanel)
local Tutorial=require(script.Parent.Tutorial)
local StarterOffer=require(script.Parent.StarterOffer)
local Economy=require(script.Parent.Economy)
local Store=require(script.Parent.Store)
-- Camera zoom after the start (1 = whole world; Home flies to .3): close over the new country.
local START_ZOOM=.12

local L={};L.__index=L
local C={ink=Color3.fromRGB(9,18,27),card=Color3.fromRGB(20,34,45),tile=Color3.fromRGB(27,45,58),
 tileOn=Color3.fromRGB(24,70,70),accent=Theme.colors.accent,text=Theme.colors.text,muted=Theme.colors.muted,
 amber=Color3.fromRGB(255,206,96),amberDeep=Color3.fromRGB(255,140,58),white=Color3.new(1,1,1)}
local SILVER=Color3.fromRGB(205,216,226)
local QUICK=TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local POP=TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out)

local LEVELS={{'easy','fish','Easy','Peaceful neighbors','Bots grow slowly and hold off attacking for a long time.'},
 {'normal','anchor','Normal','Fair fight','A short truce, then war for real.'},
 {'hard','fin','Hard','No mercy','Bots grow fast and attack early.'}}
local W,PAD=380,20

local function make(class,parent,props)
 local o=Instance.new(class)
 for k,v in pairs(props or {})do o[k]=v end
 if o:IsA('GuiObject')then o:SetAttribute('NoSkin',true)end
 o.Parent=parent;return o
end
local function corner(o,r)make('UICorner',o,{CornerRadius=UDim.new(0,r)});return o end
local function stroke(o,color,t,th)return make('UIStroke',o,{Color=color,Transparency=t or 0,Thickness=th or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
local function label(parent,text,size,weight,color,props)
 local o=make('TextLabel',parent,{BackgroundTransparency=1,Text=text,TextSize=size,FontFace=Theme.font(weight),TextColor3=color or C.text,
  TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,ZIndex=42})
 for k,v in pairs(props or {})do o[k]=v end
 return o
end
-- A pressable surface: grows a little under the pointer and dips when pressed.
local function pressable(parent,props,onClick)
 local b=make('TextButton',parent,{Text='',AutoButtonColor=false,BorderSizePixel=0,ZIndex=41})
 for k,v in pairs(props or {})do b[k]=v end
 local scale=make('UIScale',b,{Scale=1})
 local function to(v)TweenService:Create(scale,QUICK,{Scale=v}):Play()end
 b.MouseEnter:Connect(function()if b.Active then to(1.035)end end)
 b.MouseLeave:Connect(function()to(1)end)
 b.MouseButton1Down:Connect(function()if b.Active then to(.96)end end)
 b.MouseButton1Up:Connect(function()to(1)end)
 b.Activated:Connect(function()if b.Active then onClick()end end)
 return b
end
-- A round badge with one of the game's icons, lit from above.
local function badge(parent,icon,size,color,pos)
 local d=corner(make('Frame',parent,{Size=UDim2.fromOffset(size,size),Position=pos,BackgroundColor3=color:Lerp(C.ink,.55),ZIndex=42}),size)
 make('UIStroke',d,{Color=color,Thickness=2,Transparency=.05})
 make('UIGradient',d,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(170,170,170))})
 Icons.image(d,icon,math.floor(size*.56),C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=43})
 return d
end

-- The silver balance: a coin and the amount in a small pill.
local function wallet(parent,z)
 local pill=corner(make('Frame',parent,{Name='Wallet',AnchorPoint=Vector2.new(1,0),Size=UDim2.fromOffset(70,28),BackgroundColor3=C.ink,BackgroundTransparency=.25,ZIndex=z}),14)
 stroke(pill,SILVER,.55,1)
 Icons.image(pill,'coins',16,SILVER,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,8,.5,0),ZIndex=z+1})
 local text=label(pill,'…',14,Enum.FontWeight.Heavy,SILVER,{Name='Amount',Position=UDim2.fromOffset(29,0),Size=UDim2.new(1,-38,1,0),ZIndex=z+1})
 return {pill=pill,text=text,width=70}
end

local FOOTER='© OpenFront and Contributors  •  Music: APM Music  •  GNU AGPL v3, no warranty: see How to play'
local FOOTER_SHORT='© OpenFront and Contributors • Music: APM Music • AGPL v3, no warranty: see Help'
function L.new(view)
 local self=setmetatable({v=view,mode='menu',page='home',clock=0,shownPhase=nil,difficulty=nil},L)
 local gui=view.gui
 self.root=make('Frame',gui,{Name='Lobby',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Active=true,ZIndex=40})
 -- Darker behind the wordmark and the card; the demo match stays visible in between.
 local shade=make('Frame',self.root,{Size=UDim2.fromScale(1,1),BackgroundColor3=C.ink,BackgroundTransparency=.22,ZIndex=40})
 self.shadeGradient=make('UIGradient',shade,{Rotation=0,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.3,.12),NumberSequenceKeypoint.new(.5,.55),NumberSequenceKeypoint.new(.7,.3),NumberSequenceKeypoint.new(1,.05)})})

 -- Wordmark.
 self.word=make('Frame',self.root,{BackgroundTransparency=1,Size=UDim2.fromOffset(420,120),ZIndex=41})
 self.wordScale=make('UIScale',self.word,{Scale=1})
 self.title=label(self.word,'SEA BATTLE',58,Enum.FontWeight.Heavy,C.white,{Size=UDim2.new(1,0,0,70),TextXAlignment=Enum.TextXAlignment.Center})
 make('UIGradient',self.title,{Rotation=90,Color=ColorSequence.new(C.white,Color3.fromRGB(255,214,150))})
 make('UIStroke',self.title,{Color=Color3.fromRGB(4,10,20),Thickness=3,Transparency=.2})
 self.tag=label(self.word,'CONQUER THE WORLD OCEAN',15,Enum.FontWeight.Bold,C.accent,{Position=UDim2.fromOffset(0,74),Size=UDim2.new(1,0,0,24),TextXAlignment=Enum.TextXAlignment.Center})

 Icons.lead(self.tag,'waves',{size=18,gap=8})
 -- The logo (Logo: built on the device) in place of the text title; the text stays as the fallback.
 local logo=Logo.content()
 self.hasLogo=logo~=nil
 if logo then
  self.word.Size=UDim2.fromOffset(420,math.floor(420*Logo.height/Logo.width+.5))
  make('ImageLabel',self.word,{Name='Logo',BackgroundTransparency=1,ImageContent=logo,ScaleType=Enum.ScaleType.Fit,Size=UDim2.fromScale(1,1),ZIndex=42})
  self.title.Visible=false;self.tag.Visible=false
 end
 -- Footer (2026-11-15, by the author's request): the AGPL notice, quiet and half-transparent at the bottom;
 -- the full credits and licence are on the last card of "How to play".
 self.footer=label(self.root,FOOTER,12,Enum.FontWeight.Medium,C.muted,
  {Name='Footer',AnchorPoint=Vector2.new(.5,1),TextXAlignment=Enum.TextXAlignment.Center,TextTransparency=.45,TextWrapped=false,TextScaled=true,ZIndex=41})
 make('UITextSizeConstraint',self.footer,{MaxTextSize=12,MinTextSize=7})
 -- The card, with two pages: home (Solo / Online) and solo (difficulty and start).
 self.card=corner(make('Frame',self.root,{BackgroundColor3=C.card,BackgroundTransparency=.04,ZIndex=41}),18)
 stroke(self.card,C.white,.86,1)
 make('UIGradient',self.card,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(200,210,220))})
 self.scale=make('UIScale',self.card,{Scale=1})
 self.note=label(self.card,'',12,Enum.FontWeight.Medium,C.amber,{TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true})

 -- Silver (the account's one currency), top right of the card on both pages.
 self.wallet=wallet(self.card,43);self.wallet.pill.Position=UDim2.fromOffset(W-PAD,13)
 -- Home page.
 self.home=make('Frame',self.card,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=41})
 label(self.home,'NEW MATCH',13,Enum.FontWeight.Heavy,C.muted,{Position=UDim2.fromOffset(PAD,16),Size=UDim2.fromOffset(200,22)})
 local tileW=(W-PAD*2-12)/2
 local function bigTile(x,icon,color,title,onClick)
  local t=pressable(self.home,{Position=UDim2.fromOffset(x,50),Size=UDim2.fromOffset(tileW,156),BackgroundColor3=color:Lerp(C.tile,.7)},onClick)
  corner(t,16);stroke(t,color,.45,1.5)
  make('UIGradient',t,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(150,150,150))})
  badge(t,icon,58,color,UDim2.new(.5,-29,0,16))
  label(t,title,21,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(0,82),Size=UDim2.new(1,0,0,26),TextXAlignment=Enum.TextXAlignment.Center})
  local sub=label(t,'',12,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(10,110),Size=UDim2.new(1,-20,0,34),TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true})
  return t,sub
 end
 self.soloTile,self.soloSub=bigTile(PAD,'target',Color3.fromRGB(255,120,96),'Solo',function()self:choose('solo')end)
 self.onlineTile,self.onlineSub=bigTile(PAD+tileW+12,'globe',Color3.fromRGB(86,156,255),'Online',function()self:choose('online')end)
 -- "Searching" pill on the online tile while this player is in the online queue.
 self.live=corner(make('Frame',self.onlineTile,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-8,0,8),Size=UDim2.fromOffset(62,20),BackgroundColor3=Color3.fromRGB(214,52,64),Visible=false,ZIndex=43}),10)
 label(self.live,'● SEARCHING',10,Enum.FontWeight.Heavy,C.white,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=44})
 -- Watching someone else's match.
 self.watch=pressable(self.home,{BackgroundColor3=C.tileOn,Position=UDim2.fromOffset(PAD,218),Size=UDim2.fromOffset(W-PAD*2,46),Visible=false},function()self.playing='watch';self:open('hidden')end)
 corner(self.watch,12);stroke(self.watch,C.accent,.3,1.5)
 self.watchText=label(self.watch,'Watch the match',15,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 Icons.lead(self.watchText,'eye',{size=18,gap=8})
 self.helpButton=pressable(self.home,{BackgroundColor3=C.tile},function()gui:SetAttribute('HelpRequest',(gui:GetAttribute('HelpRequest')or 0)+1)end)
 corner(self.helpButton,12);stroke(self.helpButton,C.white,.85,1)
 Icons.lead(label(self.helpButton,'How to play',14,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center}),'help',{size=16,gap=8,color=C.amber})

 -- The shop (cosmetics now; the arsenal and boosts as they come).
 self.shopButton=pressable(self.home,{BackgroundColor3=C.tile},function()self.shop:show(true)end)
 corner(self.shopButton,12);stroke(self.shopButton,C.accent,.5,1)
 Icons.lead(label(self.shopButton,'Shop',14,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center}),'shop',{size=16,gap=8,color=C.accent})
 -- The chest (a random flag or pattern), between the shop and the daily reward; a count of chests waiting.
 self.chestButton=pressable(self.home,{BackgroundColor3=C.tile},function()self.chest:setOpen(true)end)
 corner(self.chestButton,12);stroke(self.chestButton,C.amber,.6,1)
 Icons.lead(label(self.chestButton,'Chest',14,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center}),'chest',{size=16,gap=8,color=C.amber})
 local function countBadge(parent)
  local b=corner(make('Frame',parent,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,6,0,-6),Size=UDim2.fromOffset(20,20),BackgroundColor3=Color3.fromRGB(240,70,70),Visible=false,ZIndex=44}),10)
  local t=label(b,'',11,Enum.FontWeight.Heavy,C.white,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=45})
  return {frame=b,text=t}
 end
 self.chestBadge=countBadge(self.chestButton)
 -- The daily reward: a button beside the shop's, with a red dot while today's reward waits.
 self.dailyButton=pressable(self.home,{BackgroundColor3=C.tile},function()self.daily:show(true)end)
 corner(self.dailyButton,12);stroke(self.dailyButton,C.amber,.6,1)
 Icons.lead(label(self.dailyButton,'Reward',14,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center}),'gift',{size=16,gap=8,color=C.amber})
 self.dailyDot=corner(make('Frame',self.dailyButton,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-6,0,6),Size=UDim2.fromOffset(10,10),BackgroundColor3=Color3.fromRGB(240,70,70),Visible=false,ZIndex=43}),5)
 -- Solo page.
 self.solo=make('Frame',self.card,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=41})
 local back=pressable(self.solo,{BackgroundColor3=C.tile,Position=UDim2.fromOffset(PAD,14),Size=UDim2.fromOffset(38,38)},function()self:setPage('home')end)
 corner(back,12);stroke(back,C.white,.85,1)
 label(back,'←',20,Enum.FontWeight.Heavy,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 Icons.lead(label(self.solo,'SOLO',20,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(PAD+52,14),Size=UDim2.fromOffset(200,38)}),'target',{size=22,gap=8,color=Color3.fromRGB(255,120,96)})
 label(self.solo,'BOT DIFFICULTY',11,Enum.FontWeight.Bold,C.muted,{Position=UDim2.fromOffset(PAD,66),Size=UDim2.fromOffset(200,16)})
 self.diffTiles={}
 local w3=(W-PAD*2-16)/3
 for i,d in ipairs(LEVELS)do
  local t=pressable(self.solo,{Position=UDim2.fromOffset(PAD+(i-1)*(w3+8),86),Size=UDim2.fromOffset(w3,104)},function()self.difficulty=d[1]end)
  corner(t,14);stroke(t,C.white,.85,1)
  Icons.image(t,d[2],34,C.white,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,12),ZIndex=42})
  label(t,d[3],15,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(0,52),Size=UDim2.new(1,0,0,20),TextXAlignment=Enum.TextXAlignment.Center})
  label(t,d[4],11,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(0,74),Size=UDim2.new(1,0,0,16),TextXAlignment=Enum.TextXAlignment.Center})
  self.diffTiles[d[1]]=t
 end
 self.diffText=label(self.solo,'',12,Enum.FontWeight.Regular,C.muted,{Position=UDim2.fromOffset(PAD,198),Size=UDim2.fromOffset(W-PAD*2,18),TextXAlignment=Enum.TextXAlignment.Center})
 self.play=pressable(self.solo,{BackgroundColor3=C.white,Position=UDim2.fromOffset(PAD,228),Size=UDim2.fromOffset(W-PAD*2,60)},function()self:startSolo()end)
 corner(self.play,16)
 self.playGradient=make('UIGradient',self.play,{Rotation=90,Color=ColorSequence.new(C.amber,C.amberDeep)})
 make('UIStroke',self.play,{Color=Color3.fromRGB(255,230,170),Transparency=.35,Thickness=1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 Icons.lead(label(self.play,'BATTLE',22,Enum.FontWeight.Heavy,Color3.fromRGB(40,20,6),{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center}),'anchor',{size=24,gap=10})

 -- Phone: the same choices as one slim strip at the bottom (the card is hidden there).
 self.strip=corner(make('Frame',self.root,{Name='MenuStrip',AnchorPoint=Vector2.new(.5,1),BackgroundColor3=C.card,BackgroundTransparency=.06,Visible=false,ZIndex=41}),16)
 stroke(self.strip,C.white,.86,1)
 make('UIGradient',self.strip,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(200,210,220))})
 self.stripScale=make('UIScale',self.strip,{Scale=1})
 self.stripWallet=wallet(self.root,42);self.stripWallet.pill.AnchorPoint=Vector2.new(1,1);self.stripWallet.pill.Visible=false
 self.stripNote=label(self.root,'',12,Enum.FontWeight.Medium,C.amber,{AnchorPoint=Vector2.new(.5,1),TextXAlignment=Enum.TextXAlignment.Center,
  TextWrapped=true,Visible=false})
 make('UIStroke',self.stripNote,{Color=Color3.fromRGB(4,10,20),Thickness=2,Transparency=.3})
 -- A strip button: an icon and a short title (the title hides when the button is too narrow for it).
 local function stripButton(name,icon,title,color,onClick)
  local b=pressable(self.strip,{Name=name,BackgroundColor3=color:Lerp(C.tile,.62)},onClick)
  corner(b,12);stroke(b,color,.45,1.5)
  local r={button=b,color=color}
  r.icon=Icons.image(b,icon,22,C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=42})
  -- (the title carries its own icon before the text, the pair centred; the lone icon is for a narrow button)
  r.title=title and label(b,title,15,Enum.FontWeight.Heavy,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=42})
  if r.title then Icons.lead(r.title,icon,{size=22,gap=8,color=C.white})end
  return r
 end
 self.sSolo=stripButton('StripSolo','target','Solo',Color3.fromRGB(255,120,96),function()self:choose('solo')end)
 self.sOnline=stripButton('StripOnline','globe','Online',Color3.fromRGB(86,156,255),function()self:choose('online')end)
 self.sWatch=stripButton('StripWatch','eye','Watch',C.accent,function()self.playing='watch';self:open('hidden')end)
 self.sHelp=stripButton('StripHelp','help',nil,Color3.fromRGB(150,170,185),function()gui:SetAttribute('HelpRequest',(gui:GetAttribute('HelpRequest')or 0)+1)end)
 self.sShop=stripButton('StripShop','shop',nil,C.accent,function()self.shop:show(true)end)
 self.sChest=stripButton('StripChest','chest',nil,C.amber,function()self.chest:setOpen(true)end)
 self.sChestBadge=countBadge(self.sChest.button)
 self.sDaily=stripButton('StripDaily','gift',nil,C.amber,function()self.daily:show(true)end)
 self.sDailyDot=corner(make('Frame',self.sDaily.button,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-5,0,5),Size=UDim2.fromOffset(10,10),BackgroundColor3=Color3.fromRGB(240,70,70),Visible=false,ZIndex=43}),5)
 self.sBack=stripButton('StripBack','home',nil,Color3.fromRGB(150,170,185),function()self:setPage('home')end)
 self.sDiff={}
 for _,d in ipairs(LEVELS)do self.sDiff[d[1]]=stripButton('Strip'..d[1],d[2],d[3],C.white,function()self.difficulty=d[1]end)end
 self.sPlay=stripButton('StripPlay','anchor','BATTLE',C.amber,function()self:startSolo()end)
 self.sPlay.button.BackgroundColor3=C.white
 make('UIGradient',self.sPlay.button,{Rotation=90,Color=ColorSequence.new(C.amber,C.amberDeep)})
 self.sPlay.title.TextColor3=Color3.fromRGB(40,20,6);self.sPlay.icon.ImageColor3=Color3.fromRGB(40,20,6)
 self.sPlay.title.LeadIcon.ImageColor3=Color3.fromRGB(40,20,6)

 -- Start picking: a slim banner at the top.
 self.banner=corner(make('Frame',gui,{Name='SpawnBanner',AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,12),BackgroundColor3=C.card,BackgroundTransparency=.04,Visible=false,ZIndex=40}),16)
 stroke(self.banner,C.accent,.4,1.5)
 self.bannerScale=make('UIScale',self.banner,{Scale=1})
 self.pin=badge(self.banner,'pin',38,Color3.fromRGB(255,120,96),UDim2.fromOffset(12,11))
 self.bannerTitle=label(self.banner,'PICK YOUR START',16,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(60,10),Size=UDim2.fromOffset(220,22)})
 self.bannerText=label(self.banner,'Tap a free coast',12,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(60,32),Size=UDim2.fromOffset(220,18)})
 self.random=pressable(self.banner,{BackgroundColor3=C.tileOn,Size=UDim2.fromOffset(118,40),Position=UDim2.fromOffset(290,10)},function()self.v:send('start','random')end)
 corner(self.random,12);stroke(self.random,C.accent,.3,1)
 Icons.lead(label(self.random,'Random',14,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center}),'dice',{size=16,gap=7})
 self.back=pressable(self.banner,{BackgroundColor3=C.tile,Size=UDim2.fromOffset(40,40),Position=UDim2.fromOffset(414,10)},function()self:backToLobby()end)
 corner(self.back,12);stroke(self.back,C.white,.85,1)
 Icons.image(self.back,'home',20,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=42})
 self.banner.Size=UDim2.fromOffset(466,60)

 -- While watching someone else's match: a way back to the lobby.
 self.homeButton=pressable(gui,{Name='LobbyButton',BackgroundColor3=C.card,AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,12),Size=UDim2.fromOffset(150,40),Visible=false,ZIndex=40},function()self:open('menu')end)
 corner(self.homeButton,12);stroke(self.homeButton,C.white,.8,1)
 Icons.lead(label(self.homeButton,'Lobby',14,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center}),'home',{size=16,gap=8})
 -- The end of your match: the screen dims and one card says you won or lost (your country gone while
 -- the match goes on, or the match over), where you placed, and offers the lobby or another match; with no
 -- choice in END_SECONDS the lobby comes back on its own (L:updateEnd).
 self.endShade=make('TextButton',gui,{Name='EndShade',Text='',AutoButtonColor=false,BackgroundColor3=C.ink,BackgroundTransparency=.4,
  BorderSizePixel=0,Size=UDim2.new(1,0,1,80),Position=UDim2.fromOffset(0,-80),Visible=false,ZIndex=44})
 self.endCard=corner(make('Frame',gui,{Name='EndCard',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.48),
  Size=UDim2.fromOffset(380,292),BackgroundColor3=C.card,BackgroundTransparency=.02,Visible=false,Active=true,ZIndex=45}),20)
 self.endStroke=stroke(self.endCard,C.accent,.2,2)
 make('UIGradient',self.endCard,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(200,210,220))})
 self.endScale=make('UIScale',self.endCard,{Scale=1})
 self.endWin=badge(self.endCard,'trophy',64,C.amber,UDim2.new(.5,-32,0,20));self.endWin.ZIndex=46
 self.endLose=badge(self.endCard,'swords',64,Color3.fromRGB(255,110,96),UDim2.new(.5,-32,0,20));self.endLose.ZIndex=46
 for _,b in ipairs({self.endWin,self.endLose})do for _,d in ipairs(b:GetDescendants())do if d:IsA('GuiObject')then d.ZIndex=47 end end end
 self.endTitle=label(self.endCard,'',28,Enum.FontWeight.Heavy,C.white,{Position=UDim2.fromOffset(0,94),Size=UDim2.new(1,0,0,34),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=46})
 self.endTitleGradient=make('UIGradient',self.endTitle,{Rotation=90})
 self.endText=label(self.endCard,'',14,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(24,132),Size=UDim2.new(1,-48,0,40),
  TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,ZIndex=46})
 -- Silver for the match: the sum; a tap (or the pointer over it) opens the lines it is made of.
 self.endSilver=pressable(self.endCard,{Name='EndSilver',BackgroundColor3=C.ink,BackgroundTransparency=.35,Position=UDim2.fromOffset(24,176),Size=UDim2.new(1,-48,0,30),ZIndex=46},function()self.endOpen=not self.endOpen end)
 corner(self.endSilver,10);stroke(self.endSilver,SILVER,.7,1)
 self.endSilver.MouseEnter:Connect(function()self.endHover=true end);self.endSilver.MouseLeave:Connect(function()self.endHover=false end)
 self.endSilverText=label(self.endSilver,'',15,Enum.FontWeight.Heavy,SILVER,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=47})
 Icons.lead(self.endSilverText,'coins',{size=17,gap=7,color=SILVER})
 self.endLines={}
 for i=1,8 do
  local row=make('Frame',self.endCard,{BackgroundTransparency=1,Size=UDim2.new(1,-72,0,18),Visible=false,ZIndex=46})
  local name=label(row,'',12,Enum.FontWeight.Medium,C.muted,{Size=UDim2.new(.6,0,1,0),ZIndex=47})
  local amount=label(row,'',12,Enum.FontWeight.Bold,C.text,{Position=UDim2.fromScale(.6,0),Size=UDim2.new(.4,0,1,0),TextXAlignment=Enum.TextXAlignment.Right,ZIndex=47})
  self.endLines[i]={row=row,name=name,amount=amount}
 end
 self.endLobby=pressable(self.endCard,{Name='EndLobby',BackgroundColor3=C.tile,Position=UDim2.fromOffset(24,184),Size=UDim2.new(.5,-30,0,52),ZIndex=46},function()self:endChoice('lobby')end)
 corner(self.endLobby,14);stroke(self.endLobby,C.white,.8,1)
 Icons.lead(label(self.endLobby,'Lobby',16,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=47}),'home',{size=18,gap=8})
 self.endAgain=pressable(self.endCard,{Name='EndAgain',BackgroundColor3=C.white,Position=UDim2.new(.5,6,0,184),Size=UDim2.new(.5,-30,0,52),ZIndex=46},function()self:endChoice('again')end)
 corner(self.endAgain,14);make('UIGradient',self.endAgain,{Rotation=90,Color=ColorSequence.new(C.amber,C.amberDeep)})
 make('UIStroke',self.endAgain,{Color=Color3.fromRGB(255,230,170),Transparency=.35,Thickness=1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 Icons.lead(label(self.endAgain,'Play again',16,Enum.FontWeight.Heavy,Color3.fromRGB(40,20,6),{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=47}),'restart',{size=18,gap=8})
 -- Solo, after a defeat: take command of the country that did it (a purchase for Robux, or one bought
 -- earlier and not used yet). Hidden when there is nothing to buy or use, or that country is gone.
 self.endTake=pressable(self.endCard,{Name='EndTake',BackgroundColor3=C.tile,Size=UDim2.new(1,-48,0,44),Visible=false,ZIndex=46},function()self:takeCommand()end)
 corner(self.endTake,14);stroke(self.endTake,Color3.fromRGB(120,220,150),.45,1.5)
 self.endTakeText=label(self.endTake,'',15,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=47})
 Icons.lead(self.endTakeText,'star',{size=17,gap=8,color=Color3.fromRGB(120,220,150)})
 Store.onFinished(function(key,purchased)
  -- The purchase window closed without a purchase: the count to the lobby goes on.
  if key=='takeover'and not purchased and self.takeWait then self.takeWait=nil;self:releaseTake()end
 end)
 -- The time left: a thin bar that drains, and the seconds under it.
 self.endBar=corner(make('Frame',self.endCard,{BackgroundColor3=Color3.fromRGB(8,14,20),BackgroundTransparency=.2,Position=UDim2.fromOffset(24,250),
  Size=UDim2.new(1,-48,0,5),ZIndex=46}),3)
 self.endFill=corner(make('Frame',self.endBar,{BackgroundColor3=C.accent,Size=UDim2.fromScale(1,1),ZIndex=47}),3)
 self.endClock=label(self.endCard,'',12,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(24,260),Size=UDim2.new(1,-48,0,18),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=46})
 self.daily=DailyCard.new(self)
 self.shop=Shop.new(self)
 self.chest=Chest.new(self)
 -- The starter pack's own window and the gold tile at the lobby's left edge (shared/StarterOffer).
 self.starterOffer=StarterOffer.new(self)
 -- The party (shared/PartyPanel): its own button at the top right.
 self.party=PartyPanel.new(self)
 -- A new player's first match (shared/Tutorial), started by L:update.
 self.tutorial=Tutorial.new(view)
 -- The online search: the server says how it goes (queued, teleporting, failed).
 self.queue={state='idle'}
 -- Back from an online match with "Play again": the search starts again by itself (L:update).
 local ok,join=pcall(function()return Players.LocalPlayer:GetJoinData()end)
 self.searchAgain=ok and type(join)=='table'and type(join.TeleportData)=='table'and join.TeleportData.again==true
 task.spawn(function()
  local api=game.ReplicatedStorage.SeaBattle:WaitForChild("ConquestAPI")
  api:WaitForChild("Queue").OnClientEvent:Connect(function(st)
   if type(st)=='table'and st.state=='teleporting'and self.queue.state~='teleporting'then Sfx.play('found')end
   self.queue=st;self.queueAt=os.clock()
  end)
 end)
 return self
end

-- "hub" (lobby server) or "match" (the server of one online match), set by the server.
function L:role()return game.ReplicatedStorage.SeaBattle:GetAttribute("ServerRole")or "hub"end
-- What Online does now: on a hub the search (idle / queued / teleporting / failed); on a match server
-- the match itself.
function L:onlineState()
 if self:role()=="match"then return 'match'end
 return self.queue and self.queue.state or 'idle'
end
function L:humans()local n=0;for _ in pairs(self.v.live.battle.clients or {})do n+=1 end;return n end
function L:countdownLeft()
 local ends=self.v.live.battle.countdownEnds
 return ends and math.max(0,math.ceil(ends-workspace:GetServerTimeNow()))or 0
end
-- What the map shows: the demo behind the menu, the solo match, or the server's match.
function L:source()
 if self.mode=='menu'then return 'demo'end
 if self.playing=='solo'then return 'solo'end
 return 'server'
end
function L:pop()
 local fit=self.fit or 1
 self.scale.Scale=fit*.94;TweenService:Create(self.scale,POP,{Scale=fit}):Play()
 local sf=self.stripFit or 1
 self.stripScale.Scale=sf*.94;TweenService:Create(self.stripScale,POP,{Scale=sf}):Play()
end
function L:open(mode)
 if mode=='menu'and self.mode~='menu'then self.pendingSolo=nil end
 -- Leaving a solo match (back to the menu) drops it; the demo comes back behind the menu.
 if mode=='menu'and self.playing=='solo'then self:reportSolo(true)end
 if mode=='menu'and self.playing=='solo'and self.v.localMatch.ready then self.v.localMatch:demo()end
 if mode=='menu'then self.playing=nil;self.page='home';self.lastSize=nil;self:pop()end
 self.mode=mode
end
function L:setPage(page)self.page=page;self.lastSize=nil;self:pop()end
function L:choose(mode)
 if mode=='solo'then self:setPage('solo');return end
 local state=self:onlineState()
 -- In a party only the leader starts and stops the search (the whole party goes along).
 if state~='match'and self.party:inParty()and not self.party:isLeader()then self.leaderNoteAt=os.clock();return end
 if state=='queued'then self.v:send('unqueue');self.queue={state='idle'}
 elseif state=='idle'or state=='failed'then self.queue={state='queued',waited=0};self.queueAt=os.clock();self.v:send('queue')
 elseif state=='match'then self.playing='online';self:open('spawn')end
end
function L:startSolo()
 -- (a solo match dropped for a new one is paid as left early)
 self:reportSolo(true)
 -- The lobby shows before the device has built its match: then "Battle" waits for it (see update).
 if not self.v.localMatch.ready or not self.v.localMatch:solo(self.difficulty or 'normal')then
  self.pendingSolo=true;self.v.message='Preparing the map…';return
 end
 self.pendingSolo=nil;self.playing='solo';self:open('spawn')
 -- The server notes when this solo match began: its silver is limited by the real time played.
 self.soloOpen=true;self.v.payout=nil
 local difficulty=self.difficulty or 'normal'
 task.spawn(function()self.v:request('solo_started',{difficulty=difficulty})end)
end
-- The result of the solo match on this device goes to the server once: at its end card, or when the match
-- is left (`quit`: left with a living country — paid without the lines for taking part and the place).
-- Nothing is sent for a match left before a coast was picked.
function L:reportSolo(quit)
 if not self.soloOpen then return end
 local lm=self.v.localMatch;local g=lm.game
 local owner=g and lm.kind=='solo'and g.clients[lm.user]
 self.soloOpen=false
 if not owner then return end
 local result=g:matchResult(owner);if not result then return end
 local report={minutes=result.minutes,peakShare=result.peakShare,participants=result.participants,kills=result.kills,place=result.place,
  won=result.won,quit=quit==true and result.alive and g.phase=='playing'}
 task.spawn(function()
  local r=self.v:request('solo_result',report)
  if r.ok and r.payout then self.v.payout=r.payout end
 end)
end
-- Seconds the end card waits for a choice before the lobby comes back on its own.
local END_SECONDS=10
-- Out of the match into the lobby (the end card and the pause menu): from an online match server
-- back to a lobby server, a solo match is dropped and the camera shows the whole world again.
function L:exitMatch()
 if self.playing=='online'and self:role()=="match"then self.v:send('leave');return end
 self:open('menu');self.v.gui:SetAttribute('ResetCamera',(self.v.gui:GetAttribute('ResetCamera')or 0)+1)
end
-- The country that finished the player's off in the solo match on this device, if it still stands.
function L:conqueror()
 local lm=self.v.localMatch;local g=lm.game
 if not g or lm.kind~='solo'or g.phase~='playing'then return nil end
 local mine=g.factions[g.clients[lm.user]or 0]
 local by=mine and not mine.alive and mine.killedBy and g.factions[mine.killedBy]
 return by and by.alive and by.bot and by or nil
end
-- "Take command": the solo match and the count to the lobby stand still meanwhile.
function L:takeCommand()
 if self.taking or self.takeWait or not self:conqueror()then return end
 local p=self.v.profile
 self.endHold=true;self.v.localMatch.paused=true
 if p and p.credits and(p.credits.takeover or 0)>0 then self:useTakeover()
 elseif Store.prompt('takeover')then self.takeWait=os.clock()
 else self:releaseTake()end
end
function L:releaseTake()
 self.endHold=false;self.taking=false;self.takeWait=nil
 if not self.v.battleUI.pause.open then self.v.localMatch.paused=false end
end
-- Spend one bought takeover: the server takes the credit and notes a new solo life, then the device
-- hands the conqueror's country to the player.
function L:useTakeover()
 if self.taking then return end
 self.taking=true;self.takeWait=nil
 task.spawn(function()
  local r=self.v:request('takeover_use')
  if r.ok and self.v.localMatch:takeover()then
   self.soloOpen=true;self.v.payout=nil;self.focusPending=true
   -- (no end card until the view shows the new country alive)
   self:hideEnd();self.endAt=nil;self.endDone=true
  else self.v.battleUI:toast('Could not take command. Try again.','bad')end
  self:releaseTake()
 end)
end
-- The end card's buttons (and its timeout, as 'lobby'). Another match: solo starts a new one at the same
-- difficulty at once; online goes back to a lobby server and searches for a new match there.
function L:endChoice(choice)
 if not self.endShown then return end
 self:hideEnd();self.endDone=true
 local online=self.playing=='online'and self:role()=="match"
 if choice=='again'then
  if online then self.v:send('leave',{again=true});return end
  self:startSolo()
  local gui=self.v.gui;gui:SetAttribute('ResetCamera',(gui:GetAttribute('ResetCamera')or 0)+1)
  return
 end
 self:exitMatch()
end
function L:hideEnd()
 self.endShown=false;self.endShade.Visible=false;self.endCard.Visible=false
 if self.endHold or self.takeWait then self:releaseTake()end
end
-- The end card (called every frame): shown once your country is gone while the match goes on, or once
-- the match is over; it counts END_SECONDS down to the lobby.
function L:updateEnd()
 local v=self.v
 local inMatch=(self.playing=='solo'and v.source=='solo')or(self.playing=='online'and v.source=='server')
 local me=inMatch and v.playerId and v.factions[v.playerId]
 if not me or self.mode~='hidden'or(v.phase~='playing'and v.phase~='finished')then
  if self.endShown then self:hideEnd()end
  if v.phase~='playing'and v.phase~='finished'then self.everAlive=false;self.endAt=nil;self.endDone=false end
  return
 end
 if me.alive and v.phase=='playing'then self.everAlive=true;self.endAt=nil;self.endDone=false;if self.endShown then self:hideEnd()end;return end
 local finished=v.phase=='finished'
 if not finished and not self.everAlive then return end
 if self.endDone then return end
 -- Filled when the card opens and again if the winner arrives a moment after the end of the match
 -- (the phase and the winner can come in different packets).
 local battle=v.battle or {};local w=battle.winner
 local first=not self.endAt
 if first or w~=self.endWinner then
  self.endAt=self.endAt or os.clock();self.endWinner=w
  local teams=battle.settings and battle.settings.teams
  local won=finished and w~=nil and(w==v.playerId or(teams and me.team==w))
  -- Place: by water among the countries still in the match; a country already gone is behind them all.
  local ranked={};local total=0
  for _,f in pairs(v.factions)do total+=1;if f.alive and(f.count or 0)>0 then table.insert(ranked,f)end end
  table.sort(ranked,function(a,b)return(a.count or 0)>(b.count or 0)end)
  local place=#ranked+1;for i,f in ipairs(ranked)do if f.id==me.id then place=i end end
  local text
  if won then text='You took '..v:share(me.count or 0)..' of the world\'s water. Place: 1 of '..total..'.'
  elseif finished then
   local winner=not teams and w and v.factions[w]
   text=(winner and(winner.name..' won. ')or teams and('Team '..tostring(w)..' won. ')or'')..'Your place: '..place..' of '..total..'.'
  else text='Your fleet was destroyed. Place: '..place..' of '..total..'.'end
  self.endTitle.Text=won and'YOU WON'or'YOU LOST'
  self.endTitleGradient.Color=won and ColorSequence.new(C.white,C.amber)or ColorSequence.new(Color3.fromRGB(255,200,190),Color3.fromRGB(255,120,104))
  self.endWin.Visible=won;self.endLose.Visible=not won
  self.endStroke.Color=won and C.amber or Color3.fromRGB(255,110,96)
  self.endFill.BackgroundColor3=won and C.amber or C.accent
  self.endText.Text=text
  if first then
   -- A solo result is sent to the server now; an online one the server has counted itself.
   if self.playing=='solo'then self:reportSolo(false)end
   self.endOpen=false;self.endHover=false
   Sfx.play(won and 'win'or 'lose')
   v.battleUI:clearSelection();if v.battleUI.pause.open then v.battleUI.pause:show(false)end
   self.endShown=true;self.endWon=won==true;self.endShade.Visible=true;self.endCard.Visible=true;self.endY=nil
   local size=v.gui.AbsoluteSize;self.endFit=math.clamp(math.min((size.X-24)/380,(size.Y-24)/330),.5,1.15)
   self.endScale.Scale=self.endFit*.9;TweenService:Create(self.endScale,POP,{Scale=self.endFit}):Play()
  end
 end
 -- Silver: the sum once the server has answered ("on its way…" after two seconds of waiting), and
 -- its lines while the row is open or under the pointer. The card grows by the lines shown.
 local pay=v.payout
 local waited=os.clock()-self.endAt
 self.endSilver.Visible=pay~=nil or waited>2
 local loot=''
 if pay and(pay.chests or 0)>0 then loot='  ·  +'..pay.chests..(pay.chests==1 and ' chest'or ' chests')end
 if pay and(pay.keys or 0)>0 then loot..='  ·  +'..pay.keys..' key'end
 self.endSilverText.Text=pay and('+'..compact(pay.total)..' silver'..loot)or 'silver on its way…'
 local shownLines=pay and(self.endOpen or self.endHover)and #pay.lines>0
 local y=176+(self.endSilver.Visible and 38 or 0)
 for i,row in ipairs(self.endLines)do
  local line=shownLines and pay.lines[i]
  row.row.Visible=line~=nil and line~=false
  if line then
   row.row.Position=UDim2.fromOffset(36,y);y+=18
   row.name.Text=Economy.Titles[line[1]]or line[1]
   row.amount.Text=(line[2]>=0 and '+'or '−')..compact(math.abs(line[2]))
  end
 end
 if shownLines then y+=8 end
 -- Solo defeat: the takeover button, when there is one to buy or use and the conqueror still stands.
 local credits=v.profile and v.profile.credits and v.profile.credits.takeover or 0
 local canTake=self.playing=='solo'and not finished and(credits>0 or Store.available('takeover'))and self:conqueror()~=nil
 self.endTake.Visible=canTake
 if canTake then
  self.endTakeText.Text=self.taking and 'Taking command…'or credits>0 and('Take command · '..credits..' left')or('Take command · '..Store.label('takeover'))
  self.endTake.Active=not self.taking
  -- (paid for a moment ago: use it at once)
  if self.takeWait and credits>0 then self:useTakeover()end
 end
 local takeH=canTake and 52 or 0
 if y+takeH~=self.endY then
  self.endY=y+takeH
  self.endLobby.Position=UDim2.fromOffset(24,y+8);self.endAgain.Position=UDim2.new(.5,6,0,y+8)
  self.endTake.Position=UDim2.fromOffset(24,y+68)
  y+=takeH
  self.endBar.Position=UDim2.fromOffset(24,y+74);self.endClock.Position=UDim2.fromOffset(24,y+84)
  self.endCard.Size=UDim2.fromOffset(380,y+116)
  local size=v.gui.AbsoluteSize;self.endFit=math.clamp(math.min((size.X-24)/380,(size.Y-24)/(y+116)),.5,1.15);self.endScale.Scale=self.endFit
 end
 local left=END_SECONDS-(os.clock()-self.endAt)
 -- (the count to the lobby waits while the lines are being read)
 if shownLines or self.endHold then self.endAt+=math.min(.1,os.clock()-(self.endTick or os.clock()))end
 self.endTick=os.clock()
 self.endFill.Size=UDim2.fromScale(math.clamp(left/END_SECONDS,0,1),1)
 self.endClock.Text='Back to the lobby in '..math.max(0,math.ceil(left))..' s'
 if finished and v.resultsLeft~=math.max(0,math.ceil(left))then v.resultsLeft=math.max(0,math.ceil(left));v.needsHUD=true end
 if left<=0 then self:endChoice('lobby')end
end
function L:backToLobby()
 -- From an online match server "back" means the lobby server.
 if self:role()=="match"and self.playing=='online'then self.v:send('leave');return end
 self:open('menu')
end

-- Lay out the card for the screen: wordmark beside it on a big screen, above it otherwise.
function L:layout(size)
 if self.lastSize==size then return end
 self.lastSize=size
 -- Reach under the top bar as well, so the whole screen is shaded.
 local inset=game:GetService('GuiService'):GetGuiInset().Y
 self.root.Position=UDim2.fromOffset(0,-inset);self.root.Size=UDim2.new(1,0,1,inset)
 local short=size.Y<560
 -- A phone (the same test as the match interface): logo on top, a slim strip at the bottom.
 self.phone=size.X<900 or size.Y<520
 self.card.Visible=not self.phone;self.strip.Visible=self.phone
 self.party:layout(size,inset,self.phone)
 if self.phone then self:layoutPhone(size,inset);return end
 self.footer.Text=FOOTER;self.footer.Position=UDim2.new(.5,0,1,-8);self.footer.Size=UDim2.new(1,-32,0,14)
 self.stripNote.Visible=false;self.stripWallet.pill.Visible=false
 -- Side by side on a big screen.
 local wide=size.X>=900 and not short
 local cardH
 if self.page=='solo'then cardH=304
 else
  local y=218
  if self.watch.Visible then y+=58 end
  local third=(W-PAD*2-20)/3
  self.shopButton.Position=UDim2.fromOffset(PAD,y);self.shopButton.Size=UDim2.fromOffset(third,42)
  self.chestButton.Position=UDim2.fromOffset(PAD+third+10,y);self.chestButton.Size=UDim2.fromOffset(third,42)
  self.dailyButton.Position=UDim2.fromOffset(PAD+(third+10)*2,y);self.dailyButton.Size=UDim2.fromOffset(third,42)
  y+=54
  self.helpButton.Position=UDim2.fromOffset(PAD,y);self.helpButton.Size=UDim2.fromOffset(W-PAD*2,42)
  cardH=y+42+PAD
 end
 if self.noteShown then cardH+=22 end
 self.note.Position=UDim2.fromOffset(PAD,cardH-PAD-16);self.note.Size=UDim2.fromOffset(W-PAD*2,16)
 self.card.Size=UDim2.fromOffset(W,cardH)
 local fit
 if wide then
  fit=math.min(1.35,(size.Y-48)/cardH,(size.X*.5-40)/W)
  self.card.AnchorPoint=Vector2.new(.5,.5);self.card.Position=UDim2.new(.68,0,.5,inset/2)
  self.word.AnchorPoint=Vector2.new(.5,.5);self.word.Position=UDim2.new(.28,0,.5,inset/2)
  local wordW,wordH=self.word.Size.X.Offset,self.word.Size.Y.Offset
  self.wordScale.Scale=self.hasLogo and math.min(math.clamp(size.X/1000,.6,1.6),(size.X*.5-40)/wordW,(size.Y-40)/wordH)or math.clamp(size.X/1400,.75,1.3)
  self.shadeGradient.Rotation=0
 else
  local wordH=self.hasLogo and self.word.Size.Y.Offset or(short and 84 or 112)
  local wordScale=self.hasLogo and math.clamp(math.min((size.X-48)/420,size.Y*(short and .3 or .26)/wordH),.4,1)
   or(short and .62 or math.clamp(size.X/700,.6,1))
  self.wordScale.Scale=wordScale
  local top=(short and 0 or 12)+wordH*wordScale*((short and not self.hasLogo)and .8 or 1)
  fit=math.min(1.1,(size.Y-top-16)/cardH,(size.X-24)/W)
  -- Wordmark and card together, centred in the height.
  local spare=math.max(0,(size.Y-top-16-cardH*fit)/2)
  self.word.AnchorPoint=Vector2.new(.5,0);self.word.Position=UDim2.new(.5,0,0,inset+spare+(short and -6 or 12))
  self.card.AnchorPoint=Vector2.new(.5,0);self.card.Position=UDim2.new(.5,0,0,inset+spare+top+4)
  self.shadeGradient.Rotation=90
 end
 self.fit=math.max(.45,fit);self.scale.Scale=self.fit
 self.tag.Visible=not short and not self.hasLogo
 self.bannerScale.Scale=math.clamp((size.X-24)/466,.6,1);self.banner.Position=UDim2.new(.5,0,0,12)
end
-- The phone layout: the strip at the bottom (one row of buttons for the page shown), a note above it,
-- the logo centred at the top under Roblox's bar, the demo match visible between.
function L:layoutPhone(size,inset)
 local H,G,P=52,8,8
 local w=math.min(size.X-16,560)
 local function row(items)
  -- items: {r, width or nil (shares what is left)}
  local fixed,flex=0,0
  for _,it in ipairs(items)do if it[2]then fixed+=it[2]else flex+=1 end end
  local each=flex>0 and(w-P*2-fixed-G*(#items-1))/flex or 0
  local x=P
  for _,it in ipairs(items)do
   local bw=it[2]or each
   local b=it[1].button;b.Visible=true;b.Position=UDim2.fromOffset(x,P);b.Size=UDim2.fromOffset(bw,H)
   -- Icon and title centred together when there is room for both, the icon alone otherwise.
   local t=it[1].title
   if t then local both=bw>=92;t.Visible=both;it[1].icon.Visible=not both end
   x+=bw+G
  end
 end
 for _,r in ipairs({self.sSolo,self.sOnline,self.sWatch,self.sHelp,self.sBack,self.sPlay,self.sDaily,self.sShop,self.sChest})do r.button.Visible=false end
 for _,r in pairs(self.sDiff)do r.button.Visible=false end
 if self.page=='solo'then
  row({{self.sBack,H},{self.sDiff.easy},{self.sDiff.normal},{self.sDiff.hard},{self.sPlay,math.min(140,math.floor(w*.3))}})
 else
  local items={{self.sSolo},{self.sOnline}}
  if self.stripWatch then table.insert(items,{self.sWatch})end
  table.insert(items,{self.sShop,H});table.insert(items,{self.sChest,H});table.insert(items,{self.sDaily,H});table.insert(items,{self.sHelp,H})
  row(items)
 end
 local stripH=H+P*2
 self.strip.Size=UDim2.fromOffset(w,stripH)
 self.stripFit=math.clamp((size.X-16)/w,.6,1);self.stripScale.Scale=self.stripFit
 -- (root covers the top bar too: its bottom is the screen's bottom)
 self.strip.Position=UDim2.new(.5,0,1,-10)
 local noteH=self.stripNote.Text~=''and 34 or 0
 self.stripNote.Visible=noteH>0
 -- (the silver pill sits over the strip's right end; the note keeps clear of it on both sides)
 local pw=self.stripWallet.width
 self.stripNote.Position=UDim2.new(.5,0,1,-10-stripH-6);self.stripNote.Size=UDim2.fromOffset(w-16-(pw+10)*2,noteH)
 self.stripWallet.pill.Visible=true;self.stripWallet.pill.Position=UDim2.new(.5,math.floor(w/2),1,-10-stripH-6)
 -- the footer: one small line in the gap under the strip
 self.footer.Text=FOOTER_SHORT;self.footer.Position=UDim2.new(.5,0,1,-1);self.footer.Size=UDim2.new(1,-16,0,9)
 -- The logo (or the text title) centred at the top: large, up to 70% of the free height (260 points).
 -- The note's line is always counted, shown or not, so the logo keeps one size on every page.
 local free=size.Y-(stripH+16+34)-16
 local wordW,wordH=self.word.Size.X.Offset,self.word.Size.Y.Offset
 if self.hasLogo then
  self.wordScale.Scale=math.clamp(math.min((size.X-24)/wordW,math.min(free*.7,260)/wordH),.3,1.1)
 else self.wordScale.Scale=math.clamp(math.min((size.X-32)/wordW,free*.3/84),.4,1)end
 self.word.AnchorPoint=Vector2.new(.5,0);self.word.Position=UDim2.new(.5,0,0,inset+8)
 self.tag.Visible=false
 self.shadeGradient.Rotation=90
 self.fit=1
 -- The start banner goes up into Roblox's top bar, level with its buttons (ConquestView:topbar).
 -- (a phone held upright has too little bar for it: then it stays under the bar)
 local tb=self.v.topbar and self.v:topbar()
 local sc=tb and math.min(1,(tb.h-8)/60,(tb.x1-tb.x0-16)/466)
 if sc and sc>=.7 then
  self.bannerScale.Scale=sc
  self.banner.AnchorPoint=Vector2.new(.5,0)
  self.banner.Position=UDim2.fromOffset(math.floor((tb.x0+tb.x1)/2),math.floor(tb.mid-30*self.bannerScale.Scale))
 else
  self.bannerScale.Scale=math.clamp((size.X-24)/466,.6,1);self.banner.Position=UDim2.new(.5,0,0,12)
 end
end

local function plural(n,one,few,many)
 return(n%10==1 and n%100~=11 and one)or(n%10>=2 and n%10<=4 and(n%100<12 or n%100>14)and few)or many
end
function L:update(dt)
 local v=self.v;local live=v.live;self.clock+=dt
 self:layout(v.gui.AbsoluteSize)
 -- The search is over once this server is a match server; a teleport that never happened gives up.
 if self:role()=="match"and self.queue.state~='idle'then self.queue={state='idle'}end
 if self.queue.state=='teleporting'and self.queueAt and os.clock()-self.queueAt>30 then self.queue={state='failed'}end
 if self.pendingSolo and self.mode=='menu'and v.localMatch.ready then self:startSolo()end
 -- A newcomer (no match played, the tutorial never seen) goes straight into the tutorial's solo match
 -- on Easy, once the profile is here: only on a lobby server, from the lobby, outside a party.
 local p=v.profile
 if not self.tutorialChecked and p and self.mode=='menu'and v.localMatch.ready and self:role()=="hub"then
  self.tutorialChecked=true
  if not p.tutorial and(p.stats and p.stats.matches or 0)==0 and not self.party:inParty()and self.queue.state=='idle'and not self.searchAgain then
   self.difficulty='easy';self.tutorial:begin();self:startSolo()
  end
 end
 self.tutorial:update(dt,self)
 if self.searchAgain and self.mode=='menu'and self:role()=="hub"and self:onlineState()=='idle'then self.searchAgain=false;self:choose('online')end
 local state=self:onlineState()
 -- Arriving on a match server (or Studio turning into one): straight to the start banner.
 if state=='match'and self.playing~='online'and self.playing~='watch'and live.phase=='countdown'then
  self.playing='online';self.mode='spawn';v.payout=nil
 end
 -- The match ended here (Studio: the server is a hub again): back to the lobby.
 if state~='match'and(self.playing=='online'or self.playing=='watch')then
  self:open('menu');v.gui:SetAttribute('ResetCamera',(v.gui:GetAttribute('ResetCamera')or 0)+1)
 end
 -- Having a country closes the start banner: at once in a solo match, when the countdown ends online.
 -- The camera then flies to the new country (Atlas listens for FocusCell).
 if self.mode=='spawn'then
  if self.playing=='solo'and v.playerId then self.mode='hidden';self.focusPending=true
  elseif self.playing=='online'and live.playerId and live.phase=='playing'then self.mode='hidden';self.focusPending=true
  elseif self.playing=='online'and not live.playerId and(live.phase=='playing'or live.phase=='finished')then
   -- Here without a country after the start (came in late): watch.
   self.playing='watch';self.mode='hidden'
  end
 end
 self:updateEnd()
 -- The match is over: the end card takes you back (L:updateEnd). Online the server also teleports
 -- everyone to a lobby server after R.ResultsSeconds; if that has not happened 15 s later the client asks
 -- (a spectator too: it has no end card).
 local over=(self.playing=='solo'and v.source=='solo'and v.phase=='finished')or((self.playing=='online'or self.playing=='watch')and live.phase=='finished')
 if over then
  self.finishedAt=self.finishedAt or os.clock()
  local left=R.ResultsSeconds-(os.clock()-self.finishedAt)
  if self.playing~='solo'and left<=-15 and not self.leaveSent then self.leaveSent=true;v:send('leave')end
 elseif self.finishedAt then self.finishedAt=nil;self.leaveSent=nil;v.resultsLeft=nil end
 if self.focusPending and v.playerId and v.source==self:source()then
  local f=v.factions[v.playerId];local cell=f and f.startCell or next(v.owned[v.playerId]or {})
  -- At the start the camera comes in close over the new country (a few cells big), not the region.
  if cell then v.gui:SetAttribute('FocusZoom',START_ZOOM);v.gui:SetAttribute('FocusCell',nil);v.gui:SetAttribute('FocusCell',cell);self.focusPending=false end
 end
 local menu=self.mode=='menu';local spawn=self.mode=='spawn'
 self.root.Visible=menu;self.banner.Visible=spawn
 self.party:update(dt,menu and self:role()=="hub")
 self.homeButton.Visible=self.mode=='hidden'and not v:myCountry()and live.phase~='loading'
 v.gui:SetAttribute('LobbyOpen',menu or spawn)
 -- The splash screen goes as soon as the lobby can be shown; the demo match joins the map a moment
 -- later, when it is built (waiting for it made the start slow).
 if not v.gui:GetAttribute('LobbyReady')then v.gui:SetAttribute('LobbyReady',true)end
 if spawn then
  -- Start banner: solo, an online countdown (with or without a coast picked), or joining a running match.
  local left=self:countdownLeft()
  if self.playing=='online'and live.phase=='countdown'then
   self.bannerTitle.Text='ONLINE · STARTS IN '..left..' S'
   self.bannerText.Text=live.playerId and('Coast chosen · players: '..self:humans())or 'Tap a free coast'
  elseif self.playing=='online'then
   self.bannerTitle.Text='ONLINE · PICK YOUR START';self.bannerText.Text='Match on · players: '..self:humans()
  elseif self.tutorial.active then self.bannerTitle.Text='PICK YOUR START';self.bannerText.Text='Tap the marked coast'
  else self.bannerTitle.Text='PICK YOUR START';self.bannerText.Text='Tap a free coast'end
  self.random.Visible=not(self.playing=='online'and live.playerId)
 end
 -- (the shop stays: the match's own shop button opens it over the map)
 self.shop:update(dt)
 self.chest:update(dt)
 self.starterOffer:update(dt,menu and self.page=='home')
 if not menu then
  if self.daily.open then self.daily:show(false)end;if self.chest.open then self.chest:setOpen(false)end
  if self.starterOffer.open then self.starterOffer:show(false)end
  return
 end
 -- Chests waiting: a count on the chest buttons.
 do
  local n=v.profile and v.profile.credits and v.profile.credits.chest or 0
  for _,b in ipairs({self.chestBadge,self.sChestBadge})do
   b.frame.Visible=n>0;local t=n>99 and '99+'or tostring(n);if b.text.Text~=t then b.text.Text=t end
  end
 end
 self.home.Visible=self.page=='home';self.solo.Visible=self.page=='solo'
 -- The silver balance (a dash until the profile has arrived).
 local profile=v.profile
 -- (a gain counts up to the new balance over about a second)
 if profile then
  local target=profile.silver or 0
  if not self.silverShown or target<self.silverShown then self.silverShown=target
  elseif target>self.silverShown then self.silverShown=math.min(target,self.silverShown+math.max(1,(target-self.silverShown)*math.min(1,dt*5)))end
 end
 local silverText=profile and compact(math.floor(self.silverShown))or '…'
 -- The daily reward: its window opens by itself once when today's reward waits; a dot marks the button.
 local waiting=self.daily:canClaim()
 self.dailyDot.Visible=waiting;self.sDailyDot.Visible=waiting
 if waiting and not self.dailyOffered and not self.searchAgain and state=='idle'and self.clock>1 then self.dailyOffered=true;self.daily:show(true)end
 self.daily:update(dt)
 -- The starter pack opens by itself once a visit while it is on offer, after the daily reward's window
 -- (when today's reward waits, that one comes first) and when nothing else is open.
 if not self.starterAutoShown and self.clock>1.5 and state=='idle'and not self.searchAgain and not self.daily.open and not(waiting and not self.dailyOffered)
  and not self.shop.open and not self.chest.open and not self.tutorial.active and not self.starterOffer.rewardLayer and self.starterOffer:available()then
  self.starterAutoShown=true;self.starterOffer:show(true)
 end
 if silverText~=self.silverText then
  self.silverText=silverText
  for _,w in ipairs({self.wallet,self.stripWallet})do
   w.text.Text=silverText
   w.width=math.max(56,math.ceil(v:textWidth(silverText,14))+42);w.pill.Size=UDim2.fromOffset(w.width,28)
  end
  self.lastSize=nil
 end
 local count=#Players:GetPlayers()
 -- Tiles: Solo is always open; Online says what it does right now.
 local function enable(t,on)t.Active=on;t.BackgroundTransparency=on and 0 or .45 end
 enable(self.soloTile,not v.localMatch.failed)
 enable(self.onlineTile,state~='teleporting')
 self.soloSub.Text='You vs 80 countries'
 local q=self.queue or {}
 local waited=(q.waited or 0)+(self.queueAt and math.floor(os.clock()-self.queueAt)or 0)
 local clockText=string.format('%d:%02d',waited//60,waited%60)
 self.onlineSub.Text=({idle='Find a match: everyone starts together',queued='Searching '..clockText..(q.queued and(' · '..q.queued..' in queue')or'')..' · cancel',
  teleporting='Joining the match…',failed='Could not join · try again',match='Back to picking a start'})[state]or ''
 self.live.Visible=state=='queued'or state=='teleporting'
 if self.watch.Visible then self.watch.Visible=false;self.lastSize=nil end
 local note=''
 local member=state~='match'and self.party:inParty()and not self.party:isLeader()
 if member and state=='idle'then self.onlineSub.Text='The party leader starts the match'end
 if self.leaderNoteAt and os.clock()-self.leaderNoteAt<3 then note='The party leader starts online matches.'end
 -- (no note while searching: the online tile's own line shows the clock; 2026-11-12, the author's request)
 if state=='teleporting'then note='Moving you to the match…'
 elseif state=='failed'then note='Could not join the match. Try again.'end
 self.note.Text=note
 local shown=note~=''
 if shown~=self.noteShown then self.noteShown=shown;self.lastSize=nil end
 -- Difficulty tiles: the chosen one lit in the accent colour.
 local chosen=self.difficulty or 'normal';self.difficulty=chosen
 for key,t in pairs(self.diffTiles)do
  local on=key==chosen
  t.BackgroundColor3=on and C.tileOn or C.tile
  local st=t:FindFirstChildOfClass('UIStroke');st.Color=on and C.accent or C.white;st.Transparency=on and 0 or .85;st.Thickness=on and 2 or 1
 end
 for _,d in ipairs(LEVELS)do if d[1]==chosen then self.diffText.Text=d[5]end end
 -- The phone strip shows the same state.
 if self.phone then
  enable(self.sSolo.button,not v.localMatch.failed);enable(self.sOnline.button,state~='teleporting')
  if self.sOnline.title then
   self.sOnline.title.Text=({idle='Online',queued='Searching '..clockText,teleporting='Joining…',failed='Try again',match='To start'})[state]or 'Online'
  end
  local stripNote=note
  if stripNote==''and self.page=='solo'then for _,d in ipairs(LEVELS)do if d[1]==chosen then stripNote=d[5]end end end
  if stripNote~=self.stripNote.Text then self.stripNote.Text=stripNote;self.lastSize=nil end
  for key,r in pairs(self.sDiff)do
   local on=key==chosen
   r.button.BackgroundColor3=on and C.tileOn or C.tile
   local st=r.button:FindFirstChildOfClass('UIStroke');st.Color=on and C.accent or C.white;st.Transparency=on and 0 or .85;st.Thickness=on and 2 or 1
  end
 end
 -- A slow glow on the start button.
 self.playGradient.Offset=Vector2.new(0,math.sin(self.clock*2)*.08)
end
function L:covers()return self.mode=='menu'or self.mode=='spawn'end
function L:isUI(obj)
 if self.endShown then return true end
 if self.shop.open or self.chest.open then return true end
 if self.starterOffer:isUI(obj)then return true end
 if self.root.Visible and(obj==self.root or obj:IsDescendantOf(self.root))then return true end
 if self.banner.Visible and(obj==self.banner or obj:IsDescendantOf(self.banner))then return true end
 if self.homeButton.Visible and(obj==self.homeButton or obj:IsDescendantOf(self.homeButton))then return true end
 if self.tutorial:isUI(obj)then return true end
 return false
end
return L
