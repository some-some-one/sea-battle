--!nonstrict
-- The daily reward window of the lobby: seven cells (taken ones ticked, today's lit and pulsing, the
-- rest dimmed, a prize on the seventh), one button to take today's reward, and the time to the next one.
-- A computer shows the seven in a row; a phone shows 4 + 3 with large icons and little text.
-- The rules are shared/Daily; the server gives the reward (command "daily_claim").
local Kit=require(script.Parent.Kit)
local Icons=require(script.Parent.Icons)
local Daily=require(script.Parent.Daily)
local Sfx=require(script.Parent.Sfx)
local compact=require(script.Parent.NumberFormat).compact
local C,make,corner,stroke,label,pressable=Kit.C,Kit.make,Kit.corner,Kit.stroke,Kit.label,Kit.pressable

local D={};D.__index=D
local Z=50
function D.new(lobby)
 local self=setmetatable({lobby=lobby,v=lobby.v,open=false,busy=false,clock=0,note=nil},D)
 local w=Kit.window(lobby.root,'Daily',Z,560,270,function()self:show(false)end)
 self.shade,self.card,self.scale=w.shade,w.card,w.scale
 self.badge=Kit.badge(self.card,'gift',40,C.amber,UDim2.fromOffset(20,16))
 self.title=label(self.card,'DAILY REWARD',19,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(72,14),Size=UDim2.new(1,-130,0,24)})
 self.sub=label(self.card,'Come back every day: a prize waits on day seven',13,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(72,38),Size=UDim2.new(1,-130,0,18)})
 self.cells={}
 for i=1,7 do
  local cell=corner(make('Frame',self.card,{Name='Day'..i,BackgroundColor3=C.tile,ZIndex=Z+2}),12)
  local c={frame=cell,stroke=stroke(cell,C.white,.85,1),scale=make('UIScale',cell,{Scale=1})}
  c.day=label(cell,'',11,Enum.FontWeight.Bold,C.muted,{Size=UDim2.new(1,0,0,16),Position=UDim2.fromOffset(0,6),TextXAlignment=Enum.TextXAlignment.Center})
  c.icon=Icons.image(cell,i==7 and 'gift'or 'coins',26,i==7 and C.amber or C.silver,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.46),ZIndex=Z+3})
  c.amount=label(cell,compact(Daily.Rewards[i]),14,Enum.FontWeight.Heavy,C.text,{AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,0,1,-6),Size=UDim2.new(1,0,0,18),TextXAlignment=Enum.TextXAlignment.Center})
  -- A tick over a taken day.
  c.done=corner(make('Frame',cell,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,14,.46,10),Size=UDim2.fromOffset(18,18),BackgroundColor3=C.accent,Visible=false,ZIndex=Z+4}),9)
  Icons.image(c.done,'check',11,C.ink,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+5})
  self.cells[i]=c
 end
 self.button=pressable(self.card,{Name='Claim',ZIndex=Z+2},function()self:claim()end)
 corner(self.button,14);Kit.primary(self.button)
 self.buttonText=label(self.button,'Claim',17,Enum.FontWeight.Heavy,C.dark,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
 -- (shown in place of the button once today's reward is taken)
 self.wait=label(self.card,'',14,Enum.FontWeight.Bold,C.muted,{TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+2})
 Icons.lead(self.wait,'clock',{size=16,gap=7})
 return self
end
function D:state()
 local p=self.v.profile;if not p or type(p.daily)~='table'then return nil end
 return Daily.state(p.daily,Daily.day(workspace:GetServerTimeNow())),workspace:GetServerTimeNow()
end
-- True while today's reward waits (the lobby lights its button's dot with it).
function D:canClaim()local s=self:state();return s~=nil and s.canClaim end
function D:layout(size)
 local phone=self.lobby.phone==true
 if self.lastSize==size and self.lastPhone==phone then return end
 self.lastSize=size;self.lastPhone=phone
 local W,H,top
 if phone then
  -- 4 + 3, large cells, no subtitle.
  local cw,ch,g,pad=74,78,8,18
  W=pad*2+cw*4+g*3;top=64
  for i,c in ipairs(self.cells)do
   local row=i<=4 and 0 or 1;local col=row==0 and i-1 or i-5
   local x=row==0 and pad+col*(cw+g)or pad+(W-pad*2-(cw*3+g*2))/2+col*(cw+g)
   c.frame.Position=UDim2.fromOffset(x,top+row*(ch+g));c.frame.Size=UDim2.fromOffset(cw,ch)
   c.day.Text=tostring(i);c.icon.Size=UDim2.fromOffset(30,30)
  end
  H=top+ch*2+g+12+46+16
  self.button.Position=UDim2.fromOffset(pad,H-46-16);self.button.Size=UDim2.fromOffset(W-pad*2,46)
 else
  local cw,ch,g,pad=64,92,8,24
  W=pad*2+cw*7+g*6;top=74
  for i,c in ipairs(self.cells)do
   c.frame.Position=UDim2.fromOffset(pad+(i-1)*(cw+g),top);c.frame.Size=UDim2.fromOffset(cw,ch)
   c.day.Text='DAY '..i;c.icon.Size=UDim2.fromOffset(26,26)
  end
  H=top+ch+16+50+20
  self.button.Position=UDim2.fromOffset(pad,H-50-20);self.button.Size=UDim2.fromOffset(W-pad*2,50)
 end
 self.sub.Visible=not phone
 self.title.Position=UDim2.fromOffset(72,phone and 22 or 14)
 self.wait.Position=self.button.Position;self.wait.Size=self.button.Size
 self.card.Size=UDim2.fromOffset(W,H)
 self.fit=math.clamp(math.min((size.X-24)/W,(size.Y-24)/H),.5,1.25);self.scale.Scale=self.fit
 Kit.belowTopbar(self.card)
end
function D:show(open)
 open=open==true
 if open==self.open then return end
 self.open=open;self.shade.Visible=open;self.card.Visible=open
 if open then
  self.note=nil;self.lastSize=nil;self:layout(self.v.gui.AbsoluteSize)
  self.scale.Scale=(self.fit or 1)*.92;game:GetService('TweenService'):Create(self.scale,Kit.POP,{Scale=self.fit or 1}):Play()
 end
end
function D:claim()
 if self.busy or not self:canClaim()then return end
 self.busy=true
 task.spawn(function()
  local r=self.v:request('daily_claim')
  self.busy=false
  if r.ok and r.reward then
   Sfx.play('build')
   local reward=r.reward
   local item=reward.item and require(script.Parent.Catalog).Cosmetics[reward.item]
   self.note='+'..compact(reward.total or reward.silver)..' silver'..(item and(' · prize: '..item.title)or'')
   self.noteUntil=os.clock()+6
  elseif r.reason=='claimed'then self.note='Today\'s reward is already claimed'
  else self.note='Could not claim the reward. Try again.';self.noteUntil=os.clock()+4 end
 end)
end
-- Every frame while the lobby's menu is shown.
function D:update(dt)
 if not self.open then return end
 self.clock+=dt
 self:layout(self.v.gui.AbsoluteSize)
 local s,now=self:state()
 if not s then self.button.Visible=false;self.wait.Visible=true;self.wait.Text='Loading…';return end
 for i,c in ipairs(self.cells)do
  local taken=i<=s.claimed;local today=s.canClaim and i==s.day
  c.done.Visible=taken
  c.frame.BackgroundColor3=today and C.tileOn or C.tile
  c.frame.BackgroundTransparency=(taken or today)and 0 or .35
  c.stroke.Color=today and C.amber or taken and C.accent or C.white
  c.stroke.Transparency=today and 0 or taken and .5 or .88;c.stroke.Thickness=today and 2 or 1
  c.icon.ImageTransparency=(taken or today)and 0 or .45
  c.amount.TextTransparency=(taken or today)and 0 or .45;c.day.TextTransparency=(taken or today)and 0 or .3
  -- Today's cell breathes.
  c.scale.Scale=today and 1+.035*math.sin(self.clock*4)or 1
 end
 self.button.Visible=s.canClaim;self.button.Active=not self.busy
 self.wait.Visible=not s.canClaim
 self.buttonText.Text=self.busy and 'Claiming…'or('Claim '..compact(s.silver)..(s.prize and ' + prize'or''))
 if not s.canClaim then
  local note=self.note and os.clock()<(self.noteUntil or 0)and self.note
  self.wait.Text=note or('Next reward in '..Kit.countdown((s.nextAt or now)-now))
  self.wait.TextColor3=note and C.amber or C.muted
 end
end
function D:isUI(obj)
 return self.open and(obj==self.shade or obj==self.card or obj:IsDescendantOf(self.card))
end
return D
