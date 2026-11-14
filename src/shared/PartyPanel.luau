--!nonstrict
-- The lobby's party (2026-11-14, by the author's request; the server side is server/Party): a separate
-- button at the top right of the lobby ("Party" and how many are in it; a round button on a phone)
-- opens a panel under it:
--  * the party, up to R.PartySize people: avatar, name, a star for the leader; the leader can remove others;
--  * an invite waiting for this player: accept or decline;
--  * Roblox friends on this server and friends in the game on other lobby servers (GetFriendsOnline,
--    asked every 30 s), each with "Invite": the invite pops up in their game, and accepting it brings
--    them to this server, into this party;
--  * "Invite friends": Roblox's own invite (it lands in the Roblox notifications); the friend who
--    follows it arrives on this server, in this party;
--  * "Leave party".
-- Only the leader searches for an online match; the whole party goes into the same one.
local Players=game:GetService("Players")
local SocialService=game:GetService("SocialService")
local TweenService=game:GetService("TweenService")
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local R=require(script.Parent.NavalRules)

local P={};P.__index=P
local C={ink=Color3.fromRGB(9,18,27),card=Color3.fromRGB(20,34,45),tile=Color3.fromRGB(27,45,58),accent=Theme.colors.accent,
 text=Theme.colors.text,muted=Theme.colors.muted,amber=Color3.fromRGB(255,206,96),red=Color3.fromRGB(150,52,48),
 dark=Color3.fromRGB(10,30,30),white=Color3.new(1,1,1),blue=Color3.fromRGB(86,156,255)}
local QUICK=TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local POP=TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
local W=320
local Z=44

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
  TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=Z+2})
 for k,v in pairs(props or {})do o[k]=v end
 return o
end
local function button(parent,props,onClick)
 local b=make('TextButton',parent,{Text='',AutoButtonColor=false,BorderSizePixel=0,ZIndex=Z+2})
 for k,v in pairs(props or {})do b[k]=v end
 local scale=make('UIScale',b,{Scale=1})
 local function to(v)TweenService:Create(scale,QUICK,{Scale=v}):Play()end
 b.MouseEnter:Connect(function()if b.Active then to(1.04)end end)
 b.MouseLeave:Connect(function()to(1)end)
 b.MouseButton1Down:Connect(function()if b.Active then to(.95)end end)
 b.MouseButton1Up:Connect(function()to(1)end)
 b.Activated:Connect(function()if b.Active then onClick()end end)
 return b
end
-- A small text button (Invite, Accept, …).
local function chip(parent,text,bg,fg,w,onClick)
 local b=corner(button(parent,{BackgroundColor3=bg,Size=UDim2.fromOffset(w,30)},onClick),9)
 label(b,text,13,Enum.FontWeight.Bold,fg,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+3})
 return b
end
local function avatar(parent,userId,size,x)
 local a=corner(make('ImageLabel',parent,{BackgroundColor3=C.ink,Size=UDim2.fromOffset(size,size),Position=UDim2.new(0,x,.5,-size/2),
  Image=string.format('rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48',userId),ZIndex=Z+3}),size/2)
 stroke(a,C.white,.8,1)
 return a
end

function P.new(lobby)
 local self=setmetatable({lobby=lobby,v=lobby.v,open=false,state={members={},friends={},max=R.PartySize,leader=true}},P)
 local root=lobby.root
 -- The button at the top right.
 self.button=corner(button(root,{Name='PartyButton',BackgroundColor3=C.card,BackgroundTransparency=.04,AnchorPoint=Vector2.new(1,0),
  Size=UDim2.fromOffset(156,44),ZIndex=Z},function()self:setOpen(not self.open)end),22)
 stroke(self.button,C.blue,.35,1.5)
 self.buttonIcon=Icons.image(self.button,'people',22,C.blue,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,14,.5,0),ZIndex=Z+1})
 self.buttonText=label(self.button,'Party',15,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(44,0),Size=UDim2.new(1,-96,1,0),ZIndex=Z+1})
 self.count=corner(make('Frame',self.button,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-8,.5,0),Size=UDim2.fromOffset(40,26),
  BackgroundColor3=C.ink,BackgroundTransparency=.2,ZIndex=Z+1}),13)
 self.countText=label(self.count,'1/'..R.PartySize,13,Enum.FontWeight.Heavy,C.text,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+2})
 self.dot=corner(make('Frame',self.button,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,2,0,-2),Size=UDim2.fromOffset(12,12),
  BackgroundColor3=Color3.fromRGB(240,70,70),Visible=false,ZIndex=Z+3}),6)
 -- The panel under it.
 self.panel=corner(make('Frame',root,{Name='PartyPanel',AnchorPoint=Vector2.new(1,0),BackgroundColor3=C.card,BackgroundTransparency=.03,
  Size=UDim2.fromOffset(W,200),Visible=false,Active=true,ZIndex=Z}),16)
 stroke(self.panel,C.white,.84,1)
 self.panelScale=make('UIScale',self.panel,{Scale=1})
 label(self.panel,'PARTY',17,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(16,12),Size=UDim2.fromOffset(160,24)})
 self.size=label(self.panel,'',13,Enum.FontWeight.Bold,C.muted,{Position=UDim2.fromOffset(104,13),Size=UDim2.fromOffset(80,24)})
 local close=corner(button(self.panel,{BackgroundColor3=C.tile,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,10),Size=UDim2.fromOffset(30,30)},
  function()self:setOpen(false)end),15)
 Icons.image(close,'close',14,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+3})
 label(self.panel,'The leader searches for an online match, and the whole party joins the same one.',12,Enum.FontWeight.Medium,C.muted,
  {Position=UDim2.fromOffset(16,38),Size=UDim2.new(1,-32,0,30),TextWrapped=true,TextTruncate=Enum.TextTruncate.None,TextYAlignment=Enum.TextYAlignment.Top})
 self.body=make('ScrollingFrame',self.panel,{BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(12,72),Size=UDim2.new(1,-24,1,-84),
  ScrollBarThickness=4,ScrollBarImageColor3=C.muted,ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.Y,
  CanvasSize=UDim2.new(),ZIndex=Z+1})
 self.list=make('UIListLayout',self.body,{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
 -- The server sends the party after every change; ask once for the first view.
 task.spawn(function()
  local api=game.ReplicatedStorage.SeaBattle:WaitForChild("ConquestAPI")
  api:WaitForChild("Party").OnClientEvent:Connect(function(st)if type(st)=='table'then self.state=st;self.dirty=true end end)
  task.wait(1)
  if lobby:role()=="hub"then self.v:request('party',{op='view'})end
  -- Friends in this game on other servers, for the "IN THE GAME" list (every 30 s, sooner with the panel open).
  while true do
   if lobby:role()=="hub"then self:sendOnline()end
   local waited=0
   repeat task.wait(1);waited+=1 until waited>=30 or(self.open and not self.wasOpen)
   self.wasOpen=self.open
  end
 end)
 return self
end
function P:sendOnline()
 local me=Players.LocalPlayer
 local ok,list=pcall(me.GetFriendsOnline,me,50)
 if not ok or type(list)~='table'then return end
 local out={}
 for _,f in ipairs(list)do
  if f.LocationType==4 and f.PlaceId==game.PlaceId and f.GameId~=game.JobId and f.VisitorId then
   table.insert(out,{u=f.VisitorId,name=f.DisplayName or f.UserName})
  end
 end
 local key=game:GetService('HttpService'):JSONEncode(out)
 if key==self.onlineKey then return end
 self.onlineKey=key
 self.v:request('party',{op='online',list=out})
end
function P:inParty()return #(self.state.members or {})>1 end
function P:isLeader()return self.state.leader~=false end
function P:setOpen(open)
 self.open=open==true
 self.panel.Visible=self.open
 if self.open then
  self.dirty=true
  self.panelScale.Scale=(self.fit or 1)*.94;TweenService:Create(self.panelScale,POP,{Scale=self.fit or 1}):Play()
 end
end
function P:send(op,user)
 task.spawn(function()
  local r=self.v:request('party',{op=op,user=user})
  local note
  if r and not r.ok then
   note=({party_full='The party already has '..R.PartySize..' people.',expired='This invite is no longer valid.',slow_down='Wait a couple of seconds.',
    not_friends='You can only invite your Roblox friends.',send_failed='Could not send the invite. Try again.'})[r.reason]
  elseif r and r.ok and r.reason=='moving'then
   note='Moving to your friend\'s server…'
  end
  if note then self.note=note;self.noteAt=os.clock();self.dirty=true end
 end)
end
-- Roblox's own invite: the friend comes to this server and joins this party (the launch data).
function P:inviteFriends()
 task.spawn(function()
  local me=Players.LocalPlayer
  local okCan,can=pcall(SocialService.CanSendGameInviteAsync,SocialService,me)
  if okCan and can==false then self.note='Roblox does not allow sending an invite right now.';self.noteAt=os.clock();self.dirty=true;return end
  local options=Instance.new('ExperienceInviteOptions')
  options.PromptMessage='Join my party in Sea Battle!'
  options.LaunchData='party:'..me.UserId
  local ok=pcall(SocialService.PromptGameInvite,SocialService,me,options)
  if not ok then self.note='Could not open the Roblox invite.'
  else self.note='The Roblox invite goes to your friend\'s Roblox notifications. Friends already in the game are easier to invite from the list below.'end
  self.noteAt=os.clock();self.dirty=true
 end)
end
-- Everything in the panel, built again after each change.
function P:rebuild()
 for _,c in ipairs(self.body:GetChildren())do if not c:IsA('UIListLayout')then c:Destroy()end end
 local st=self.state;local order=0
 local function add(o)order+=1;o.LayoutOrder=order;return o end
 local function row(h,bg)
  return add(corner(make('Frame',self.body,{BackgroundColor3=bg or C.tile,BackgroundTransparency=bg and 0 or .2,Size=UDim2.new(1,-6,0,h),ZIndex=Z+2}),10))
 end
 local function heading(text)add(label(self.body,text,12,Enum.FontWeight.Heavy,C.muted,{Size=UDim2.new(1,-6,0,20)}))end
 self.size.Text=#st.members..' / '..(st.max or R.PartySize)
 -- An invite for this player.
 if st.invite then
  local r=row(78,Color3.fromRGB(30,58,84))
  avatar(r,st.invite.u,32,10).Position=UDim2.fromOffset(10,8)
  label(r,st.invite.name..' invites you to a party',13,Enum.FontWeight.Bold,C.text,{Position=UDim2.fromOffset(50,8),Size=UDim2.new(1,-60,0,32),
   TextWrapped=true,TextTruncate=Enum.TextTruncate.None})
  chip(r,'Accept',C.accent,C.dark,110,function()self:send('accept',st.invite.u)end).Position=UDim2.fromOffset(50,42)
  chip(r,'No',C.tile,C.text,70,function()self:send('decline')end).Position=UDim2.fromOffset(168,42)
 end
 -- The party.
 heading(self:inParty()and 'IN THE PARTY' or 'JUST YOU FOR NOW')
 for _,m in ipairs(st.members)do
  local r=row(44)
  avatar(r,m.u,32,8)
  local name=label(r,m.name..(m.me and ' (you)'or ''),14,Enum.FontWeight.Bold,C.text,{Position=UDim2.fromOffset(48,0),Size=UDim2.new(1,-100,1,0)})
  if m.leader then
   Icons.image(r,'star',16,C.amber,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,self:isLeader()and not m.me and -46 or -12,.5,0),ZIndex=Z+3})
   name.Size=UDim2.new(1,-120,1,0)
  end
  if self:isLeader()and self:inParty()and not m.me then
   local k=corner(button(r,{BackgroundColor3=C.red,AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-8,.5,0),Size=UDim2.fromOffset(28,28)},
    function()self:send('kick',m.u)end),14)
   Icons.image(k,'close',12,C.white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=Z+4})
  end
 end
 if self:inParty()and not self:isLeader()then
  add(label(self.body,'The leader (star) starts online matches.',12,Enum.FontWeight.Medium,C.amber,{Size=UDim2.new(1,-6,0,18)}))
 end
 -- Invite: Roblox's prompt (only while there is room).
 local full=#st.members>=(st.max or R.PartySize)
 if not full then
  local b=add(corner(button(self.body,{BackgroundColor3=C.blue,Size=UDim2.new(1,-6,0,42)},function()self:inviteFriends()end),11))
  Icons.lead(label(b,'Invite friends',15,Enum.FontWeight.Heavy,C.white,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+3}),
   'people',{size=18,gap=8,color=C.white})
 end
 -- Friends here.
 local function friendRows(list)
  for _,f in ipairs(list)do
   local r=row(44)
   avatar(r,f.u,32,8)
   label(r,f.name,14,Enum.FontWeight.Bold,C.text,{Position=UDim2.fromOffset(48,0),Size=UDim2.new(1,-150,1,0)})
   local c=chip(r,f.invited and 'Invited' or 'Invite',f.invited and C.tile or C.accent,f.invited and C.muted or C.dark,92,function()
    if not f.invited and not full then self:send('invite',f.u)end
   end)
   c.AnchorPoint=Vector2.new(1,.5);c.Position=UDim2.new(1,-8,.5,0)
   c.Active=not f.invited and not full
  end
 end
 heading('FRIENDS ON THIS SERVER')
 if #(st.friends or {})==0 then
  add(label(self.body,'Nobody yet.',12,Enum.FontWeight.Medium,C.muted,{Size=UDim2.new(1,-6,0,18)}))
 end
 friendRows(st.friends or {})
 heading('FRIENDS IN THE GAME')
 if #(st.away or {})==0 then
  add(label(self.body,'No friends on other lobby servers. To invite someone who is not in the game, use the button above.',12,Enum.FontWeight.Medium,C.muted,
   {Size=UDim2.new(1,-6,0,32),TextWrapped=true,TextTruncate=Enum.TextTruncate.None}))
 end
 friendRows(st.away or {})
 if self.note and os.clock()-(self.noteAt or 0)<5 then
  add(label(self.body,self.note,12,Enum.FontWeight.Bold,C.amber,{Size=UDim2.new(1,-6,0,32),TextWrapped=true,TextTruncate=Enum.TextTruncate.None}))
 end
 if self:inParty()then
  local b=add(corner(button(self.body,{BackgroundColor3=C.red,Size=UDim2.new(1,-6,0,38)},function()self:send('leave')end),10))
  Icons.lead(label(b,'Leave party',14,Enum.FontWeight.Bold,C.white,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=Z+3}),
   'exit',{size=16,gap=8,color=C.white})
 end
 self.contentH=self.list.AbsoluteContentSize.Y
end
-- Called from Lobby:layout. `inset`: Roblox's top bar (the lobby's root reaches under it).
function P:layout(size,inset,phone)
 self.phone=phone
 local top=inset+12
 if phone then
  self.button.Size=UDim2.fromOffset(52,44)
  self.buttonText.Visible=false;self.count.Visible=true
  self.buttonIcon.Position=UDim2.new(0,8,.5,0);self.buttonIcon.Size=UDim2.fromOffset(18,18)
  self.count.Size=UDim2.fromOffset(26,20);self.countText.TextSize=11
  self.count.Position=UDim2.new(1,-4,.5,0)
 else
  self.button.Size=UDim2.fromOffset(156,44)
  self.buttonText.Visible=true
  self.buttonIcon.Position=UDim2.new(0,14,.5,0);self.buttonIcon.Size=UDim2.fromOffset(22,22)
  self.count.Size=UDim2.fromOffset(40,26);self.countText.TextSize=13;self.count.Position=UDim2.new(1,-8,.5,0)
 end
 self.button.Position=UDim2.new(1,-16,0,top)
 self.panel.Position=UDim2.new(1,-16,0,top+52)
 -- As tall as its content, within the screen (scaled down on a small one).
 local avail=size.Y+inset-(top+52)-12
 self.fit=math.clamp(math.min((size.X-32)/W,1),.6,1)
 local h=math.min(72+(self.contentH or 300)+20,avail/self.fit)
 self.panel.Size=UDim2.fromOffset(W,math.max(160,h))
 if not self.open then self.panelScale.Scale=self.fit end
 self.lastSize=size;self.lastInset=inset
end
function P:update(dt,shown)
 self.button.Visible=shown
 if not shown and self.open then self:setOpen(false)end
 local st=self.state
 self.countText.Text=#st.members..'/'..(st.max or R.PartySize)
 self.dot.Visible=st.invite~=nil and not self.open
 -- A new invite opens the panel by itself.
 local inviter=st.invite and st.invite.u
 if inviter~=self.lastInviter then self.lastInviter=inviter;if inviter and shown and not self.open then self:setOpen(true)end end
 if self.note and os.clock()-(self.noteAt or 0)>=5 then self.note=nil;self.dirty=true end
 if self.dirty and self.open then
  self.dirty=false;self:rebuild()
  task.defer(function()
   self.contentH=self.list.AbsoluteContentSize.Y
   if self.lastSize then self:layout(self.lastSize,self.lastInset,self.phone)end
  end)
 end
end
return P
