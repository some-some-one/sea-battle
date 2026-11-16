--!nonstrict
-- A new player's first match (2026-11-16, by the author's request: like RoWorld, a newcomer goes
-- straight from the lobby into a solo match on Easy and is shown what to tap; ideas only, our own code).
-- The lobby starts it (Lobby: a profile with no match played and no tutorial seen, on a lobby server).
-- One small goal at a time:
--   * spawn  — the start banner is up, so no card: a white mark on a roomy free coast (the camera flies
--              there); after SPAWN_AUTO seconds that coast is taken for the player;
--   * expand — "Tap the open sea next to you": the mark on neutral water a few cells out;
--   * attack — "Tap a neighbour's water, then Attack" once somebody borders the player (on a touch
--              screen the mark moves to the card's Attack button); passed over when nobody comes;
--   * port   — the mark on the port's tile (on a phone first on Build), then on the player's coast;
--              the gold for it is topped up (a solo match runs on this device);
--   * a green card: the player is ready, and how a match is won.
-- The card sits at the top centre with "1 / 3" and Skip. A step nobody finishes in STEP_MAX seconds is
-- passed over, so nobody is ever stuck. The texts are plain English sentences without names or numbers
-- in them, so Roblox's automatic translation can translate them whole.
-- When it ends (done, skipped or the match left) the server notes it (Account "tutorial"), and the
-- lobby never starts it again.
local TweenService=game:GetService("TweenService")
local UIS=game:GetService("UserInputService")
local Kit=require(script.Parent.Kit)
local Theme=require(script.Parent.Theme)
local R=require(script.Parent.NavalRules)
local make,corner,stroke=Kit.make,Kit.corner,Kit.stroke

local T={};T.__index=T
T.STEP_MAX=75        -- seconds on a step before it is passed over
T.SPAWN_AUTO=15      -- seconds on the spawn step before the marked coast is taken for the player
T.CONTACT_WAIT=40    -- seconds on the attack step without any neighbour before it is passed over
T.DONE_FLASH=.9      -- the card stays green this long after a step
T.END_SHOW=7         -- the last card
local Z=88
local WHITE=Color3.new(1,1,1)
local INK=Color3.fromRGB(9,18,27)
local GREEN=Color3.fromRGB(96,214,140)
local STEPS={
 {id='spawn'},
 {id='expand',touch='Tap the open sea next to your country to grow',desktop='Click the open sea next to your country to grow'},
 {id='attack',touch="Tap a neighbour's water, then tap Attack",desktop="Click a neighbour's water to attack it",
  wait='Keep growing until you meet a neighbour'},
 {id='port',touch='Build a port: tap the marked button',desktop='Build a port: click the marked button',
  place='Now tap your coast to build the port',placeDesktop='Now click your coast to build the port'},
}
local COUNTED=#STEPS-1 -- the spawn step has no card

local function touchScreen()return UIS.TouchEnabled and not UIS.KeyboardEnabled end

function T.new(view)
 local self=setmetatable({v=view,active=false,i=0,t=0,flash=0,ending=0},T)
 local gui=view.gui
 -- The mark: two white rings closing on a white dot (a finger coming down), "Tap here" under it.
 local function ring(parent)
  local r=corner(make('Frame',parent,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z}),999)
  make('UIStroke',r,{Name='Line',Color=WHITE,Thickness=3,Transparency=1})
  return r
 end
 local mark=make('Frame',gui,{Name='TutorialMark',BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(0,0),Visible=false,ZIndex=Z})
 self.mark=mark
 self.ringA,self.ringB=ring(mark),ring(mark)
 self.dot=corner(make('Frame',mark,{BackgroundColor3=WHITE,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(14,14),ZIndex=Z+1}),999)
 make('UIStroke',self.dot,{Color=INK,Thickness=1.5,Transparency=.45})
 self.tap=make('TextLabel',mark,{BackgroundColor3=INK,BackgroundTransparency=.12,Text='Tap here',TextSize=13,FontFace=Theme.font(Enum.FontWeight.Bold),
  TextColor3=WHITE,AutomaticSize=Enum.AutomaticSize.XY,AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,.5,30),Size=UDim2.fromOffset(0,0),ZIndex=Z+1})
 corner(self.tap,999)
 make('UIPadding',self.tap,{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,4)})
 -- The card: "1 / 3", one line, Skip.
 local card=corner(make('Frame',gui,{Name='TutorialCard',AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,12),Size=UDim2.fromOffset(440,52),
  BackgroundColor3=Color3.fromRGB(20,34,45),BackgroundTransparency=.04,Visible=false,Active=true,ZIndex=Z}),16)
 self.card=card
 self.cardStroke=stroke(card,WHITE,.55,1.5)
 self.cardScale=make('UIScale',card,{Scale=1})
 self.count=make('TextLabel',card,{BackgroundTransparency=1,Text='1 / 3',TextSize=13,FontFace=Theme.font(Enum.FontWeight.Heavy),TextColor3=WHITE,
  Position=UDim2.fromOffset(14,0),Size=UDim2.new(0,40,1,0),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=Z+1})
 self.text=make('TextLabel',card,{BackgroundTransparency=1,Text='',TextSize=15,FontFace=Theme.font(Enum.FontWeight.Bold),TextColor3=WHITE,TextWrapped=true,
  Position=UDim2.fromOffset(58,0),Size=UDim2.new(1,-58-78,1,0),TextXAlignment=Enum.TextXAlignment.Left,ZIndex=Z+1})
 self.skip=Kit.pressable(card,{Name='Skip',BackgroundColor3=Color3.fromRGB(27,45,58),AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),
  Size=UDim2.fromOffset(62,32),ZIndex=Z+1},function()self:stop('skipped')end)
 corner(self.skip,10)
 make('TextLabel',self.skip,{BackgroundTransparency=1,Text='Skip',TextSize=13,FontFace=Theme.font(Enum.FontWeight.Bold),TextColor3=Theme.colors.muted,
  Size=UDim2.fromScale(1,1),ZIndex=Z+2})
 return self
end

-- The tutorial match was started (the lobby starts the solo match itself).
function T:begin()
 self.active=true;self.i=0;self.ending=0;self.flash=0
 self:advance()
end
-- how: 'done' | 'skipped' | 'left'. Noted on the server once; the last card stays a moment after 'done'.
function T:stop(how)
 if not self.active then return end
 self.active=false;self.mark.Visible=false
 if how=='done'then
  self.ending=T.END_SHOW
  self.count.Text=''
  self.text.Text='You are ready! Hold '..math.floor(R.WinShare*100+.5)..'% of the sea to win.'
  self:tint(GREEN);self.skip.Visible=false;self.card.Visible=true;self:pop()
 else self.card.Visible=false end
 local v=self.v
 task.spawn(function()pcall(function()v:request('tutorial',{how=how})end)end)
end
function T:pop()
 self.cardScale.Scale=.92
 TweenService:Create(self.cardScale,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
end
function T:tint(color)self.cardStroke.Color=color;self.cardStroke.Transparency=color==WHITE and .55 or .1;self.count.TextColor3=color end
function T:step()return STEPS[self.i]end
function T:advance()
 self.i+=1;self.t=0;self.sent=nil;self.target=nil;self.focused=nil;self.topped=nil;self.retarget=0
 local s=STEPS[self.i]
 if not s then self:stop('done');return end
 if s.id=='spawn'then self.card.Visible=false;return end
 self.count.Text=(self.i-1)..' / '..COUNTED
 self:tint(WHITE);self.skip.Visible=true;self.card.Visible=true;self:pop()
end
-- A step done: the card turns green for a moment, then the next step comes.
function T:complete()
 if self.flash>0 then return end
 local s=self:step();if not s then return end
 if s.id=='spawn'then self:advance();return end
 self.flash=T.DONE_FLASH;self:tint(GREEN);self.mark.Visible=false
end
-- Every order the player sends (ConquestView:send), with whether it was taken.
function T:onCommand(action,value,ok)
 if not self.active then return end
 local s=self:step();if not s then return end
 -- (the coast taken for the player was refused meanwhile: any free one)
 if s.id=='spawn'and action=='start'and not ok and self.sent and value~='random'then self.v:send('start','random')end
 if not ok then return end
 if s.id=='expand'and action=='capture'then self:complete()
 elseif s.id=='attack'and(action=='capture'or action=='break_attack')then
  local cell=type(value)=='number'and value or type(value)=='table'and value.cell
  if action=='break_attack'or(cell and self.v:owner(cell)>0 and self.v:owner(cell)~=self.v.playerId)then self:complete()end
 elseif s.id=='port'and action=='build'and type(value)=='table'and value.kind=='port'then self:complete()end
end

-- Places to point at -------------------------------------------------------------------------------
-- A free coast with room around it but a neighbour within reach: about NEIGHBOUR cells from the nearest
-- country's start (the farthest coast kept a newcomer alone past the attack step), off the polar seas.
local NEIGHBOUR=45
function T:findSpot()
 local v=self.v;local grid=v.grid;local w,h=grid.width,grid.height
 local starts={}
 for _,f in pairs(v.factions or {})do if f.alive~=false and f.startCell then table.insert(starts,f.startCell)end end
 local best,score=nil,-math.huge
 local stride=53;local offset=math.random(0,stride-1)
 for id=1+offset,grid.count,stride do
  local y=(id-1)//w
  if y<h*.18 or y>h*.8 or not grid:isWater(id)or not v:isCoast(id)or v:owner(id)~=0 then continue end
  local x=(id-1)%w;local near=math.huge
  for _,s in ipairs(starts)do
   local dx=math.abs(x-(s-1)%w);if grid.data.wrapX then dx=math.min(dx,w-dx)end
   local dy=y-(s-1)//w;near=math.min(near,dx*dx+dy*dy)
  end
  local value=-math.abs(math.sqrt(near)-NEIGHBOUR)+math.random()*6
  if value>score then best,score=id,value end
 end
 return best
end
-- Neutral water about six cells out from the player's border.
function T:expandTarget(me)
 local v=self.v;local grid=v.grid;local owned=v.owned[me];if not owned then return nil end
 local q,dist,head={},{},1
 for id in pairs(owned)do
  local a,b,c,d=grid:nb4(id)
  for k=1,4 do
   local n=k==1 and a or k==2 and b or k==3 and c or d
   if n>0 and dist[n]==nil and grid:isWater(n)and v:owner(n)==0 then dist[n]=1;q[#q+1]=n end
  end
  if #q>600 then break end
 end
 while head<=#q and head<5000 do
  local id=q[head];head+=1;local dd=dist[id]
  if dd>=6 then return id end
  local a,b,c,d=grid:nb4(id)
  for k=1,4 do
   local n=k==1 and a or k==2 and b or k==3 and c or d
   if n>0 and dist[n]==nil and grid:isWater(n)and v:owner(n)==0 then dist[n]=dd+1;q[#q+1]=n end
  end
 end
 return q[#q]
end
-- Water of a country next to the player (not an ally).
function T:neighbourCell(me)
 local v=self.v;local grid=v.grid;local owned=v.owned[me];if not owned then return nil end
 local ui=v.battleUI;local checked=0
 for id in pairs(owned)do
  checked+=1;if checked>20000 then break end
  local a,b,c,d=grid:nb4(id)
  for k=1,4 do
   local n=k==1 and a or k==2 and b or k==3 and c or d
   local o=n>0 and v:owner(n)or 0
   if o>0 and o~=me and not(ui and ui:allied(o))then return n end
  end
 end
 return nil
end
-- Land beside the player's water, for the port.
function T:coastLand(me)
 local v=self.v;local grid=v.grid;local f=v.factions[me];local owned=v.owned[me];if not owned then return nil end
 local function landBeside(id)
  local a,b,c,d=grid:nb4(id)
  for k=1,4 do local n=k==1 and a or k==2 and b or k==3 and c or d;if n>0 and not grid:isWater(n)then return n end end
 end
 if f and f.startCell and owned[f.startCell]then local n=landBeside(f.startCell);if n then return n end end
 local checked=0
 for id in pairs(owned)do checked+=1;if checked>20000 then break end;local n=landBeside(id);if n then return n end end
 return nil
end
-- The control the port step points at: the port's tile, or on a phone first the Build button.
function T:portControl()
 local bar=self.v.battleUI and self.v.battleUI.bar;if not bar then return nil end
 local trayOpen=bar.tray and bar.tray.Visible
 for _,t in ipairs(bar.tiles.Build_port or {})do
  if t.desktop and bar.root.Visible then return t.button end
  if not t.desktop and trayOpen then return t.button end
 end
 if bar.strip and bar.strip.Visible and bar.pBuild then return bar.pBuild end
 return nil
end
function T:cardAttack()
 local ui=self.v.battleUI;if not(ui and ui.card.Visible)then return nil end
 for _,b in ipairs(ui.cardButtons)do if b.Visible and b.Text=='Attack'then return b end end
 return nil
end
function T:focus(cell,zoom)
 if not cell then return end
 local gui=self.v.gui
 if zoom then gui:SetAttribute('FocusZoom',zoom)end
 gui:SetAttribute('FocusCell',nil);gui:SetAttribute('FocusCell',cell)
end

-- Drawing the mark ----------------------------------------------------------------------------------
-- On a map cell (the marks layer, where WorldToScreenPoint counts from) or on a control (the main
-- layer): a control gets rings closing onto its edge and no dot.
function T:draw(cell,control)
 local v=self.v;local mark=self.mark
 local p,around
 if control then
  if mark.Parent~=v.gui then mark.Parent=v.gui end
  local pos=control.AbsolutePosition+control.AbsoluteSize/2-v.gui.AbsolutePosition
  p=pos;around=math.max(control.AbsoluteSize.X,control.AbsoluteSize.Y)/2
 elseif cell then
  if mark.Parent~=v.marks then mark.Parent=v.marks end
  local c=v.grid:getCell(cell);if not c then mark.Visible=false;return end
  local s,on=workspace.CurrentCamera:WorldToScreenPoint(v.grid:cellToWorld(c.x,c.y))
  if not on then mark.Visible=false;return end
  p=Vector2.new(s.X,s.Y)
 else mark.Visible=false;return end
 mark.Position=UDim2.fromOffset(math.floor(p.X+.5),math.floor(p.Y+.5));mark.Visible=true
 -- Two rings, half a beat apart, closing from wide onto the spot and fading in as they close.
 local inner=around and around+3 or 9
 local outer=around and around+22 or 34
 local beat=os.clock()%1.2/1.2
 for k,r in ipairs({self.ringA,self.ringB})do
  local e=(beat+(k-1)*.5)%1
  local d=(outer-(outer-inner)*e)*2
  r.Size=UDim2.fromOffset(d,d)
  r.Line.Transparency=1-math.sin(e*math.pi)*.9
 end
 self.dot.Visible=around==nil
 local pulse=1+math.sin(os.clock()*6)*.08
 self.dot.Size=UDim2.fromOffset(math.floor(14*pulse),math.floor(14*pulse))
 self.tap.Text=touchScreen()and 'Tap here'or 'Click here'
 -- (under a spot; above a control at the bottom of the screen)
 local low=control and p.Y>v.gui.AbsoluteSize.Y*.6
 self.tap.AnchorPoint=Vector2.new(.5,low and 1 or 0)
 local gap=(around or 0)+(around and 26 or 30)
 self.tap.Position=UDim2.new(.5,0,.5,low and -gap or gap)
end

function T:say(text)if self.text.Text~=text then self.text.Text=text end end
-- The card at the top centre: on a phone under Roblox's top bar (the status line is up in it), on a
-- computer beside the status panel, or under it when the window is too narrow for both.
function T:layout()
 local v=self.v;local size=v.gui.AbsoluteSize
 if size==self.laidOut then return end
 self.laidOut=size
 local w=math.min(440,size.X-24)
 local y=12
 if not v.compact and size.X/2-w/2<24+420+12 then y=92 end
 self.card.Size=UDim2.fromOffset(w,v.compact and 50 or 54);self.card.Position=UDim2.new(.5,0,0,y)
 self.text.TextSize=v.compact and 14 or 15
end

-- Every frame (Lobby:update).
function T:update(dt,lobby)
 if self.card.Visible then self:layout()end
 if self.ending>0 then
  self.ending-=dt
  if self.ending<=0 then self.card.Visible=false end
 end
 if not self.active then return end
 local v=self.v;local s=self:step();if not s then return end
 -- The tutorial's match left (back to the lobby, another match) or over: it ends here.
 local inSolo=lobby.playing=='solo'and v.source=='solo'
 if s.id~='spawn'and(not inSolo or v.phase=='finished'or not v.playerId)then self:stop('left');return end
 if s.id=='spawn'and lobby.mode~='spawn'and not v.playerId then
  if lobby.playing~='solo'then self:stop('left')end
  return
 end
 self.t+=dt
 if self.flash>0 then
  self.flash-=dt
  if self.flash<=0 then self.flash=0;self:advance()end
  return
 end
 if self.t>T.STEP_MAX then self:advance();return end
 local touch=touchScreen();local me=v.playerId
 if s.id=='spawn'then
  if me then self:complete();return end
  -- (until the solo match's own state is here the map still shows the lobby's demo)
  if v.source~='solo'then self.mark.Visible=false;return end
  if not self.target or v:owner(self.target)~=0 then self.target=self:findSpot()end
  if self.target and not self.focused then self.focused=true;self:focus(self.target,.22)end
  if self.t>T.SPAWN_AUTO and not self.sent then
   self.sent=true;v:send('start',self.target or 'random')
  end
  self:draw(self.target)
 elseif s.id=='expand'then
  self:say(touch and s.touch or s.desktop)
  self.retarget-=dt
  if not self.target or v:owner(self.target)~=0 or self.retarget<=0 then self.target=self:expandTarget(me);self.retarget=3 end
  self:draw(self.target)
 elseif s.id=='attack'then
  self.retarget-=dt
  if not self.target or v:owner(self.target)==0 or v:owner(self.target)==me or self.retarget<=0 then self.target=self:neighbourCell(me);self.retarget=2 end
  if not self.target then
   self:say(s.wait)
   if self.t>T.CONTACT_WAIT then self:advance();return end
   self.expandAt=self.expandAt and v:owner(self.expandAt)==0 and self.expandAt or self:expandTarget(me)
   self:draw(self.expandAt)
  else
   self:say(touch and s.touch or s.desktop)
   if not self.focused then self.focused=true;self:focus(self.target,.18)end
   local button=touch and self:cardAttack()
   if button then self:draw(nil,button)else self:draw(self.target)end
  end
 elseif s.id=='port'then
  -- (a solo match runs here: the gold for one port, if the country has less)
  if not self.topped then
   self.topped=true
   local lm=v.localMatch;local g=lm and lm.game;local id=g and g.clients[lm.user];local f=id and g.factions[id]
   if f and lm.kind=='solo'then local price=v.battleUI:price('build','port');if(f.gold or 0)<price then f.gold=price end end
  end
  local mode=v.battleUI and v.battleUI.mode
  if mode and mode.action=='build'and mode.kind=='port'then
   self:say(touch and s.place or s.placeDesktop)
   if not self.target or v:owner(self.target)~=0 then self.target=self:coastLand(me)end
   self:draw(self.target)
  else
   self:say(touch and s.touch or s.desktop)
   self:draw(nil,self:portControl())
  end
 end
end
-- (the card and the mark take no map taps: the lobby asks this for every tap)
function T:isUI(obj)
 return self.card.Visible and(obj==self.card or obj:IsDescendantOf(self.card))
end
return T
