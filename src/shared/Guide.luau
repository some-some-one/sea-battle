--!nonstrict
-- "How to play" (2026-11-12, by the author's request): a dimmed window with topic cards (a round
-- medallion with the topic's icon, a title
-- and a short text), two to a row on a wide screen and one on a narrow one. Two wide
-- cards list the buildings and the arsenal as chips with their keys. At the end a "Controls" card: key
-- caps beside what they do, for mouse and keyboard and for touch (the device in hand first).
-- Last, "Credits & licence" and the source repository's address (2026-11-14, by the author's request).
-- Numbers in the texts come from shared/NavalRules, so they follow the balance.
-- The body scrolls; it keeps a margin on every side so the cards' outlines are never cut.
local UIS=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local TextService=game:GetService("TextService")
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local R=require(script.Parent.NavalRules)
local Catalog=require(script.Parent.Catalog)
local Soundtrack=require(script.Parent.Soundtrack)

local G={};G.__index=G
local C={ink=Color3.fromRGB(9,18,27),card=Color3.fromRGB(20,34,45),tile=Color3.fromRGB(27,45,58),
 accent=Theme.colors.accent,text=Theme.colors.text,muted=Theme.colors.muted,white=Color3.new(1,1,1)}
local POP=TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
local Z=70       -- (over the pause menu, which opens it too)
local HEADER=78
local MARGIN=6       -- inside the scrolling body, on every side (outlines and the medallions' rings)
local GAP=12

local function percent(x)return math.floor(x*100+.5)..'%'end
local shares={};for _,s in ipairs(R.AttackShares)do table.insert(shares,math.floor(s*100+.5))end
local SHARES=table.concat(shares,' / ')..'%'
local ALLIANCE=math.floor(R.AllianceSeconds/60+.5)
local MINUTES=math.floor(R.MatchSeconds/60+.5)

-- Topics: icon, colour, title, text for mouse and keyboard, text for touch (nil: the same), and a chip
-- list for a wide card ('buildings' or 'arsenal').
local TOPICS={
 {'trophy',Color3.fromRGB(255,196,84),'Goal',
  'Hold '..percent(R.WinShare)..' of all the world\'s water, or be the largest country when '..MINUTES..' minutes run out. Land cannot be taken: countries grow by sea only.'},
 {'pin',Color3.fromRGB(255,150,90),'Pick a coast',
  'Click any free coast and your country appears there. In an online match you pick during the countdown: anyone too late gets a random coast.',
  'Tap any free coast and your country appears there. In an online match you pick during the countdown: anyone too late gets a random coast.'},
 {'waves',Color3.fromRGB(86,170,255),'Grow by sea',
  'Click free water to send your fleet there and grow. Click your own water to stop growing. Your fleet builds up on its own; ports give you more.',
  'Tap free water to send your fleet there and grow. Tap your own water to stop growing. Your fleet builds up on its own; ports give you more.'},
 {'swords',Color3.fromRGB(255,110,96),'Attack',
  'Click enemy water to start an attack. Set the share of your fleet with the '..SHARES..' buttons or Q and E. Backspace recalls your last attack. Numbers on the front: blue is your fleet, red is the enemy\'s.',
  'Tap another country to open its window: attack, alliance, fleet. Set the share of your fleet with the '..SHARES..' buttons. Numbers on the front: blue is your fleet, red is the enemy\'s.'},
 {'alliance',Color3.fromRGB(176,140,255),'Alliances',
  'Right-click a country to open its window: alliance or sending fleet. An alliance lasts '..ALLIANCE..' minutes, and allies do not fight. Whoever breaks an alliance defends worse for 30 seconds.',
  'Long-press a country to open its window: alliance or sending fleet. An alliance lasts '..ALLIANCE..' minutes, and allies do not fight. Whoever breaks an alliance defends worse for 30 seconds.'},
 {'radiation',Color3.fromRGB(255,96,110),'Missiles and defense',
  'A missile platform launches atomic (9) and hydrogen (0) missiles and MIRVs. Missile defense shoots down missiles flying at you. A fighter (8) patrols and steers enemy trade planes to you.',
  'A missile platform launches atomic and hydrogen missiles and MIRVs. Missile defense shoots down missiles flying at you. A fighter patrols and steers enemy trade planes to you.'},
 {'factory',Color3.fromRGB(111,208,186),'Build an economy',
  'Gold comes in on its own, and rigs give more. Pick a tile at the bottom of the screen (or its key), then a spot on the map. Each next building of the same kind costs more.',
  'Gold comes in on its own, and rigs give more. Tap a tile at the bottom of the screen, then a spot on the map. Each next building of the same kind costs more.','buildings'},
 {'shop',Color3.fromRGB(255,206,96),'Arsenal',
  'Silver from matches unlocks new weapons and orders in the shop forever. What you unlock shows up in your match panel right away, in solo and online.',nil,'arsenal'},
}
local BUILDINGS={
 {'anchor','port','More fleet and trade. On the coast.','1'},
 {'plane','airport','Trade planes and fighters. On the coast.','2'},
 {'drop','oil','Produces gold. On your water.','3'},
 {'flame','gas','Gold, cheaper than oil. On your water.','4'},
 {'shield','defense','Stronger defense of the water around it.','5'},
 {'radar','sam','Shoots down missiles flying at you.','6'},
 {'radiation','silo','Launches missiles.','7'},
 {'jet',nil,'Patrols and intercepts.','8'},
}
local ARSENAL_KEY={battery='Z',depthbomb='C',cluster='V',bombers='B',mobilize='N'}
-- Controls: {keys, what it does}. A key list shows each key as its own cap.
local KEYS_DESKTOP={
 {{'Click'},'Grow, attack or place an order'},
 {{'Right-click'},'Country window, cancel an order'},
 {{'W','A','S','D'},'Move the map (or drag with the mouse)'},
 {{'Wheel'},'Zoom (or + and −)'},
 {{'1','–','7'},'Buildings'},
 {{'8'},'Fighter'},
 {{'9','0'},'Atomic and hydrogen missiles'},
 {{'Z','C','V','B','N'},'Arsenal'},
 {{'Q','E'},'Attack share − / +'},
 {{'Space'},'Click under the cursor'},
 {{'Backspace'},'Recall your last attack'},
 {{'X','Esc'},'Cancel'},
 {{'Home'},'To your country'},
 {{'F'},'Whole world'},
 {{'Tab'},'Leaders'},
 {{'P'},'Pause'},
 {{'G'},'Cell grid'},
 {{'H'},'This help'},
 {{'M'},'Music on / off'},
 {{'Click a plane'},'Then click a spot on the map'},
}
local KEYS_TOUCH={
 {{'Tap'},'Grow, attack or place an order'},
 {{'Long press'},'Country window'},
 {{'Drag'},'Move the map'},
 {{'Pinch'},'Zoom'},
 {{'Bottom tile'},'Building or missile, then a spot'},
 {{'Your plane'},'Then tap a spot on the map'},
 {{'Status line'},'Leaders'},
}

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
  TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,ZIndex=Z+3})
 for k,v in pairs(props or {})do o[k]=v end
 return o
end
-- The height of wrapped text (measured with the legacy Builder Sans of the same weight, plus a margin).
local LEGACY={[Enum.FontWeight.Regular]=Enum.Font.BuilderSans,[Enum.FontWeight.Medium]=Enum.Font.BuilderSansMedium,
 [Enum.FontWeight.Bold]=Enum.Font.BuilderSansBold,[Enum.FontWeight.Heavy]=Enum.Font.BuilderSansExtraBold}
local function measure(text,size,weight,width)
 local ok,v=pcall(TextService.GetTextSize,TextService,text,size,LEGACY[weight]or Enum.Font.BuilderSans,Vector2.new(width,10000))
 if not ok then return Vector2.new(#text*size*.5,size*1.3)end
 return v
end
-- A round medallion: a soft glow, a ring and the icon.
local function medallion(parent,icon,color,size,pos)
 local glow=corner(make('Frame',parent,{Position=pos-UDim2.fromOffset(4,4),Size=UDim2.fromOffset(size+8,size+8),BackgroundColor3=color,BackgroundTransparency=.82,ZIndex=Z+3}),size)
 local d=corner(make('Frame',glow,{Position=UDim2.fromOffset(4,4),Size=UDim2.fromOffset(size,size),BackgroundColor3=color:Lerp(C.ink,.58),ZIndex=Z+4}),size)
 make('UIStroke',d,{Color=color,Thickness=2})
 make('UIGradient',d,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(165,165,165))})
 Icons.image(d,icon,math.floor(size*.52),C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+5})
 return glow
end
-- A key cap: a rounded box with a lip at the bottom. -> its width.
local function keycap(parent,text,x,y,h)
 local w=math.max(h,math.ceil(measure(text,12,Enum.FontWeight.Bold,1000).X)+14)
 if text=='–'then
  label(parent,text,13,Enum.FontWeight.Bold,C.muted,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(10,h),TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})
  return 10
 end
 local lip=corner(make('Frame',parent,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=Color3.fromRGB(4,10,16),BackgroundTransparency=.2,ZIndex=Z+3}),6)
 local cap=corner(make('Frame',lip,{Size=UDim2.new(1,0,1,-2),BackgroundColor3=C.white,BackgroundTransparency=.9,ZIndex=Z+4}),6)
 stroke(cap,C.white,.78,1)
 label(cap,text,12,Enum.FontWeight.Bold,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=false,ZIndex=Z+5})
 return w
end

function G.new(gui)
 local self=setmetatable({},G)
 -- `root` is what other code shows and hides (help.Visible); a click on the dim area closes it.
 self.root=make('TextButton',gui,{Name='Guide',Text='',AutoButtonColor=false,Size=UDim2.fromScale(1,1),BackgroundColor3=C.ink,BackgroundTransparency=.28,Visible=false,ZIndex=Z})
 self.root.Activated:Connect(function()self.root.Visible=false end)
 self.panel=corner(make('Frame',self.root,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),BackgroundColor3=C.card,Active=true,ZIndex=Z+1}),20)
 stroke(self.panel,C.white,.84,1)
 make('UIGradient',self.panel,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(205,212,222))})
 self.scale=make('UIScale',self.panel,{Scale=1})
 medallion(self.panel,'help',Color3.fromRGB(255,196,84),42,UDim2.fromOffset(22,18))
 label(self.panel,'HOW TO PLAY',22,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(78,16),Size=UDim2.new(1,-150,0,26),TextYAlignment=Enum.TextYAlignment.Center,ZIndex=Z+2})
 self.lead=label(self.panel,'',13,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(78,42),Size=UDim2.new(1,-150,0,18),TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+2})
 local close=make('TextButton',self.panel,{Text='',AutoButtonColor=false,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-18,0,20),Size=UDim2.fromOffset(38,38),BackgroundColor3=C.tile,ZIndex=Z+2})
 corner(close,19);stroke(close,C.white,.85,1)
 Icons.image(close,'close',14,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+3})
 close.Activated:Connect(function()self.root.Visible=false end)
 make('Frame',self.panel,{Position=UDim2.fromOffset(18,HEADER-6),Size=UDim2.new(1,-36,0,1),BackgroundColor3=C.white,BackgroundTransparency=.9,BorderSizePixel=0,ZIndex=Z+2})
 self.list=make('ScrollingFrame',self.panel,{Position=UDim2.fromOffset(12,HEADER),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,
  ScrollBarImageColor3=C.accent,ScrollingDirection=Enum.ScrollingDirection.Y,CanvasSize=UDim2.new(),ZIndex=Z+2})
 self.root:GetPropertyChangedSignal('Visible'):Connect(function()
  if self.root.Visible then
   local fit=self.fit or 1;self.scale.Scale=fit*.94;TweenService:Create(self.scale,POP,{Scale=fit}):Play()
   self.list.CanvasPosition=Vector2.zero
  end
 end)
 return self
end

-- One topic card at (x, y), `w` wide. -> its height.
function G:topic(i,t,x,y,w,touch,wide)
 local color=t[2]
 local card=corner(make('Frame',self.list,{Name='Topic'..i,Position=UDim2.fromOffset(x,y),BackgroundColor3=color:Lerp(C.tile,.86),ZIndex=Z+2}),16)
 stroke(card,color,.62,1)
 make('UIGradient',card,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(170,170,175))})
 medallion(card,t[1],color,44,UDim2.fromOffset(18,18))
 -- (the title beside the medallion, no topic numbers: 2026-11-12, the author's request)
 label(card,t[3],17,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(78,28),Size=UDim2.new(1,-90,0,24),TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd})
 local text=touch and t[5]or t[4]
 local tw=w-36
 local th=math.ceil(measure(text,14,Enum.FontWeight.Regular,tw).Y)
 label(card,text,14,Enum.FontWeight.Regular,C.muted,{Position=UDim2.fromOffset(18,72),Size=UDim2.fromOffset(tw,th)})
 local h=72+th+8
 local chips=t[6]=='buildings'and self:buildingChips(touch)or t[6]=='arsenal'and self:arsenalChips(touch)or nil
 if chips then
  local cols=wide and 3 or(w>=520 and 2 or 1)
  local cw=(tw-(cols-1)*10)/cols
  local ch=56
  for n,chip in ipairs(chips)do
   local col,row=(n-1)%cols,(n-1)//cols
   local f=corner(make('Frame',card,{Position=UDim2.fromOffset(18+col*(cw+10),h+6+row*(ch+8)),Size=UDim2.fromOffset(cw,ch),BackgroundColor3=C.ink,BackgroundTransparency=.45,ZIndex=Z+3}),12)
   stroke(f,C.white,.9,1)
   local badge=corner(make('Frame',f,{Position=UDim2.fromOffset(8,12),Size=UDim2.fromOffset(32,32),BackgroundColor3=color:Lerp(C.ink,.6),ZIndex=Z+4}),16)
   make('UIStroke',badge,{Color=color,Thickness=1.5,Transparency=.2})
   Icons.image(badge,chip.icon,17,C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+5})
   local keyW=0
   if chip.key and not touch then keyW=keycap(f,chip.key,cw-30,17,22)+8 end
   label(f,chip.title,13,Enum.FontWeight.Bold,C.text,{Position=UDim2.fromOffset(48,5),Size=UDim2.new(1,-56-keyW,0,18),TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+4})
   label(f,chip.text,11,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(48,22),Size=UDim2.new(1,-56-keyW,0,30),TextTruncate=Enum.TextTruncate.AtEnd,LineHeight=.95,ZIndex=Z+4})
  end
  h+=math.ceil(#chips/cols)*(ch+8)+10
 end
 card.Size=UDim2.fromOffset(w,h)
 return h
end
function G:buildingChips()
 local out={}
 for _,b in ipairs(BUILDINGS)do
  local name=b[2]and R.Buildings[b[2]]and R.Buildings[b[2]].name or 'Fighter'
  if b[2]=='defense'then name='Sea Post'end
  table.insert(out,{icon=b[1],title=name,text=b[3],key=b[4]})
 end
 return out
end
function G:arsenalChips()
 local out={}
 for _,key in ipairs(Catalog.ArsenalOrder)do
  local item=Catalog.Arsenal[key]
  table.insert(out,{icon=item.icon,title=item.title,text=item.plain,key=ARSENAL_KEY[key]})
 end
 return out
end
-- One block of controls: a heading and rows of key caps with what they do, in `cols` columns. -> its height.
function G:keyBlock(parent,title,icon,rows,x,y,w,cols)
 label(parent,title,12,Enum.FontWeight.Heavy,C.accent,{Position=UDim2.fromOffset(x+22,y),Size=UDim2.fromOffset(w-22,18),TextYAlignment=Enum.TextYAlignment.Center})
 Icons.image(parent,icon,16,C.accent,{Position=UDim2.fromOffset(x,y+1),ZIndex=Z+4})
 local gap=24
 local colW=(w-(cols-1)*gap)/cols
 local keyArea=math.min(140,math.floor(colW*.42))
 local per=math.ceil(#rows/cols)
 for n,row in ipairs(rows)do
  -- (filled down each column, then the next)
  local col,line=(n-1)//per,(n-1)%per
  local cx=x+col*(colW+gap);local yy=y+28+line*32
  local kx=cx
  for k,key in ipairs(row[1])do kx+=keycap(parent,key,kx,yy,26)+(k<#row[1]and 4 or 0)end
  local dx=math.max(cx+keyArea,kx+10)
  label(parent,row[2],13,Enum.FontWeight.Medium,C.text,{Position=UDim2.fromOffset(dx,yy),Size=UDim2.fromOffset(cx+colW-dx,26),TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd})
 end
 for c=1,cols-1 do
  make('Frame',parent,{Position=UDim2.fromOffset(x+c*(colW+gap)-gap/2,y+28),Size=UDim2.fromOffset(1,per*32-6),BackgroundColor3=C.white,BackgroundTransparency=.9,BorderSizePixel=0,ZIndex=Z+3})
 end
 return 28+per*32
end
function G:controls(x,y,w,touch,wide)
 local card=corner(make('Frame',self.list,{Name='Controls',Position=UDim2.fromOffset(x,y),BackgroundColor3=C.tile,ZIndex=Z+2}),16)
 stroke(card,C.white,.82,1)
 make('UIGradient',card,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(170,170,175))})
 medallion(card,'gamepad',Color3.fromRGB(150,190,210),44,UDim2.fromOffset(18,18))
 label(card,'CONTROLS',17,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(78,22),Size=UDim2.new(1,-90,0,24),TextYAlignment=Enum.TextYAlignment.Center})
 label(card,touch and 'For phone and tablet; keyboard and mouse below.'or 'Keyboard and mouse; phone and tablet below.',12,Enum.FontWeight.Medium,C.muted,
  {Position=UDim2.fromOffset(78,46),Size=UDim2.new(1,-90,0,16),TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd})
 local first={'Mouse and keyboard','gamepad',KEYS_DESKTOP};local second={'Touch','people',KEYS_TOUCH}
 if touch then first,second=second,first end
 local inner=w-36;local top=84
 local cols=wide and 2 or 1
 local h1=self:keyBlock(card,first[1],first[2],first[3],18,top,inner,cols)
 make('Frame',card,{Position=UDim2.fromOffset(18,top+h1+6),Size=UDim2.fromOffset(inner,1),BackgroundColor3=C.white,BackgroundTransparency=.9,BorderSizePixel=0,ZIndex=Z+3})
 local h2=self:keyBlock(card,second[1],second[2],second[3],18,top+h1+18,inner,cols)
 local h=top+h1+18+h2+10
 card.Size=UDim2.fromOffset(w,h)
 return h
end
-- Build the cards for this width and device.
function G:build(designW,touch)
 self.list:ClearAllChildren()
 local wide=designW>=820
 local listW=designW-24
 local innerW=listW-MARGIN*2-8   -- (8: the scroll bar's lane)
 local cols=wide and 2 or 1
 local cw=(innerW-(cols-1)*GAP)/cols
 local y=MARGIN;local i=1
 while i<=#TOPICS do
  local t=TOPICS[i]
  if t[6]or cols==1 then
   y+=self:topic(i,t,MARGIN,y,innerW,touch,wide)+GAP;i+=1
  else
   local nxt=TOPICS[i+1]
   if nxt and not nxt[6]then
    -- a pair: both cards as tall as the taller one
    local a=self:topic(i,t,MARGIN,y,cw,touch,false)
    local b=self:topic(i+1,nxt,MARGIN+cw+GAP,y,cw,touch,false)
    local hh=math.max(a,b)
    self.list['Topic'..i].Size=UDim2.fromOffset(cw,hh);self.list['Topic'..(i+1)].Size=UDim2.fromOffset(cw,hh)
    y+=hh+GAP;i+=2
   else
    y+=self:topic(i,t,MARGIN,y,innerW,touch,wide)+GAP;i+=1
   end
  end
 end
 y+=self:controls(MARGIN,y,innerW,touch,wide)+GAP
 y+=self:credits(MARGIN,y,innerW)+GAP
 y+=self:source(MARGIN,y,innerW)+MARGIN
 self.list.CanvasSize=UDim2.fromOffset(0,y)
 return y
end
-- The last card: credits and the licence (AGPL-3.0 asks the game to say where it comes from, that it is
-- free software without warranty, and where its source is). Plain paragraphs, measured to wrap.
local REPO='github.com/some-some-one/sea-battle'
local CREDITS={
 'Sea Battle is a modified version of OpenFront. © OpenFront and Contributors. Changes © 2026 the Sea Battle developers.',
 'Sea Battle is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License, version 3, with the additional terms in its LICENSE file. It comes with ABSOLUTELY NO WARRANTY. The licence comes with the source code of Sea Battle.',
 'Map made with Natural Earth data (public domain). '..Soundtrack.credit..'.',
 'Some gameplay and interface ideas were inspired by RoWorld (github.com/lukechatton/roworld). No RoWorld code or assets are used.',
 'Sea Battle is not affiliated with or endorsed by OpenFront or RoWorld.',
}
function G:credits(x,y,w)
 local card=corner(make('Frame',self.list,{Name='Credits',Position=UDim2.fromOffset(x,y),BackgroundColor3=C.ink,BackgroundTransparency=.35,ZIndex=Z+2}),14)
 stroke(card,C.white,.86,1)
 label(card,'CREDITS & LICENCE',15,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(18,16),Size=UDim2.new(1,-36,0,20),TextWrapped=false})
 local ty=46
 for _,text in ipairs(CREDITS)do
  local h=math.ceil(measure(text,12,Enum.FontWeight.Medium,w-36).Y)+2
  label(card,text,12,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(18,ty),Size=UDim2.fromOffset(w-36,h)})
  ty+=h+8
 end
 local h=ty+8
 card.Size=UDim2.fromOffset(w,h)
 return h
end
-- Below it: "Source" and the public repository's address. A game cannot open a browser, so the address
-- sits in a read-only text box: on a computer it can be selected and copied.
function G:source(x,y,w)
 local row=make('Frame',self.list,{Name='Source',Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,40),BackgroundTransparency=1,ZIndex=Z+2})
 local bw=math.min(300,w-120)
 label(row,'Source',14,Enum.FontWeight.Medium,C.muted,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(.5,-(bw/2)+4,.5,0),Size=UDim2.fromOffset(80,20),
  TextXAlignment=Enum.TextXAlignment.Right,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=false})
 local b=corner(make('TextButton',row,{Name='SourceButton',Text='',AutoButtonColor=false,AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(.5,-(bw/2)+16,.5,0),
  Size=UDim2.fromOffset(bw,36),BackgroundColor3=C.tile,ZIndex=Z+3}),10)
 b.Activated:Connect(function()if self.repoBox then self.repoBox:CaptureFocus()end end)
 stroke(b,C.white,.8,1)
 Icons.image(b,'globe',16,C.text,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,12,.5,0),ZIndex=Z+4})
 self.repoBox=make('TextBox',b,{Text=REPO,TextEditable=false,ClearTextOnFocus=false,BackgroundTransparency=1,TextSize=13,FontFace=Theme.font(Enum.FontWeight.Bold),
  TextColor3=C.text,TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(36,0),Size=UDim2.new(1,-44,1,0),ZIndex=Z+4})
 return 40
end
-- Size the panel to the screen; called every frame by the Atlas, works only when the size changed.
function G:layout(size)
 local touch=UIS.TouchEnabled and not UIS.KeyboardEnabled
 if self.lastSize==size and self.lastTouch==touch then return end
 self.lastSize=size;self.lastTouch=touch
 local inset=game:GetService('GuiService'):GetGuiInset().Y
 self.root.Position=UDim2.fromOffset(0,-inset);self.root.Size=UDim2.new(1,0,1,inset)
 -- Laid out at a design width and scaled to the screen, like the lobby card.
 local designW=size.X>=900 and 900 or 460
 local contentH=self:build(designW,touch)
 local fit=math.min(math.clamp(size.X/1500,1,1.25),(size.X-24)/designW)
 -- (centred under Roblox's top bar: on a phone a tall panel would cover its buttons)
 self.panel.Position=UDim2.new(.5,0,.5,math.floor(inset/2))
 local maxH=(size.Y-16)/fit
 local h=math.min(HEADER+contentH+12,maxH)
 self.panel.Size=UDim2.fromOffset(designW,h)
 self.list.Size=UDim2.fromOffset(designW-24,h-HEADER-10)
 self.fit=fit;self.scale.Scale=fit
 self.lead.Text=designW>=820 and 'A naval strategy: your fleet decides everything. '..(touch and ''or 'H opens and closes this help.')or 'Your fleet decides everything.'
end
return G
