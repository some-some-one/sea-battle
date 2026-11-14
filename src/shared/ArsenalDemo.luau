--!nonstrict
-- The shop's arsenal previews (2026-11-11, by the author's request: the shop shows each item at
-- work, and players understand and buy more when they see it). A few seconds of what an item does in
-- a match, drawn in the map's own style and played over and over: the player's water on the left, a
-- rival's on the right, the units in the map's pixel shapes (UnitShapes), blasts as discs. Our own
-- drawing; every frame is a function of the time into the loop, so a preview can start anywhere.
--   depthbomb  the torpedo runs under water past a missile defence that cannot see it, and hits
--   cluster    a missile arcs over, bursts, and five bomblets fall around the aim
--   mobilize   gold turns into fleet at once: the counter jumps and new ships sail in
--   battery    the battery on the shore shells the rival's water in its ring; their fleet goes down
--   reload2x   two platforms: the fast one fires twice for the other's once
--   bombers    a bomber leaves the airport, slips past a missile defence every other time, bombs a mark
--   ArsenalDemo.new(parent, key, z) -> demo;  demo:show(key);  demo:step(clock);  demo:destroy()
local Icons=require(script.Parent.Icons)
local Shapes=require(script.Parent.UnitShapes)
local compact=require(script.Parent.NumberFormat).compact
local Theme=require(script.Parent.Theme)
local D={};D.__index=D
-- One loop, seconds; the stage is 200 x 100 units, centred in the frame (the sides show more water).
local LOOP=4
local OUR=Color3.fromRGB(66,124,170)
local ENEMY=Color3.fromRGB(164,86,108)
local SEA=Color3.fromRGB(26,58,90)
local LAND=Color3.fromRGB(190,170,120)
local INK=Color3.fromRGB(14,20,30)
local WHITE=Color3.new(1,1,1)
local FLASH=Color3.fromRGB(255,240,200)
local FIRE=Color3.fromRGB(255,130,50)
local GOLD=Color3.fromRGB(255,206,84)
local GOOD=Color3.fromRGB(126,222,152)
local BAD=Color3.fromRGB(255,110,100)
local function lerp(a,b,t)return a+(b-a)*t end
local function clamp01(t)return math.clamp(t,0,1)end
-- 0..1 across [a, b] of the loop (0 before, 1 after).
local function span(t,a,b)return clamp01((t-a)/(b-a))end
-- A fixed scatter (the same every loop): a number in 0..1 from a seed.
local function hash(n)local x=math.sin(n*12.9898)*43758.5453;return x-math.floor(x)end

function D.new(parent,key,z)
 local self=setmetatable({key=key,z=z or 60,rects={},discs={},icons={},texts={}},D)
 self.frame=Instance.new('Frame')
 self.frame.Name='ArsenalDemo';self.frame.BackgroundColor3=SEA;self.frame.BorderSizePixel=0;self.frame.ClipsDescendants=true
 self.frame.ZIndex=self.z;self.frame.Parent=parent
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,12);c.Parent=self.frame
 return self
end
function D:show(key)self.key=key end
function D:destroy()self.frame:Destroy()end

-- Immediate drawing: each frame asks for what it needs; the pools hand out the same objects again and
-- hide what was not asked for this time.
local function take(pool,n,make)
 local o=pool[n];if not o then o=make();pool[n]=o end
 return o
end
function D:toPx(x,y)return self.ox+x*self.u,self.oy+y*self.u end
-- A rectangle centred at (x, y), in stage units; rot in degrees.
function D:rect(x,y,w,h,color,layer,rot,alpha)
 self.nr+=1
 local f=take(self.rects,self.nr,function()
  local o=Instance.new('Frame');o.BorderSizePixel=0;o.AnchorPoint=Vector2.new(.5,.5);o.Parent=self.frame;return o
 end)
 local px,py=self:toPx(x,y)
 f.Position=UDim2.fromOffset(px,py);f.Size=UDim2.fromOffset(math.max(1,w*self.u),math.max(1,h*self.u))
 f.BackgroundColor3=color;f.BackgroundTransparency=alpha or 0;f.Rotation=rot or 0;f.ZIndex=self.z+(layer or 1);f.Visible=true
 return f
end
-- A disc (filled) or a ring (line > 0).
function D:disc(x,y,r,color,layer,alpha,line)
 self.nd+=1
 local f=take(self.discs,self.nd,function()
  local o=Instance.new('Frame');o.BorderSizePixel=0;o.AnchorPoint=Vector2.new(.5,.5);o.Parent=self.frame
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(1,0);c.Parent=o
  local s=Instance.new('UIStroke');s.Name='Line';s.Parent=o
  return o
 end)
 local px,py=self:toPx(x,y);local d=math.max(1,r*2*self.u)
 f.Position=UDim2.fromOffset(px,py);f.Size=UDim2.fromOffset(d,d);f.ZIndex=self.z+(layer or 1);f.Visible=true
 local s=f.Line
 if line then
  f.BackgroundTransparency=1;s.Enabled=true;s.Color=color;s.Thickness=line;s.Transparency=alpha or 0
 else
  s.Enabled=false;f.BackgroundColor3=color;f.BackgroundTransparency=alpha or 0
 end
 return f
end
function D:icon(name,x,y,size,color,layer)
 self.ni+=1
 local img=take(self.icons,self.ni,function()local o=Icons.image(self.frame,name,16,WHITE,{AnchorPoint=Vector2.new(.5,.5)});return o end)
 Icons.set(img,name)
 local px,py=self:toPx(x,y);local s=size*self.u
 img.Position=UDim2.fromOffset(px,py);img.Size=UDim2.fromOffset(s,s);img.ImageColor3=color or WHITE;img.ZIndex=self.z+(layer or 3);img.Visible=true
 return img
end
function D:text(value,x,y,size,color,layer,alpha)
 self.nt+=1
 local l=take(self.texts,self.nt,function()
  local o=Instance.new('TextLabel');o.BackgroundTransparency=1;o.AnchorPoint=Vector2.new(.5,.5);o.Size=UDim2.fromOffset(200,20)
  o.FontFace=Theme.font(Enum.FontWeight.Heavy);o.TextStrokeTransparency=.4;o.Parent=self.frame
  return o
 end)
 local px,py=self:toPx(x,y)
 l.Position=UDim2.fromOffset(px,py);l.Text=value;l.TextSize=math.max(9,size*self.u);l.TextColor3=color or WHITE
 l.TextTransparency=alpha or 0;l.TextStrokeTransparency=.35+(alpha or 0)*.65;l.ZIndex=self.z+(layer or 6);l.Visible=true
 return l
end
-- A unit shape (UnitShapes) at (x, y), facing `heading` (radians, 0 = right), q stage units a pixel.
function D:shape(name,x,y,q,heading,owner)
 local shape=Shapes.list[name];local a=heading or 0
 local ca,sa=math.cos(a),math.sin(a);local deg=math.deg(a)
 local fill=shape.fill and owner:Lerp(shape.fill,shape.mix or .5)or owner
 local rim=shape.rim or Color3.fromRGB(255,96,40)
 local dark=name=='mirv'and Color3.fromRGB(20,20,24)or fill:Lerp(Color3.new(0,0,0),.6)
 q*=(shape.scale or 1)*1.4 -- (bigger than on the map: the preview is small)
 local function put(list,color,grow,layer)
  for _,p in ipairs(list or {})do
   local ox,oy=(p[3]or 0)*q,(p[4]or 0)*q
   self:rect(x+ox*ca-oy*sa,y+ox*sa+oy*ca,p[1]*q+grow,p[2]*q+grow,color,layer,deg)
  end
 end
 put(shape.pieces,rim,q,4);put(shape.pieces,fill,0,5);put(shape.light,WHITE,0,6);put(shape.mark,dark,0,7)
end
-- A blast: a white flash that turns to fire, and a ring out to the edge; `age` 0..1.
function D:blast(x,y,r,age)
 if age<=0 or age>=1 then return end
 self:disc(x,y,r*(.3+.7*math.sqrt(age)),FIRE,8,.25+.7*age,math.max(1.5,self.u*.8))
 local core=r*.55*(1-age*.5)
 self:disc(x,y,core,FLASH:Lerp(FIRE,age),8,math.min(1,age*1.3))
end
-- The water a blast took: neutral sea showing through the rival's colour.
function D:hole(x,y,r,t)if t>0 then self:disc(x,y,r*math.min(1,t*3),SEA,2,0)end end
-- A structure on the map: a dark tile with its icon.
function D:building(icon,x,y,color)
 self:rect(x,y,13,13,INK,3,0,.1)
 self:icon(icon,x,y,10,color or WHITE,4)
end
-- The water: ours up to `split`, the rival's after it (and land between, when asked for).
function D:waters(split,landFrom,landTo)
 local half=400
 self:rect(split-half/2,50,half,300,OUR,1)
 self:rect(split+half/2,50,half,300,ENEMY,1)
 self:rect(split,50,.8,300,INK,2,0,.5)
 if landFrom then self:rect((landFrom+landTo)/2,50,landTo-landFrom,300,LAND,2)end
end

local scenes={}
-- The torpedo: under water from the platform, past a missile defence that does not see it.
function scenes.depthbomb(self,t,loop)
 self:waters(110)
 self:building('radiation',30,60,WHITE)
 self:disc(128,32,30,WHITE,2,.55,math.max(1,self.u*.6))
 self:building('radar',128,32,WHITE)
 local run=span(t,.08,.62)
 if run>0 and run<1 then
  local x=lerp(40,166,run)
  for k=1,5 do local bx=x-8-k*7;if bx>38 then self:rect(bx,60+((k%2)*2-1)*1.5,1.6,1.6,WHITE,3,0,.25+k*.13)end end
  self:shape('torpedo',x,60,1.6,0,OUR)
  if x>100 and x<158 then self:text('Defense blind',128,14,7,WHITE,9)end
 end
 local hit=span(t,.62,.92)
 self:hole(166,60,24,span(t,.62,.75)*(1-span(t,.95,1)))
 self:blast(166,60,30,hit)
end
-- The cluster: an arc over, a burst, five bomblets around the aim.
function scenes.cluster(self,t,loop)
 self:waters(100)
 self:building('radiation',28,64,WHITE)
 local ax,ay=150,46
 local fly=span(t,.05,.42)
 if fly>0 and fly<1 then
  local x=lerp(36,ax,fly);local y=lerp(64,ay,fly)-30*math.sin(math.pi*fly)
  local dx=ax-36;local dy=(ay-64)-30*math.pi*math.cos(math.pi*fly)
  self:shape('cluster',x,y,1.6,math.atan2(dy,dx),OUR)
 end
 local keep=1-span(t,.95,1)
 self:hole(ax,ay,14,span(t,.42,.5)*keep);self:blast(ax,ay,18,span(t,.42,.7))
 for k=1,5 do
  local ang=k/5*math.pi*2+.4;local r=26+hash(k)*8
  local tx,ty=ax+math.cos(ang)*r,ay+math.sin(ang)*r*.8
  local f=span(t,.42,.6)
  if f>0 and f<1 then self:shape('missile',lerp(ax,tx,f),lerp(ay,ty,f),1.3,0,OUR)end
  self:hole(tx,ty,7,span(t,.6,.66)*keep);self:blast(tx,ty,9,span(t,.6,.82))
 end
end
-- Mobilisation: gold turns into fleet at once.
function scenes.mobilize(self,t,loop)
 self:waters(400)
 local grow=span(t,.3,.5)
 local fleet=18000+3600*grow
 self:icon('ship',42,30,12,WHITE,6)
 self:text(compact(fleet),82,30,13,WHITE,7)
 if t>.3 and t<.75 then self:text('+'..compact(3600),82,lerp(18,6,span(t,.3,.75)),9,GOOD,8,span(t,.55,.75))end
 self:icon('coins',140,30,11,GOLD,6)
 self:text(t<.3 and '1.0M'or compact(1000000-3600),170,30,10,GOLD,7)
 local coin=span(t,.18,.32)
 if coin>0 and coin<1 then self:icon('coins',lerp(140,82,coin),30-14*math.sin(math.pi*coin),8,GOLD,8)end
 for k=1,10 do
  local arrive=span(t,.32+k*.025,.5+k*.025)
  if arrive>0 then
   local row,col=(k-1)%2,(k-1)//2
   local x=lerp(-20,40+col*26+row*13,1-(1-arrive)^2)
   self:shape('ship',x,62+row*16,2.2,0,OUR)
  end
 end
end
-- The coastal battery: a shell every second into the rival's water inside its ring.
function scenes.battery(self,t,loop)
 self:waters(104,82,104)
 self:disc(93,52,45,WHITE,3,.5,math.max(1,self.u*.6))
 self:building('cannon',93,52,WHITE)
 local shots=math.floor(t*4)
 self:icon('ship',150,12,9,WHITE,6)
 self:text(compact(48000-200*shots-(t*4%1>.3 and 200 or 0)),176,12,9,WHITE,7)
 for k=0,3 do
  local seed=loop*4+k
  local ang=-1+hash(seed)*2;local r=22+hash(seed+.5)*20
  local tx,ty=93+math.cos(ang)*r,52+math.sin(ang)*r
  local f=span(t,k*.25,k*.25+.08)
  if f>0 and f<1 then self:shape('shell',lerp(93,tx,f),lerp(52,ty,f),2.2,0,OUR)end
  local b=span(t,k*.25+.08,k*.25+.24)
  self:blast(tx,ty,6,b)
  if b>0 and b<1 then self:text('−200',tx,ty-9-6*b,7,BAD,9,b)end
 end
end
-- Fast reload: the fast platform fires twice for the other's once.
function scenes.reload2x(self,t,loop)
 self:waters(130)
 for row=0,1 do
  local y=row==0 and 28 or 72;local fast=row==1
  self:building('radiation',24,y,fast and GOLD or WHITE)
  self:text(fast and '×2'or '×1',24,y+12,7,fast and GOLD or WHITE,7)
  local period=fast and .5 or 1
  local phase=(t%period)/period
  self:rect(52,y+9,30,2.4,INK,4,0,.2)
  self:rect(37+15*phase,y+9,30*phase,2.4,fast and GOLD or WHITE,5)
  for k=0,(fast and 1 or 0)do
   local start=k*period;local f=span(t,start,start+.3)
   if f>0 and f<1 then self:shape('missile',lerp(34,176,f),y,1.6,0,OUR)end
   self:blast(176,y,9,span(t,start+.3,start+.48))
  end
 end
end
-- Bombers: off the airport, past a missile defence every other loop, three bombs on the mark.
function scenes.bombers(self,t,loop)
 self:waters(100,-200,62)
 self:building('plane',28,66,WHITE)
 local mx,my=160,40
 self:disc(mx,my,8,BAD,3,.2,math.max(1,self.u*.6));self:rect(mx,my,1,18,BAD,3,0,.3);self:rect(mx,my,18,1,BAD,3,0,.3)
 self:disc(128,74,28,WHITE,2,.55,math.max(1,self.u*.6));self:building('radar',128,74,WHITE)
 local downed=loop%2==1
 local fly=span(t,.05,.6)
 local x,y=lerp(34,186,fly),lerp(64,30,fly)
 local heading=math.atan2(30-64,186-34)
 local shot=span(t,.3,.38)
 if shot>0 and shot<1 then
  local bx,by=lerp(34,186,span(.34,.05,.6)),lerp(64,30,span(.34,.05,.6))
  self:rect(lerp(128,downed and bx or bx+14,shot),lerp(74,downed and by or by-10,shot),2,2,WHITE,8)
 end
 if downed and t>=.38 then
  local p=span(t,.38,.5);local bx,by=lerp(34,186,span(.38,.05,.6)),lerp(64,30,span(.38,.05,.6))
  if p<1 then self:disc(bx,by,6*(.4+.6*p),WHITE,8,.2+.8*p)end
  self:text('Shot down',128,58,7,BAD,9,span(t,.7,.9))
  return
 end
 if t>.38 and t<.6 then self:text('Missed',128,58,7,GOOD,9)end
 if fly>0 and fly<1 then self:shape('bomber',x,y,1.5,heading,OUR)end
 local keep=1-span(t,.95,1)
 for k=-1,1 do
  local tx,ty=mx+k*10,my+k*3
  local f=span(t,.45+k*.03,.55+k*.03)
  if f>0 and f<1 then self:rect(lerp(tx-12,tx,f),lerp(ty-6,ty,f),2.2,2.2,INK,7)end
  self:hole(tx,ty,6,span(t,.55+k*.03,.6+k*.03)*keep);self:blast(tx,ty,8,span(t,.55+k*.03,.78+k*.03))
 end
end

function D:step(clock)
 -- (in the frame's own units: a window's UIScale scales everything placed here once more)
 local size=Vector2.new(self.frame.Size.X.Offset,self.frame.Size.Y.Offset)
 if size.X<4 or size.Y<4 then size=self.frame.AbsoluteSize end
 if size.X<4 or size.Y<4 then return end
 self.u=size.Y/100;self.ox=(size.X-200*self.u)/2;self.oy=0
 self.nr,self.nd,self.ni,self.nt=0,0,0,0
 local loop=math.floor(clock/LOOP);local t=(clock%LOOP)/LOOP
 local scene=scenes[self.key]
 if scene then scene(self,t,loop)end
 for i=self.nr+1,#self.rects do self.rects[i].Visible=false end
 for i=self.nd+1,#self.discs do self.discs[i].Visible=false end
 for i=self.ni+1,#self.icons do self.icons[i].Visible=false end
 for i=self.nt+1,#self.texts do self.texts[i].Visible=false end
end
D.has=function(key)return scenes[key]~=nil end
return D
