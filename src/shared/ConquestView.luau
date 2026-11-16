--!nonstrict
-- Client-only ownership geometry; commands and outcomes remain on the server.
local View={};View.__index=View
local Geometry=require(script.Parent.TerritoryGeometry)
local compact=require(script.Parent.NumberFormat).compact
-- Roblox head shot of a player, loaded by the engine without a yielding call.
local function avatarImage(userId)
 return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48",math.max(1,tonumber(userId)or 1))
end
-- A bot playing as a person (f.persona) shows the default avatar: the atlas head in classic yellow.
local PERSONA_SKIN=Color3.fromRGB(245,205,48)
-- Its generated Roblox avatar (server/PersonaHeads) once the server has built it: a head-and-shoulders
-- model shown in a small ViewportFrame over the avatar slot, like a head shot.
local function personaHead(look)
 local folder=look and script.Parent:FindFirstChild("PersonaHeads")
 return folder and folder:FindFirstChild(tostring(look))
end
local function showHead(img,model)
 local vp=img:FindFirstChild("Face3D")
 if not vp then
  vp=Instance.new("ViewportFrame");vp.Name="Face3D";vp.Size=UDim2.fromScale(1,1);vp.BackgroundTransparency=1
  vp.Ambient=Color3.fromRGB(175,175,175);vp.LightColor=Color3.new(1,1,1);vp.LightDirection=Vector3.new(-.6,-1,-.8)
  vp.ZIndex=img.ZIndex;vp:SetAttribute("NoSkin",true);vp:SetAttribute("Marker",true)
  local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=vp
  vp.Parent=img
 end
 for _,c in ipairs(vp:GetChildren())do if not c:IsA("UICorner")then c:Destroy()end end
 local copy=model:Clone();copy.Parent=vp
 local head=copy:FindFirstChild("Head")
 local cam=Instance.new("Camera");cam.FieldOfView=30
 if head then cam.CFrame=CFrame.lookAt(head.Position+head.CFrame.LookVector*3.6+Vector3.new(0,.3,0),head.Position+Vector3.new(0,-.15,0))end
 cam.Parent=vp;vp.CurrentCamera=cam
 img.ImageTransparency=1
end
local function dropHead(img)
 local vp=img:FindFirstChild("Face3D");if vp then vp:Destroy()end
 img.ImageTransparency=0
end
local function showAvatar(img,user,persona,look)
 local head=not user and persona and personaHead(look)
 local key=user and("u"..user)or(persona and("persona:"..tostring(look)..(head and ":3d"or "")))or ""
 if img:GetAttribute("AvatarKey")==key then return end
 img:SetAttribute("AvatarKey",key)
 if user then
  dropHead(img)
  img.ImageContent=Content.fromUri(avatarImage(user));img.ImageRectSize=Vector2.zero;img.ImageRectOffset=Vector2.zero;img.ImageColor3=Color3.new(1,1,1)
 elseif persona then
  -- The default head icon until (or unless) the generated avatar is ready.
  require(script.Parent.Icons).set(img,"avatar");img.ImageColor3=PERSONA_SKIN
  if head then showHead(img,head)else dropHead(img)end
 end
end
local Config=require(script.Parent.ConquestConfig)
local PLAYER=Config.PlayerId
local BattleView=require(script.Parent.BattleView)
local Sfx=require(script.Parent.Sfx)
local Flags=require(script.Parent.Flags)
local Protocol=require(script.Parent.Protocol)
local Rules=require(script.Parent.NavalRules)
local Wire=require(script.Parent.Wire)
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local TerritoryImage=require(script.Parent.TerritoryImage)
local PARTICIPANTS=Config.ParticipantCount
local CHUNK=24
local ink=Theme.colors.panel
local white=Theme.colors.text
-- Calm territory look: fills read as a light wash over the sea, outlines a darker shade.
-- The wash is pre-blended with the water colour and drawn opaque: the decorative coast
-- raster is coarser than the cell grid, and real transparency would show it through.
local FILL_STRENGTH=.36
local FILL_SATURATION=.85 -- country colours are muted before they tint the sea
-- How strongly a country's colour tints the sea. Blue and violet stay at FILL_STRENGTH; colours far from
-- the water's hue (yellow, orange, red) would turn grey-green over blue, so they are laid on thicker, up
-- to +WARM_BOOST, and keep their hue. Tribes (one shared brown) use TRIBE_STRENGTH so they read as brown.
local WARM_BOOST,TRIBE_STRENGTH=.3,.72
local function fillStrength(color,kind)
 if kind=='tribe'then return TRIBE_STRENGTH end
 local h=Color3.fromRGB(table.unpack(color)):ToHSV()
 local d=math.abs(h*360-215);d=math.min(d,360-d)
 return FILL_STRENGTH+WARM_BOOST*math.max(0,(d-90)/90)
end
local BORDER_TRANSPARENCY=.25
-- Your active fronts (your attack or an attack on you) are drawn red and thicker.
-- Pale red, how a missile's target area (BattleView AREA_COLOR 255,120,120 at .74 transparency) reads on
-- the map; one colour for every country (mixing it into the fill turned purple countries lilac).
local FRONT_RGB={242,140,140}
local FRONT_COLOR=Color3.fromRGB(table.unpack(FRONT_RGB))
local FRONT_WIDTH=2
local OVERLAY_LIFT=.0028 -- studs of overlay height per stud of camera height (measured: the image wins below ~.002)
local function brighten(v,k)return math.floor(v+(255-v)*k)end
-- How much lighter the country under the mouse gets: a soft hint, not a glare (author: the first .25 / .45 was too bright).
local HOVER_FILL,HOVER_EDGE=.1,.25
local function pairKey(a,b)if a>b then a,b=b,a end;return a..":"..b end
local function ui(cls,parent,props)
 local obj=Instance.new(cls);for k,v in pairs(props)do obj[k]=v end;obj.Parent=parent;return obj
end
local function label(parent,name,value,pos,size,fs)
 return ui("TextLabel",parent,{Name=name,Text=value,Position=pos,Size=size,BackgroundTransparency=1,
  TextColor3=white,TextSize=fs or 12,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=7})
end
local function part(parent,name,pos,size,color,alpha)
 return ui("Part",parent,{Name=name,Position=pos,Size=size,Color=color,Transparency=alpha or 0,
  Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,CastShadow=false,
  Material=Enum.Material.SmoothPlastic,TopSurface=Enum.SurfaceType.Smooth,BottomSurface=Enum.SurfaceType.Smooth})
end
local messages={fleet_exhausted="The fleet you sent ran out. Send fresh forces with a new order.",
 target_unreachable="The enemy's remaining territory shares no water border with you.",
 front_blocked="The front cannot advance here. Pick another border to attack.",
 target_defeated="The chosen enemy is fully defeated.",expansion_finished="All free water within reach is taken.",countered="The forces met head-on. The border moves only for the stronger side.",coast_required="Pick a free sea or ocean coast.",occupied="Another country already holds this coast.",
 already_started="Your starting point is already chosen.",not_adjacent="No water border to advance through.",
 own="This water is already yours.",start_required="First pick a starting point on a coast.",
 defeated="You lost everything. Start a new match.",slow_down="Click a little slower.",
 advancing="Growing along all the water within reach.",stopped="Advance stopped.",
 started="Start chosen! You can build a port for gold.",captured="Water captured.",
 restarted="New match: pick a free coast.",spectator="Another player is already controlling this match.",match_running="The match has already started: you cannot join it.",
 reinforced="Reinforcements added to the current attack.",reserved_coast="This coast is reserved for an island country. Pick another."}
function View.new(grid,gui)
 local self=setmetatable({grid=grid,gui=gui,owners=buffer.create(grid.count),factions={},coast={},chunks={},owned={},countryLabels={},anchors={},
  dirty={},dirtyQueue={},dirtyHead=1,labelsDirty=true,labelClock=0,pending={},pendingHead=1,
  revision=-1,epoch=0,phase="loading",busy=false,needsHUD=true,clock=0,early={},fronts={},hot={},frontLabels={},frontClock=0},View)
 self.root=Instance.new("Folder");self.root.Name="ConquestTerritories";self.root.Parent=workspace
 -- Marks pinned to the map (names, icons, range rings) get a screen of their own over the whole display.
 -- The interface's ScreenGui keeps to the safe area: on iPhones with rounded corners and a notch or
 -- Dynamic Island it is narrower than the view, so marks near the sides were cut off while the ships
 -- (3D parts) showed there. `marks` has the origin of WorldToScreenPoint (below the top bar inset).
 self.markScreen=Instance.new("ScreenGui");self.markScreen.Name="SeaBattleMapMarks";self.markScreen.ResetOnSpawn=false
 self.markScreen.ScreenInsets=Enum.ScreenInsets.None;self.markScreen.ClipToDeviceSafeArea=false
 self.markScreen.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;self.markScreen.DisplayOrder=gui.DisplayOrder-1
 -- `hold` fills the whole screen; its AbsolutePosition says where the screen starts in the coordinates
 -- WorldToScreenPoint and AbsolutePosition share.
 self.markHold=Instance.new("Frame");self.markHold.Name="Hold";self.markHold.BackgroundTransparency=1;self.markHold.BorderSizePixel=0
 self.markHold.Size=UDim2.fromScale(1,1);self.markHold.Parent=self.markScreen
 -- An empty, invisible probe of the free part of Roblox's top bar (see topbar).
 local barGui=Instance.new("ScreenGui");barGui.Name="SeaBattleTopbarProbe";barGui.ResetOnSpawn=false
 barGui.ScreenInsets=Enum.ScreenInsets.TopbarSafeInsets;barGui.Enabled=true
 self.barProbe=Instance.new("Frame");self.barProbe.Name="Probe";self.barProbe.BackgroundTransparency=1;self.barProbe.Active=false
 self.barProbe.Size=UDim2.fromScale(1,1);self.barProbe.Parent=barGui;barGui.Parent=gui.Parent
 self.marks=Instance.new("Frame");self.marks.Name="Marks";self.marks.BackgroundTransparency=1;self.marks.BorderSizePixel=0
 self.marks.Size=UDim2.fromScale(1,1);self.marks.Parent=self.markHold;self:placeMarks();Theme.skin(self.markScreen);self.markScreen.Parent=gui.Parent
 self.water=Color3.fromRGB(table.unpack(grid.data.uniformWaterColor or {78,134,212}))
 -- Territory pixels live in two images; parts are only a fallback when EditableImage is unavailable.
 self.pixelColors={}
 self.image=TerritoryImage.new(grid,self.root,function(id)return self:pixelColor(id)end)
 self.panel=ui("Frame",gui,{Name="ConquestHUD",Position=UDim2.fromOffset(24,20),Size=UDim2.fromOffset(300,96),
  BackgroundColor3=ink,BorderSizePixel=0,ZIndex=6})
 self.heading=label(self.panel,"MatchStatus","PICK A STARTING POINT",UDim2.fromOffset(12,8),UDim2.fromOffset(280,22),13)
 self.heading.Font=Enum.Font.GothamBold;self.heading.TextTruncate=Enum.TextTruncate.AtEnd
 -- Share of the water and the time left, right-aligned on the same line as the name.
 self.stats=label(self.panel,"MatchStats","",UDim2.fromOffset(12,8),UDim2.fromOffset(280,22),13)
 self.stats.Font=Enum.Font.GothamBold;self.stats.RichText=true;self.stats.TextXAlignment=Enum.TextXAlignment.Right
 self.stats:GetPropertyChangedSignal("TextBounds"):Connect(function()self:placeHeading()end)
 self.status=label(self.panel,"Status","Loading countries…",UDim2.fromOffset(12,33),UDim2.fromOffset(276,45),12)
 -- The player's Roblox avatar (head shot) before their name in the match line.
 self.avatar=ui("ImageLabel",self.panel,{Name="Avatar",BackgroundColor3=Color3.fromRGB(40,62,78),BackgroundTransparency=0,BorderSizePixel=0,
  Position=UDim2.fromOffset(10,8),Size=UDim2.fromOffset(22,22),ZIndex=7,Visible=false,
  Image=avatarImage(game.Players.LocalPlayer.UserId)})
 self.avatar:SetAttribute("NoSkin",true);ui("UICorner",self.avatar,{CornerRadius=UDim.new(1,0)})
 -- Mouse hover card: name, forces, relation and what a click does. It follows
 -- the cursor; Marker keeps it out of the label layout and the theme (styled here).
 local tip=ui("Frame",gui,{Name="HoverTip",BackgroundColor3=ink,BackgroundTransparency=.08,BorderSizePixel=0,ZIndex=40,
  Visible=false,Active=false,AutomaticSize=Enum.AutomaticSize.XY,Size=UDim2.fromOffset(0,0)})
 tip:SetAttribute("Marker",true);ui("UICorner",tip,{CornerRadius=UDim.new(0,8)})
 ui("UIStroke",tip,{Name="Owner",Thickness=1.5,Transparency=.2})
 ui("UIPadding",tip,{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),PaddingTop=UDim.new(0,7),PaddingBottom=UDim.new(0,7)})
 ui("UIListLayout",tip,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,3)})
 local head=ui("Frame",tip,{Name="Head",BackgroundTransparency=1,AutomaticSize=Enum.AutomaticSize.XY,Size=UDim2.fromOffset(0,18),LayoutOrder=1,ZIndex=40})
 ui("UIListLayout",head,{FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
 local swatch=ui("Frame",head,{Name="Swatch",Size=UDim2.fromOffset(12,12),BorderSizePixel=0,LayoutOrder=1,ZIndex=41});ui("UICorner",swatch,{CornerRadius=UDim.new(0,3)})
 local face=ui("ImageLabel",head,{Name="Avatar",Size=UDim2.fromOffset(16,16),BackgroundColor3=Color3.fromRGB(40,62,78),BorderSizePixel=0,LayoutOrder=2,ZIndex=41,Visible=false})
 ui("UICorner",face,{CornerRadius=UDim.new(1,0)})
 local function line(name,order,size,font,color)
  return ui("TextLabel",tip,{Name=name,BackgroundTransparency=1,AutomaticSize=Enum.AutomaticSize.XY,Size=UDim2.fromOffset(0,0),Text="",
   TextSize=size,Font=font,TextColor3=color,TextXAlignment=Enum.TextXAlignment.Left,LayoutOrder=order,ZIndex=41})
 end
 ui("TextLabel",head,{Name="Title",BackgroundTransparency=1,AutomaticSize=Enum.AutomaticSize.XY,Size=UDim2.fromOffset(0,0),Text="",
  TextSize=14,Font=Enum.Font.GothamBold,TextColor3=white,LayoutOrder=3,ZIndex=41})
 line("Info",2,12,Enum.Font.Gotham,white);line("Relation",3,12,Enum.Font.GothamMedium,white)
 line("Hint",4,11,Enum.Font.Gotham,Color3.fromRGB(150,176,188))
 -- The theme's font for the text; its panel styling stays off the frames.
 for _,d in ipairs(tip:GetDescendants())do if not d:IsA("TextLabel")then d:SetAttribute("NoSkin",true)end end
 self.tip=tip
 self.status.TextWrapped=true;self.status.TextYAlignment=Enum.TextYAlignment.Top
 -- Share of all water, with a bar toward the selected victory share.
 self.progress=ui("Frame",self.panel,{Name="VictoryProgress",Position=UDim2.fromOffset(12,82),Size=UDim2.fromOffset(276,6),
  BackgroundColor3=Color3.fromRGB(40,58,70),BorderSizePixel=0,ZIndex=7})
 ui("UICorner",self.progress,{CornerRadius=UDim.new(1,0)})
 self.progressFill=ui("Frame",self.progress,{Name="Fill",Size=UDim2.fromScale(0,1),BackgroundColor3=Color3.fromRGB(111,208,186),BorderSizePixel=0,ZIndex=8})
 ui("UICorner",self.progressFill,{CornerRadius=UDim.new(1,0)})
 -- On a phone a tap on the status line opens or closes the leaderboard (Tab does it on a keyboard).
 self.leadersTap=ui("TextButton",self.panel,{Name="LeadersTap",Text="",BackgroundTransparency=1,AutoButtonColor=false,
  Size=UDim2.fromScale(1,1),ZIndex=9,Visible=false})
 self.leadersTap.Activated:Connect(function()if self.compact then self:toggleLeaders()end end)
 -- Always-visible leaderboard (on a phone: on demand): living countries by water share, top ten plus
 -- your own place. Its size follows the screen (placeLeaders): larger on a computer.
 self.leaderboard=ui("Frame",gui,{Name="Leaderboard",Position=UDim2.new(1,-258,0,64),Size=UDim2.fromOffset(234,300),
  BackgroundColor3=ink,BorderSizePixel=0,ZIndex=6,Visible=false})
 self.leaderTitle=label(self.leaderboard,"Title","LEADERS",UDim2.fromOffset(12,8),UDim2.fromOffset(210,18),12)
 self.leaderTitle.Font=Enum.Font.GothamBold
 self.leaderSub=label(self.leaderboard,"Subtitle","",UDim2.fromOffset(12,26),UDim2.fromOffset(210,16),10)
 self.leaderSub.TextColor3=Color3.fromRGB(150,173,178)
 -- Phone only: a trophy before the title, a close button, a line under the header and "···" before your
 -- own place when it is below the rows shown (see placeLeaders / refreshLeaders).
 self.leaderIcon=Icons.image(self.leaderboard,"trophy",18,Color3.fromRGB(255,196,84),{Name="Trophy",Position=UDim2.fromOffset(12,11),ZIndex=8,Visible=false})
 self.leaderClose=ui("TextButton",self.leaderboard,{Name="Close",Text="",AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(32,50,63),
  BorderSizePixel=0,Size=UDim2.fromOffset(28,28),ZIndex=8,Visible=false})
 self.leaderClose:SetAttribute("NoSkin",true);ui("UICorner",self.leaderClose,{CornerRadius=UDim.new(1,0)})
 Icons.image(self.leaderClose,"close",12,white,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=9})
 self.leaderClose.Activated:Connect(function()self.showLeaders=false;self:refreshHUD()end)
 self.leaderLine=ui("Frame",self.leaderboard,{Name="Line",BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.9,BorderSizePixel=0,
  Size=UDim2.new(1,-24,0,1),Position=UDim2.fromOffset(12,40),ZIndex=7,Visible=false})
 self.leaderGap=label(self.leaderboard,"Gap","···",UDim2.fromOffset(0,0),UDim2.new(1,0,0,12),13)
 self.leaderGap.TextXAlignment=Enum.TextXAlignment.Center;self.leaderGap.TextColor3=Color3.fromRGB(150,173,178);self.leaderGap.Visible=false
 self.leaderRows={}
 for i=1,11 do
  -- A row is a button: it flies the camera to that country (the middle of its largest water).
  local row=ui("TextButton",self.leaderboard,{Name="Leader"..i,Text="",AutoButtonColor=false,Position=UDim2.fromOffset(8,48+(i-1)*22),Size=UDim2.fromOffset(218,20),
   BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=7})
  ui("UICorner",row,{CornerRadius=UDim.new(0,5)})
  row.MouseEnter:Connect(function()row.BackgroundTransparency=.92 end)
  row.MouseLeave:Connect(function()row.BackgroundTransparency=1 end)
  row.Activated:Connect(function()self:focusCountry(row:GetAttribute("Country"))end)
  local dot=ui("Frame",row,{Name="Dot",Position=UDim2.fromOffset(28,6),Size=UDim2.fromOffset(8,8),BorderSizePixel=0,ZIndex=8})
  ui("UICorner",dot,{CornerRadius=UDim.new(1,0)})
  Flags.image(row,nil,10,{ZIndex=8,Visible=false})
  local rank=label(row,"Rank","",UDim2.fromOffset(2,0),UDim2.fromOffset(24,20),11);rank.TextXAlignment=Enum.TextXAlignment.Right;rank.ZIndex=8
  ui("UICorner",rank,{CornerRadius=UDim.new(1,0)}) -- (a phone draws the place as a round badge)
  local name=label(row,"CountryName","",UDim2.fromOffset(42,0),UDim2.fromOffset(122,20),11);name.TextTruncate=Enum.TextTruncate.AtEnd;name.ZIndex=8
  local value=label(row,"Share","",UDim2.fromOffset(160,0),UDim2.fromOffset(54,20),11);value.TextXAlignment=Enum.TextXAlignment.Right;value.ZIndex=8
  self.leaderRows[i]=row
 end
 -- Fights window: this player's expansion and every attack they make or suffer; a row flies the camera
 -- to that front line, the header folds the list away.
 self.fightsPanel=ui("Frame",gui,{Name="Fights",Position=UDim2.new(1,-258,0,374),Size=UDim2.fromOffset(234,34),
  BackgroundColor3=ink,BorderSizePixel=0,ZIndex=6,Visible=false})
 ui("UICorner",self.fightsPanel,{CornerRadius=UDim.new(0,8)})
 self.fightsHeader=ui("TextButton",self.fightsPanel,{Name="Header",Text="",BackgroundTransparency=1,Size=UDim2.new(1,0,0,30),ZIndex=7,AutoButtonColor=false})
 self.fightsTitle=label(self.fightsHeader,"Title","BATTLES",UDim2.fromOffset(12,6),UDim2.new(1,-44,0,18),12)
 self.fightsTitle.Font=Enum.Font.GothamBold;self.fightsTitle.ZIndex=8
 Icons.lead(self.fightsTitle,"swords",{size=14})
 self.fightsToggle=label(self.fightsHeader,"Toggle","–",UDim2.new(1,-30,0,6),UDim2.fromOffset(20,18),14)
 self.fightsToggle.Font=Enum.Font.GothamBold;self.fightsToggle.TextXAlignment=Enum.TextXAlignment.Center;self.fightsToggle.ZIndex=8
 self.fightsHeader.Activated:Connect(function()self.fightsFolded=not self.fightsFolded;self.fightsClock=1 end)
 self.fightRows={}
 for i=1,6 do
  local row=ui("TextButton",self.fightsPanel,{Name="Fight"..i,Text="",AutoButtonColor=true,BackgroundColor3=Color3.fromRGB(30,48,60),
   BackgroundTransparency=.2,BorderSizePixel=0,Position=UDim2.fromOffset(8,30+(i-1)*26),Size=UDim2.new(1,-16,0,22),ZIndex=7,Visible=false})
  ui("UICorner",row,{CornerRadius=UDim.new(0,6)})
  local text=label(row,"Label","",UDim2.fromOffset(8,0),UDim2.new(1,-12,1,0),11);text.ZIndex=8;text.TextTruncate=Enum.TextTruncate.AtEnd
  Icons.lead(text,"swords",{size=13,gap=5})
  row.Activated:Connect(function()if row:GetAttribute("Cell")then self:focusCell(row:GetAttribute("Cell"))end end)
  self.fightRows[i]=row
 end
 local api=game.ReplicatedStorage.SeaBattle:WaitForChild("ConquestAPI")
 self.remote=api:WaitForChild("Command")
 -- `live` is the server's online match as the lobby needs it (phase, places, countdown, own country),
 -- kept current whatever the map shows. The map shows one `source` at a time: "demo" (the lobby's
 -- background) or "solo" (the player's own match), both run here by shared/LocalMatch, or "server".
 self.live={epoch=0,phase="loading",battle={}};self.source=nil
 self.wire=Wire.newDecoder()
 api:WaitForChild("Changed").OnClientEvent:Connect(function(msg)self:incoming(msg)end)
 -- The player's saved profile (silver, daily bonus, purchases): the server sends it after every change,
 -- and once on request in case the first one came before this connection.
 self.profile=nil
 api:WaitForChild("Profile").OnClientEvent:Connect(function(p,extra)
  self:setProfile(p)
  -- The silver for the online match just played (shown in the end-of-match card).
  if type(extra)=='table'and extra.payout then self.payout=extra.payout end
  -- The starter pack just bought: its reward window (shared/StarterOffer).
  if type(extra)=='table'and type(extra.starter)=='table'and self.lobby then self.lobby.starterOffer:reward(extra.starter)end
 end)
 task.spawn(function()self:request("profile")end)
 self.localMatch=require(script.Parent.LocalMatch).new(self)
 if not self:loadLive()then self.status.Text="Could not load the online match."end
 self.battleUI=BattleView.new(self)
 self.lobby=require(script.Parent.Lobby).new(self)
 return self
end
function View:setProfile(p)
 if type(p)~='table'then return end
 self.profile=p;self.profileAt=os.clock()
end
-- An account request (profile, daily bonus, shop): waits for the server's answer {ok, reason, ...}; a
-- profile in the answer is taken at once. Unlike `send` it does not touch the match's status line.
function View:request(action,value)
 local ok,r=pcall(function()return self.remote:InvokeServer(action,value)end)
 if not ok or type(r)~='table'then return {ok=false,reason='no_reply'}end
 if r.profile then self:setProfile(r.profile)end
 return r
end
-- Everything from the server passes here (shared/Wire messages): the lobby's view of the online match
-- is updated, and the map only while it shows the server.
function View:incoming(msg)
 local ok,delta=pcall(Wire.decode,msg,self.wire)
 if not ok then warn("[SeaBattle] bad message: "..tostring(delta));return end
 self:track(delta)
 if self.source=="server"then self:receive(delta)end
end
function View:track(d)
 local live=self.live
 if d.snapshot then
  local s=d.snapshot
  if s.epoch<live.epoch then return end
  live.epoch=s.epoch;live.phase=s.phase;live.battle={}
  for k,v in pairs(s.shared or {})do live.battle[k]=v end
 elseif d.private or d.epoch~=live.epoch then return
 else
  if d.phase then live.phase=d.phase end
  for k,v in pairs(d.shared or {})do live.battle[k]=v end
 end
 local clients=live.battle.clients or {}
 local user=game.Players.LocalPlayer.UserId
 live.playerId=clients[tostring(user)]or clients[user]
end
-- The whole online map; the server limits snapshot requests, so retry a few times after a cooldown.
function View:loadLive()
 for attempt=1,6 do
  local ok,result=pcall(function()return self.remote:InvokeServer("snapshot")end)
  if ok and result and result.snapshot then self:incoming(result.snapshot);return true end
  task.wait(math.min(attempt,3))
 end
 return false
end
-- Forget the current stream, so the next snapshot is taken whatever its epoch.
function View:clearStream()
 self.epoch=0;self.revision=-1;self.early={};self.pending={};self.pendingHead=1
end
-- What the map shows. The local match (demo or solo) gives its own clock; the server's map is asked
-- for again as a whole.
function View:setSource(source)
 if source==self.source then return end
 local was=self.source;self.source=source;self:clearStream();self.message=nil
 if source=="server"then
  self.timeScale=1;self.simClock=nil;self.localMatch:hide()
  task.spawn(function()
   if not self:loadLive()and self.source=="server"then self.status.Text="Could not load the online match."end
  end)
 else
  self.simClock=function()return self.localMatch:clock()end
  if was~="demo"and was~="solo"then self.localMatch:show()else task.spawn(self.localMatch.push,self.localMatch)end
 end
end
-- The player's own country in what the map shows (a solo match, or the online one).
function View:myCountry()
 if self.source=="solo"then return self.playerId end
 return self.live.playerId
end
function View:owner(id)return Geometry.owner(self.owners,id)end
-- Colour of one cell in the territory image: an opaque wash for the inside, a darker outline where the
-- neighbouring water belongs to someone else, red on your active fronts. Land and neutral water stay clear.
function View:pixelColor(id)
 local o=buffer.readu8(self.owners,id-1);if o==0 then return 0,0,0,0 end
 local c=self.pixelColors[o]
 if not c then
  local f=self.factions[o];if not f then return 0,0,0,0 end
  -- A border pixel is a full cell wide, so it sits between the wash and the old dark outline.
  local h,sat,v=Color3.fromRGB(table.unpack(f.color)):ToHSV();local base=Color3.fromHSV(h,sat*FILL_SATURATION,v)
  local fill=self.water:Lerp(base,fillStrength(f.color,f.kind));local edge=fill:Lerp(base:Lerp(Color3.fromRGB(28,38,48),.45),.6)
  c={math.floor(fill.R*255),math.floor(fill.G*255),math.floor(fill.B*255),math.floor(edge.R*255),math.floor(edge.G*255),math.floor(edge.B*255)}
  -- A water pattern (a cosmetic): its cells take a lighter tint of the same fill.
  c.pattern=Flags.pattern(f.pattern)
  if c.pattern then local tint=fill:Lerp(Color3.new(1,1,1),.2);c[7],c[8],c[9]=math.floor(tint.R*255),math.floor(tint.G*255),math.floor(tint.B*255)end
  self.pixelColors[o]=c
 end
 local grid=self.grid;local w,h=grid.width,grid.height;local x,y=(id-1)%w,(id-1)//w
 local owners,mask,hot=self.owners,grid.waterMask,self.hot
 -- The neighbour that makes this an outline cell: another owner's (or nobody's) water; a front
 -- with that owner wins. (Written out without a helper closure: this runs for every repainted cell.)
 local other
 for k=1,8 do
  -- the four sides, then (only for the hovered country without an outline yet) the diagonals
  if k==5 and(other or o~=self.hoverOwner)then break end
  local n
  if k==1 then n=x>0 and id-1 elseif k==2 then n=x<w-1 and id+1 elseif k==3 then n=y>0 and id-w elseif k==4 then n=y<h-1 and id+w
  elseif k==5 then n=x>0 and y>0 and id-w-1 elseif k==6 then n=x<w-1 and y>0 and id-w+1
  elseif k==7 then n=x>0 and y<h-1 and id+w-1 else n=x<w-1 and y<h-1 and id+w+1 end
  if n then
   local no=buffer.readu8(owners,n-1)
   if no~=o and buffer.readu8(mask,n-1)==1 and(not other or(no>0 and hot[pairKey(o,no)]))then other=no end
  end
 end
 -- The hovered country: its outline brighter and one cell thicker (the diagonals too), and
 -- for a country of moderate size its fill brighter as well.
 local hl=o==self.hoverOwner
 if not other then
  if hl and self.hoverFill then return brighten(c[1],HOVER_FILL),brighten(c[2],HOVER_FILL),brighten(c[3],HOVER_FILL),255 end
  local pt=c.pattern
  if pt and pt[(y%pt.h)*pt.w+x%pt.w+1]then return c[7],c[8],c[9],255 end
  return c[1],c[2],c[3],255
 end
 -- Front line: one pale red for every country, like a missile's target area.
 if other>0 and self.hot[pairKey(o,other)]then
  return FRONT_RGB[1],FRONT_RGB[2],FRONT_RGB[3],255
 end
 if hl then return brighten(c[4],HOVER_EDGE),brighten(c[5],HOVER_EDGE),brighten(c[6],HOVER_EDGE),255 end
 return c[4],c[5],c[6],255
end
-- Repaint every cell of `a` touching `b` (and the other way round) after a front starts or ends.
function View:repaintPair(a,b)
 for _,pair in ipairs({{a,b},{b,a}})do
  local mine,theirs=pair[1],pair[2]
  for id in pairs(self.owned[mine]or {})do
   for _,n in ipairs(self.grid:neighborIds(id))do if buffer.readu8(self.owners,n-1)==theirs then self.image:paint(id);break end end
  end
 end
end
function View:mark(id)
 if self.image then self.image:paint(id);return end
 local x,y=(id-1)%self.grid.width,math.floor((id-1)/self.grid.width)
 local cx,cy=math.floor(x/CHUNK),math.floor(y/CHUNK);local key=cx..":"..cy
 if not self.dirty[key]then self.dirty[key]={cx=cx,cy=cy};table.insert(self.dirtyQueue,key)end
end
function View:setCell(id,owner)
 local old=self:owner(id);if old==owner then return end
 -- The newest neutral water taken by this player: where its expansion line is now.
 if owner==self.playerId and old==0 then self.lastExpansion=id end
 if old>0 and self.owned[old]then self.owned[old][id]=nil end
 buffer.writeu8(self.owners,id-1,owner)
 if owner>0 then self.owned[owner]=self.owned[owner]or {};self.owned[owner][id]=true end
 self:mark(id)
 local a,b,c,d=self.grid:nb4(id)
 if a>0 then self:mark(a)end;if b>0 then self:mark(b)end;if c>0 then self:mark(c)end;if d>0 then self:mark(d)end
 -- (the player's border for the front labels: this cell and its neighbours may have joined or left it)
 local me=self.border and self.borderFor
 if me then
  self:borderCheck(id,me)
  if a>0 then self:borderCheck(a,me)end;if b>0 then self:borderCheck(b,me)end
  if c>0 then self:borderCheck(c,me)end;if d>0 then self:borderCheck(d,me)end
 end
 self.labelsDirty=true
end
function View:renderChunk(key,location)
 local chunk=self.chunks[key]
 if not chunk then
  local folder=Instance.new("Folder");folder.Name="Pixels_"..key;folder.Parent=self.root
  chunk={folder=folder,pool={}};self.chunks[key]=chunk
 end
 chunk.location=location;chunk.pairs={};chunk.front={}
 local rects=Geometry.chunk(self.grid,self.owners,location.cx*CHUNK,location.cy*CHUNK,CHUNK)
 local d=self.grid.data;local s=d.tileSize;local me=self.playerId
 for i,r in ipairs(rects)do
  local f=self.factions[r.owner];if not f then continue end
  local color=Color3.fromRGB(table.unpack(f.color))
  local size=Vector3.new(r.w*s,.002,r.h*s)
  local front=false
  if r.border then
   local other=r.other or 0;local pk=pairKey(r.owner,other);chunk.pairs[pk]=true
   front=self.hot[pk]==true
   -- Points along borders with you, used to anchor the force label on the front line.
   if me and other>0 and(r.owner==me or other==me)then
    local list=chunk.front[pk]or {};chunk.front[pk]=list
    if #list<6 then table.insert(list,Vector3.new((r.x+r.w/2-d.width/2)*s,.03,(r.y+r.h/2-d.height/2)*s))end
   end
   local width=(self.borderWidth or .035)*(front and FRONT_WIDTH or 1)
   color=front and FRONT_COLOR or color:Lerp(Color3.fromRGB(28,38,48),.45)
   if r.w<.5 then size=Vector3.new(width,.002,r.h*s)
   else size=Vector3.new(r.w*s,.002,width)end
  else
   color=self.water:Lerp(color,fillStrength(f.color,f.kind))
  end
  local pos=Vector3.new((r.x+r.w/2-d.width/2)*s,r.border and .027 or .022,(r.y+r.h/2-d.height/2)*s)
  local obj=chunk.pool[i]
  if not obj then obj=part(chunk.folder,"PixelFill",pos,size,color);chunk.pool[i]=obj end
  obj.Name=r.border and "CountryBorder"or "PixelFill";obj.Position=pos;obj.Size=size;obj.Color=color
  obj.Transparency=r.border and(front and 0 or BORDER_TRANSPARENCY)or 0
  obj:SetAttribute("BorderAxis",r.border and (r.w<.5 and "X"or "Z")or nil)
  obj:SetAttribute("Front",front or nil)
 end
 for i=#rects+1,#chunk.pool do chunk.pool[i].Transparency=1 end
end
function View:createCountryLabels()
 for _,f in ipairs(self.factions)do
  if not self.countryLabels[f.id]then
   local name=label(self.marks,"CountryName",f.name,UDim2.new(),UDim2.fromOffset(180,28),12)
   name.AnchorPoint=Vector2.new(.5,.5);name.TextXAlignment=Enum.TextXAlignment.Center
   name.Font=Enum.Font.GothamBold;name.TextStrokeColor3=ink;name.TextStrokeTransparency=.05;name.ZIndex=2;name.Visible=false
   -- A player's country shows their Roblox avatar before the name (bots have none).
   local face=ui("ImageLabel",name,{Name="Avatar",AnchorPoint=Vector2.new(1,.5),BackgroundColor3=ink,BackgroundTransparency=.2,
    BorderSizePixel=0,ZIndex=2,Visible=false});face:SetAttribute("Marker",true);face:SetAttribute("NoSkin",true)
   ui("UICorner",face,{CornerRadius=UDim.new(1,0)})
   -- A worn flag (a cosmetic) after the name.
   Flags.image(name,nil,10,{AnchorPoint=Vector2.new(0,.5),ZIndex=2,Visible=false})
   self.countryLabels[f.id]=name
  end

 end
end
-- Sea/ocean coast, matching the server rule; computed locally instead of being sent.
function View:isCoast(id)
 local cached=self.coast[id];if cached~=nil then return cached end
 local grid=self.grid;local p=grid.data.palette[grid:paletteId(id)];local coast=false
 if p.water and(p.kind=="sea"or p.kind=="ocean")then
  for _,n in ipairs(grid:neighborIds(id))do if not grid:isWater(n)then coast=true;break end end
 end
 self.coast[id]=coast;return coast
end
function View:applyRoster(roster)
 local list={}
 for _,row in ipairs(roster)do
  local entry=Protocol.unpack(row,Protocol.RosterFields)
  local existing=self.factions[entry.id]
  if existing then for k,v in pairs(entry)do existing[k]=v end;entry=existing end
  list[entry.id]=entry
  -- A country can change colour within a match (a player or a persona gets the colour of the coast
  -- it starts on). The fill is cached per country, so a changed colour drops the cache and repaints
  -- that country's cells over the next frames; otherwise cells painted before the new colour arrived
  -- keep the old one while its buildings and labels show the new one.
  local key=(entry.color and table.concat(entry.color,",")or"")..":"..tostring(entry.kind)..":"..tostring(entry.pattern)
  self.colorKeys=self.colorKeys or {}
  if self.colorKeys[entry.id]~=key then
   if self.colorKeys[entry.id]~=nil then self:recolor(entry.id)end
   self.colorKeys[entry.id]=key
  end
 end
 self.factions=list
end
function View:recolor(id)
 self.pixelColors[id]=nil
 self.hoverQueue=self.hoverQueue or {}
 for cell in pairs(self.owned and self.owned[id]or {})do table.insert(self.hoverQueue,cell)end
end
function View:applyRows(rows)
 for _,entry in ipairs(rows)do local f=self.factions[entry[1]];if f then Protocol.unpack(entry[2],Protocol.FactionFields,f)end end
end
function View:applyBattle(data)
 local b=self.battle or {prices={},attackOptions={},structures={},units={},clients={},settings={},events={}};self.battle=b
 if data.shared then for k,v in pairs(data.shared)do b[k]=v end end
 if data.structures then
  local list={};for _,row in ipairs(data.structures)do table.insert(list,Protocol.unpack(row,Protocol.StructureFields))end;b.structures=list
 end
 if data.units then
  local list={};for _,row in ipairs(data.units)do table.insert(list,Protocol.unpack(row,Protocol.UnitFields))end;b.units=list;b.unitsAt=os.clock();b.unitsTime=data.time
 end
 -- Railway network rows {edge id, corner cells}; replaced whole whenever the track changes.
 if data.railways then b.railways=data.railways;b.railwaysVersion=(b.railwaysVersion or 0)+1 end
 if data.time then b.time=data.time end
 if data.recordFrames then b.recordFrames=data.recordFrames end
 local user=game.Players.LocalPlayer.UserId
 self.playerId=b.clients[tostring(user)]or b.clients[user]
end
function View:applyPrivate(p)
 local b=self.battle;if not b or not p then return end
 local f=self.factions[p.owner];if f and p.row then Protocol.unpack(p.row,Protocol.FactionFields,f)end
 if p.prices then b.prices[tostring(p.owner)]=p.prices end
 if p.attack then
  local options={}
  for id,row in pairs(p.attack.options)do local o=Protocol.unpack(row,Protocol.AttackFields);o.amount=p.attack.amount;options[id]=o end
  b.attackOptions[tostring(p.owner)]=options
 end
 if p.fronts then self:setFronts(p.owner,p.fronts)end
 self.needsHUD=true
end
-- Re-render only chunks whose borders touch a front that turned on or off.
function View:setFronts(me,rows)
 local fronts,hot={},{}
 for _,row in ipairs(rows)do
  local front=Protocol.unpack(row,Protocol.FrontFields);front.key=pairKey(me,front.enemy)
  table.insert(fronts,front);hot[front.key]=true
 end
 local changed={}
 for key in pairs(hot)do if not self.hot[key]then changed[key]=true end end
 for key in pairs(self.hot)do if not hot[key]then changed[key]=true end end
 self.fronts=fronts;self.hot=hot
 if next(changed)and self.image then
  for key in pairs(changed)do local a,b=key:match("^(%d+):(%d+)$");self:repaintPair(tonumber(a),tonumber(b))end
 elseif next(changed)then
  for key,chunk in pairs(self.chunks)do
   for pk in pairs(changed)do if chunk.pairs and chunk.pairs[pk]then
    if not self.dirty[key]then self.dirty[key]=chunk.location;table.insert(self.dirtyQueue,key)end;break
   end end
  end
 end
end
-- One label per front, on the border point nearest the screen centre.
-- The player's own cells that touch another country (self.border), kept up to date by setCell and built
-- whole once per player and snapshot: the front labels look only at these. (2026-11-16: the labels
-- scanned up to 30 000 of the player's cells per front every 0.3 s, a table per cell; with four fronts
-- that was ≈48 ms a time, more than the whole match step, on a computer.)
function View:borderCheck(id,me)
 local o=self.owners
 if buffer.readu8(o,id-1)==me then
  local a,b,c,d=self.grid:nb4(id)
  for k=1,4 do
   local n=k==1 and a or k==2 and b or k==3 and c or d
   if n>0 then local x=buffer.readu8(o,n-1);if x>0 and x~=me then self.border[id]=true;return end end
  end
 end
 self.border[id]=nil
end
function View:updateFrontLabels(camera)
 self.frontAnchors=self.frontAnchors or {}
 local center=camera.CFrame.Position;local seen={}
 local me=self.playerId
 local best,distance={},{}
 if self.image and me and #self.fronts>0 then
  if self.borderFor~=me or not self.border then
   self.border={};self.borderFor=me
   for id in pairs(self.owned[me]or {})do self:borderCheck(id,me)end
  end
  local wanted={};for _,front in ipairs(self.fronts)do wanted[front.enemy]=true end
  local grid,o=self.grid,self.owners;local w,h,tile=grid.width,grid.height,grid.data.tileSize
  for id in pairs(self.border)do
   local a,b,c,d=grid:nb4(id)
   for k=1,4 do
    local n=k==1 and a or k==2 and b or k==3 and c or d
    local x=n>0 and buffer.readu8(o,n-1)or 0
    if wanted[x]then
     local px,pz=((id-1)%w+.5-w/2)*tile,((id-1)//w+.5-h/2)*tile
     local dd=(px-center.X)^2+(pz-center.Z)^2
     if not distance[x]or dd<distance[x]then distance[x]=dd;best[x]=Vector3.new(px,.03,pz)end
    end
   end
  end
 end
 for _,front in ipairs(self.fronts)do
  local anchor,dist=best[front.enemy],distance[front.enemy]
  for _,chunk in pairs(self.chunks)do
   for _,point in ipairs(chunk.front and chunk.front[front.key]or {})do
    local d=(point.X-center.X)^2+(point.Z-center.Z)^2
    if not dist or d<dist then anchor,dist=point,d end
   end
  end
  self.frontAnchors[front.key]=anchor;seen[front.key]=true
 end
 for key,label in pairs(self.frontLabels)do if not seen[key]then label:Destroy();self.frontLabels[key]=nil;self.frontAnchors[key]=nil end end
end
-- The troops of the attack, blue for yours and red for one on you, written on the front.
local OUTGOING,INCOMING=Color3.fromRGB(0x3f,0xa9,0xf5),Color3.fromRGB(0xf8,0x71,0x71)
function View:frontText(front)
 if front.mode=="attack"then return compact(front.mine),OUTGOING end
 return compact(front.theirs),INCOMING
end
function View:receive(delta)
 if delta.snapshot then
  local s=delta.snapshot
  if s.epoch<self.epoch or(s.epoch==self.epoch and s.revision<self.revision)then return end
  self.epoch=s.epoch;self.revision=s.revision;self.phase=s.phase;self.factions={};self.battle=nil
  if self.battleUI then self.battleUI:clearUnits()end
  self:applyRoster(s.roster);self:applyRows(s.rows);self:applyBattle(s)
  self.owners=s.cellOwners;self.owned={};self.anchors={};self.pending={};self.pendingHead=1;self.border=nil;self.borderFor=nil
  for i=1,Rules.MaxParticipants do self.owned[i]={}end
  for _,name in pairs(self.countryLabels)do name.Visible=false end;self.nameState=nil
  if self.image then self.image:clear();self.pixelColors={};self.colorKeys={}
  else self.root:ClearAllChildren()end
  self.chunks={};self.dirty={};self.dirtyQueue={};self.dirtyHead=1
  for _,label in pairs(self.frontLabels)do label:Destroy()end;self.frontLabels={};self.frontAnchors={};self.fronts={};self.hot={}
  for id=1,self.grid.count do
   local owner=self:owner(id)
   if owner>0 then self.owned[owner][id]=true;self:mark(id)end
   if id%65536==0 then task.wait()end
  end
  self:createCountryLabels();self.message=nil;self.labelsDirty=true;self.lastFactionCount=#self.factions
  -- Packets that raced ahead of the snapshot response are replayed, not lost.
  local early=self.early;self.early={}
  for _,d in ipairs(early)do if d.epoch==self.epoch and(d.private or d.revision>=s.revision)then self:receive(d)end end
 elseif self.epoch==0 then
  table.insert(self.early,delta);return
 else
  if delta.epoch~=self.epoch then return end
  if delta.private then self:applyPrivate(delta.private);return end
  if delta.revision<self.revision then return end
  self.revision=delta.revision;self.phase=delta.phase
  self:applyBattle(delta)
  if delta.roster then self:applyRoster(delta.roster)end
  if delta.rows then self:applyRows(delta.rows)end
  -- (read straight from the packed buffer: a table per cell was thousands of tables a second)
  local packed=delta.cells;local now=os.clock();local count=0;local listed
  if typeof(packed)=='buffer'then count=buffer.len(packed)//Protocol.CellBytes
  elseif type(packed)=='table'then listed=packed;count=#packed end
  -- New cells are laid out over the time until the next message is due (the measured gap between
  -- messages), so the fill moves on evenly instead of jumping when a message lands and then standing still.
  if count>0 then
   local gap=self.lastCellsAt and math.clamp(now-self.lastCellsAt,.05,.5)or .1
   self.cellGap=(self.cellGap or gap)+(gap-(self.cellGap or gap))*.3;self.lastCellsAt=now
   -- Cells still waiting from the previous message go first: the new ones start after them.
   -- (pending is flat: cell, owner, time for each waiting cell)
   local p=self.pending;local n=#p
   local from=math.max(now,n>=self.pendingHead and p[n]or now)
   local span=math.max(.05,self.cellGap*.95-(from-now))
   local B=Protocol.CellBytes
   for i=1,count do
    local cell,owner
    if listed then cell,owner=listed[i][1],listed[i][2]
    else cell,owner=buffer.readu32(packed,(i-1)*B),buffer.readu8(packed,(i-1)*B+4)end
    p[n+1]=cell;p[n+2]=owner;p[n+3]=from+(i-1)/count*span;n+=3
   end
  end
  if #self.factions~=self.lastFactionCount then self:createCountryLabels()end
  self.lastFactionCount=#self.factions
 end
 self.needsHUD=true
 if self.onChanged and not self.notifyPending then
  self.notifyPending=true;task.delay(.25,function()self.notifyPending=false;self.onChanged()end)
 end
end
function View:refreshLabels()
 if self.labelBusy then return end
 self.labelBusy=true;self.labelsDirty=false;local epoch=self.epoch
 task.spawn(function()
  for _,f in ipairs(self.factions)do
   if epoch~=self.epoch then break end
   -- A country that barely changed keeps its label spot: no search over its water.
   local old=self.anchors[f.id];local count=f.count or 0
   if old and old.count and self:owner(old.cell)==f.id and math.abs(count-old.count)<math.max(30,count*.05)then continue end
   local anchor=Geometry.largest(self.grid,self.owners,self.owned[f.id]or {},f.id,true)
   if anchor then anchor.count=count end
   if epoch==self.epoch then self.anchors[f.id]=anchor end
   task.wait()
  end
  self.labelBusy=false
 end)
end
-- The status panel's height: the title line and the progress bar, plus the message line when there is one.
function View:fitHUD()
 local small=self.compact==true;local has=self.status.Text~=""
 local right=self.hudRight or 300
 self.status.Visible=has
 local h=small and(has and 58 or 40)or(has and 88 or 58)
 if self.panel.Size.Y.Offset~=h then self.panel.Size=UDim2.fromOffset(right,h)end
 self.progress.Position=UDim2.fromOffset(10,h-(small and 9 or 14))
end
function View:refreshHUD()
 local mine=self.factions[self.playerId or PLAYER];if not mine then return end
 local alive=0;for _,f in ipairs(self.factions)do if f.alive then alive+=1 end end
 local showAvatar=self.phase~="choosing"and self.phase~="finished"and self.playerId~=nil
 if self.avatar.Visible~=showAvatar then self.avatar.Visible=showAvatar;self:placeHeading()end
 if self.phase=="choosing" then
  self.heading.Text="PICK A STARTING POINT";self.stats.Text=""
  self.status.Text=self.message or "Tap a free sea or ocean coast"
 else
  local finished=self.phase=="finished"
  self.heading.Text=finished and "MATCH OVER"or(mine.name and mine.name~="")and mine.name or "Your country"
  -- (a phone drops the words "of the water": the percentage alone is enough there)
  self.stats.Text=finished and ""or string.format('<font color="#6fd0ba">%s</font>%s  ·  %s',(self:share(mine.count):gsub("<","&lt;")),self.compact and ""or " of the water",self:timeLeftText())
  if self.phase=="finished"then
   -- Results: who won, and when the lobby comes back.
   local w=self.battle and self.battle.winner;local winner=w and self.factions[w]
   self.status.Text=(winner and("Winner: "..(w==self.playerId and "you! "or winner.name..". "))or "Match over. ")
    ..(self.resultsLeft and("Back to the lobby in "..self.resultsLeft.." s.")or "")
   self:fitHUD();self:refreshLeaders(mine);self.needsHUD=false;return
  end
  -- Only what matters now: a message, how a running order ended, an air landing on its way, the target
  -- of an attack. Nothing when all is calm (the panel then shrinks to its title line and progress bar).
  -- How the last order ended shows for a few seconds, not for the rest of the match.
  if mine.lastOrderEnd~=self.seenOrderEnd then self.seenOrderEnd=mine.lastOrderEnd;self.orderEndAt=os.clock()end
  local ended=mine.lastOrderEnd and os.clock()-(self.orderEndAt or 0)<6 and messages[mine.lastOrderEnd]
  local text=not mine.alive and messages.defeated or self.message or ended or ""
  if text==""and mine.alive and(mine.transportCount or 0)>0 and not mine.advancing then
   text="In flight: "..mine.transportCount.." · "..compact(mine.transportFleet).." fleet"
  end
  if text==""and mine.alive and mine.advancing then
   -- Several attacks can run at once: the latest is named, the rest counted.
   local enemy=mine.attackOwner and self.factions[mine.attackOwner]
   local attacks=0;for _,front in ipairs(self.fronts or {})do if front.mode=="attack"then attacks+=1 end end
   text=enemy and("Attacking: "..enemy.name..(attacks>1 and(" and "..(attacks-1).." more")or""))or ""
  end
  self.status.Text=text
 end
 self:fitHUD()
 self:refreshLeaders(mine)
 self.needsHUD=false
end
-- Match time left (R.MatchSeconds of match time; then the largest country wins), as m:ss.
function View:timeLeftText()
 local left=math.max(0,Rules.MatchSeconds-((self.battle and self.battle.time)or 0))
 return string.format("%d:%02d",left//60,math.floor(left%60))
end
-- Share of all water on the map, with precision that still moves for small countries.
function View:share(count)
 local v=(count or 0)/math.max(1,self.grid.data.stats.waterCells)*100
 if v>0 and v<.01 then return "<0.01%"end
 return(v>=10 and string.format("%.0f",v)or v>=1 and string.format("%.1f",v)or string.format("%.2f",v))..'%'
end
function View:refreshLeaders(mine)
 local ranked={}
 for _,f in ipairs(self.factions)do if f.alive and(f.count or 0)>0 then table.insert(ranked,f)end end
 table.sort(ranked,function(a,b)if a.count~=b.count then return a.count>b.count end;return a.id<b.id end)
 local myRank;for i,f in ipairs(ranked)do if f.id==self.playerId then myRank=i;break end end
 local settings=self.battle and self.battle.settings or {}
 local goal=settings.winShare or .65
 local water=self.grid.data.stats.waterCells
 self.progressFill.Size=UDim2.fromScale(math.clamp((mine.count or 0)/(water*goal),0,1),1)
 self.progress.Visible=self.phase~="choosing"
 self.leaderTitle.Text="LEADERS · "..#ranked..(self.compact and ""or(#ranked==1 and " COUNTRY"or " COUNTRIES"))
 local sub="Victory: "..math.floor(goal*100+.5).."% of the water"..(self.phase=="playing"and(" · "..self:timeLeftText())or"")
 if settings.teams then
  local teams={0,0};for _,f in ipairs(ranked)do local t=f.team==1 and 1 or 2;teams[t]+=f.count end
  sub..="  ·  teams "..self:share(teams[1]).." / "..self:share(teams[2])
 end
 -- (a phone already shows the time in the status line: there only the goal)
 self.leaderSub.Text=self.compact and("goal "..math.floor(goal*100+.5).."%")or sub
 local g=self.leaderGeo or {w=234,row=22,top=48}
 local phone=self.compact==true
 -- A computer: the top ten and your place. A phone: as many rows as fit between the top bar and the
 -- command strip (3 to 10), your place always last when it is lower.
 local rows=10
 if phone then
  local barTop=self.battleUI and self.battleUI.bar and self.battleUI.bar.top or self.gui.AbsoluteSize.Y-70
  local avail=barTop-10-self.leaderboard.Position.Y.Offset
  rows=math.clamp(math.floor((avail-g.top-10-(myRank and 14 or 0))/g.row),3,10)
 end
 local shown={};local gap=false
 local first=(myRank and myRank>rows and phone)and rows-1 or rows
 for i=1,math.min(first,#ranked)do table.insert(shown,{rank=i,f=ranked[i]})end
 if myRank and myRank>first then table.insert(shown,{rank=myRank,f=ranked[myRank]});gap=phone end
 local accent=Color3.fromRGB(111,208,186);local muted=Color3.fromRGB(150,173,178)
 local medals={Color3.fromRGB(255,196,84),Color3.fromRGB(205,215,226),Color3.fromRGB(222,146,96)}
 local y=g.top
 for i,row in ipairs(self.leaderRows)do
  local entry=shown[i];row.Visible=entry~=nil
  if entry then
   local f=entry.f;local own=f.id==self.playerId;row:SetAttribute("Country",f.id)
   if gap and i==#shown then
    self.leaderGap.Position=UDim2.fromOffset(0,y-1);y+=14
   end
   row.Position=UDim2.fromOffset(8,y);y+=g.row
   row.Dot.BackgroundColor3=Color3.fromRGB(table.unpack(f.color))
   -- (a worn flag stands in the dot's place)
   Flags.set(row.Flag,f.flag);row.Dot.Visible=not row.Flag.Visible
   row.CountryName.Text=(own and "★ "or "")..f.name;row.Share.Text=self:share(f.count)
   local color=own and accent or white
   row.CountryName.TextColor3=color;row.Share.TextColor3=color
   row.CountryName.Font=own and Enum.Font.GothamBold or Enum.Font.Gotham
   if phone then
    -- Places 1-3 on gold, silver and bronze badges, the others plain; your row tinted.
    local medal=medals[entry.rank]
    row.Rank.Text=tostring(entry.rank)
    row.Rank.BackgroundColor3=medal or Color3.fromRGB(32,50,63);row.Rank.BackgroundTransparency=medal and 0 or 1
    row.Rank.TextColor3=medal and Color3.fromRGB(20,24,30)or muted
    row.Share.Font=Enum.Font.GothamBold
    row.BackgroundColor3=accent;row.BackgroundTransparency=own and .82 or 1
   else
    row.Rank.Text=entry.rank..".";row.Rank.TextColor3=muted;row.Rank.BackgroundTransparency=1
    row.Share.Font=Enum.Font.Gotham
    row.BackgroundColor3=Color3.fromRGB(255,255,255);if not own then row.BackgroundTransparency=1 end
   end
  end
 end
 self.leaderGap.Visible=gap
 self.leaderboard.Size=UDim2.fromOffset(g.w,y+(phone and 8 or 6))
 self.leaderboard.Visible=#ranked>0 and(self.compact and self.showLeaders==true or not self.compact and not self.hideLeaders)and not self.lobbyCovered
end
function View:isUI(obj)
 if self.lobby and self.lobby:isUI(obj)then return true end
 if self.battleUI and self.battleUI:isUI(obj)then return true end
 if self.leaderboard.Visible and(obj==self.leaderboard or obj:IsDescendantOf(self.leaderboard))then return true end
 if self.fightsPanel.Visible and(obj==self.fightsPanel or obj:IsDescendantOf(self.fightsPanel))then return true end
 return obj==self.panel or obj:IsDescendantOf(self.panel)
end
function View:nearStart(cell)
 if not cell then return nil end
 local best,distance=nil,math.huge
 for dy=-3,3 do for dx=-3,3 do
  local c=self.grid:cell(cell.x+dx,cell.y+dy)
  if c and self:isCoast(c.id) and self:owner(c.id)==0 and dx*dx+dy*dy<distance then best,distance=c,dx*dx+dy*dy end
 end end
 return best
end
-- One request at a time; a tap made meanwhile is kept (the latest wins) and sent right after, never dropped.
function View:send(action,value)
 if self.busy then self.queuedCommand={action,value};self.message="Sending…";self.needsHUD=true;return end
 -- "New match": back to the lobby. A solo match is dropped; from an online match the player goes back
 -- to a lobby server (the country plays on under the AI).
 if action=="restart"then
  if self.source=="server"and self.lobby and self.lobby:role()=="match"then action="leave"
  else if self.lobby then self.lobby:open('menu')end;return end
 end
 self.busy=true
 task.spawn(function()
  local ok,r
  if self.source=="solo"then ok,r=true,self.localMatch:command(action,value)
  else ok,r=pcall(function()return self.remote:InvokeServer(action,value)end)end
  if ok then
   if r.snapshot then self:incoming(r.snapshot)end
   Sfx.reply(action,r.ok==true,r.reason)
   self.message=BattleView.reasons[r.reason]or messages[r.reason] or (r.ok and "Done." or "Not available.")
   -- A refused order is also a notice, so it is seen wherever the eyes are.
   if not r.ok and self.battleUI then self.battleUI:toast(self.message,'bad')end
   if r.ok and r.reason=='allied'and self.battleUI then self.battleUI:toast(self.message,'good',nil,'alliance')end
   -- (the newcomer's tutorial follows the orders it asks for)
   local tutorial=self.lobby and self.lobby.tutorial
   if tutorial then tutorial:onCommand(action,value,r.ok==true)end
  else self.message="No answer from the server. Try again."end
  self.busy=false;self.needsHUD=true
  local nextOne=self.queuedCommand;self.queuedCommand=nil
  if nextOne then self:send(nextOne[1],nextOne[2])end
 end)
end
-- The country under the mouse (Atlas calls this every frame; nil = none): its highlight waits a moment
-- for the pointer to rest (a short delay), the card follows the cursor at once.
local HOVER_DELAY=.08
local HOVER_FILL_MAX=30000 -- larger countries highlight only their border (a fill means every cell)
function View:hover(cell,screen)
 local o=0
 if cell and cell.water and self.phase=="playing"and self.playerId and not self.lobbyCovered then
  o=self:owner(cell.id);if o==self.playerId then o=0 end
 end
 if o~=self.hoverWanted then self.hoverWanted=o;self.hoverAsked=os.clock()end
 self.hoverScreen=screen
 -- (any cell under the mouse, for the build / missile aim preview: BattleView:updateAim)
 self.pointerCell=cell
end
function View:setHover(o)
 local old=self.hoverOwner or 0;if o==old then return end
 self.hoverOwner=o;local f=self.factions[o];self.hoverFill=f~=nil and(f.count or 0)<=HOVER_FILL_MAX
 -- Repainted over the next frames (a big country is tens of thousands of cells).
 self.hoverQueue=self.hoverQueue or {}
 for _,owner in ipairs({old,o})do
  if owner>0 then for id in pairs(self.owned[owner]or {})do table.insert(self.hoverQueue,id)end end
 end
end
function View:updateHover()
 local wanted=self.hoverWanted or 0
 if wanted~=(self.hoverOwner or 0)and os.clock()-(self.hoverAsked or 0)>=HOVER_DELAY then self:setHover(wanted)end
 local q=self.hoverQueue
 if q and #q>0 then
  local n=math.min(#q,6000)
  for i=#q,#q-n+1,-1 do self:mark(q[i]);q[i]=nil end
 end
 -- The card: shown at once for the country under the cursor (none while a country card is open).
 local tip=self.tip;local o=wanted;local f=o>0 and self.factions[o]
 local ui=self.battleUI
 if not f or not self.hoverScreen or(ui and ui.card.Visible)then tip.Visible=false;return end
 local key=o..":"..tostring(f.fleet)..":"..tostring(f.count)..":"..tostring(ui and ui.mode~=nil)
 if key~=self.tipKey then
  self.tipKey=key
  local color=Color3.fromRGB(table.unpack(f.color))
  tip.Owner.Color=color;tip.Head.Swatch.BackgroundColor3=color;tip.Head.Title.Text=f.name
  local user;for u,id in pairs(self.battle and self.battle.clients or {})do if id==o and tonumber(u)then user=tonumber(u)end end
  local face=user~=nil or f.persona==true
  tip.Head.Avatar.Visible=face;tip.Head.Swatch.Visible=not face
  if face then showAvatar(tip.Head.Avatar,user,f.persona,f.look)end
  tip.Info.Text="Fleet "..compact(f.fleet or 0).."  ·  "..self:share(f.count).." of the water"
  local allied=ui and ui:allied(o);local war=self.playerId and self.hot[pairKey(self.playerId,o)]
  -- Where it stands with you. A bot's kind (tribe, kind of nation) is internal logic and not shown.
  tip.Relation.Text=allied and "Ally"or war and "At war"or "Neutral country"
  tip.Relation.TextColor3=allied and Color3.fromRGB(130,226,170)or war and Color3.fromRGB(242,140,140)or white
  tip.Hint.Visible=not(ui and ui.mode)
  tip.Hint.Text=allied and "Click: ally card"or "Click: attack  ·  Right-click: alliance or attack"
 end
 local origin=self.gui.AbsolutePosition;local size=self.gui.AbsoluteSize;local p=self.hoverScreen-origin
 local w,h=tip.AbsoluteSize.X,tip.AbsoluteSize.Y
 local x=p.X+16;if x+w>size.X-6 then x=p.X-16-w end
 local y=math.clamp(p.Y+18,6,math.max(6,size.Y-h-6))
 tip.Position=UDim2.fromOffset(math.floor(x),math.floor(y));tip.Visible=true
end
function View:click(cell,touch)
 if not cell then return end
 if self.battleUI then self.battleUI:closeCard()end
 if self.battleUI and self.battleUI:click(cell)then return end
 -- During an online countdown the coast is already picked: the match itself has not begun.
 if self.phase=="countdown"and self.playerId then return end
 if self.phase=="choosing"or self.phase=="countdown"or not self.playerId then
  -- A start is chosen only from the lobby's start-picking step; a spectator's clicks do nothing.
  if not(self.lobby and self.lobby.mode=='spawn')then return end
  local start=self:nearStart(cell)
  if start then self:send("start",start.id)
  else self.message=messages.coast_required;self.needsHUD=true end
 elseif cell.water then
  local enemy=self:owner(cell.id)
  -- Another country: a card with its forces offers alliance or attack instead of attacking at once.
  -- With a mouse another country is attacked at once with the current share; an ally
  -- gets its card (break the alliance, donate). A tap opens any country's card (alliance or attack),
  -- as do a right-click and a long press.
  if enemy>0 and enemy~=self.playerId and(touch or self.battleUI:allied(enemy))then self.battleUI:openCard(enemy,cell);return end
  self:send("capture",cell.id)
 else self.message="You can only expand over water.";self.needsHUD=true end
end
-- Right-click / long press: an armed order is cancelled; on another country's water its card opens
-- (alliance, attack, donate); anywhere else the selection is cleared.
function View:contextClick(cell)
 local ui=self.battleUI;if not ui then return end
 if ui.mode then ui:clearSelection();return end
 local enemy=cell and cell.water and self.playerId and self.phase=="playing"and self:owner(cell.id)or 0
 if enemy>0 and enemy~=self.playerId then ui:openCard(enemy,cell)else ui:clearSelection()end
end
function View:playing()return self.playerId~=nil and self.phase=="playing"end
-- Q / E: the attack share one step down or up (25 / 40 / 50 / 60 / 75%).
local SHARES=Rules.AttackShares
function View:stepShare(dir)
 if not self:playing()then return end
 local f=self.factions[self.playerId];local now=f and f.ratio or Rules.AttackShare
 local best=1
 for i,v in ipairs(SHARES)do if math.abs(v-now)<math.abs(SHARES[best]-now)then best=i end end
 local nextOne=SHARES[math.clamp(best+dir,1,#SHARES)]
 if nextOne~=SHARES[best]or math.abs(nextOne-now)>.001 then self:send("ratio",nextOne)end
end
-- Tab (or a tap on the status line on a phone): the leaderboard shown or hidden. A phone keeps it
-- closed until asked, a computer shows it until hidden.
function View:toggleLeaders()
 if self.compact then self.showLeaders=not self.showLeaders else self.hideLeaders=not self.hideLeaders end
 self:refreshHUD()
end
-- The marks' frame starts where WorldToScreenPoint counts from. That is not the screen's corner: on an
-- iPhone in landscape the camera viewport begins past the notch or Dynamic Island (about
-- 47-62 px), and WorldToScreenPoint also leaves out the top bar. Version 43 put the frame at the
-- screen's left and version 44 measured only the top bar (WorldToViewportPoint minus WorldToScreenPoint
-- is the same viewport both ways): every mark sat that side inset too far left, which looks worse the
-- further out the map is zoomed. AbsolutePosition uses WorldToScreenPoint's origin, so the full-screen
-- `hold`'s AbsolutePosition is the screen's corner there, and minus it moves the frame onto that origin.
function View:placeMarks()
 local corner=self.markHold.AbsolutePosition
 if corner~=self.markCorner then
  self.markCorner=corner;self.marks.Position=UDim2.fromOffset(-corner.X,-corner.Y)
 end
end
function View:update(camera,zoom,dt)
 self:placeMarks()
 -- Roblox's top bar or the screen's corner moved (the bar shows up late, a phone turns): lay out again.
 local bar=self.barProbe.AbsoluteSize;local corner=self.barProbe.AbsolutePosition-self.gui.AbsolutePosition
 if bar~=self.barSeen or corner~=self.cornerSeen then
  self.barSeen=bar;self.cornerSeen=corner;self.lastLayoutSize=nil
  if self.lobby then self.lobby.lastSize=nil end
 end
 self:updateHover()
 -- The territory image (a SurfaceGui) is drawn as if raised by ~0.2% of the camera distance, so
 -- parts just above it would vanish; overlays ride a little higher (a pixel or two of parallax).
 local lift=camera.CFrame.Position.Y*OVERLAY_LIFT
 if not self.overlayLift or math.abs(lift-self.overlayLift)>self.overlayLift*.15 then self.overlayLift=lift end
 if self.battleUI then self.battleUI:update(camera,dt)end
 if self.lobby then
  self.lobby:update(dt)
  -- The lobby picks what the map shows (Lobby:source); the local match runs while shown.
  local wanted=self.lobby:source()
  if wanted~="server"and self.localMatch.failed then wanted="server"end
  self:setSource(wanted)
  if self.source~="server"then self.localMatch:update(dt)end
  -- The lobby and the start banner replace the match status, the leaderboard and the list.
  local covered=self.lobby:covers()
  self.panel.Visible=not covered
  if covered then self.leaderboard.Visible=false end
  if covered~=self.lobbyCovered then self.lobbyCovered=covered;self.needsHUD=true end
 end
 self.clock+=dt
 local now=os.clock()
 local pending=self.pending
 while self.pendingHead<=#pending and pending[self.pendingHead+2]<=now do
  local head=self.pendingHead;self.pendingHead+=3;self:setCell(pending[head],pending[head+1])
 end
 if self.pendingHead>#pending then table.clear(pending);self.pendingHead=1 end
 local pixelWorld=2*camera.CFrame.Position.Y*math.tan(math.rad(camera.FieldOfView/2))/math.max(1,camera.ViewportSize.Y)
 self.pixelWorld=pixelWorld
 local thickness=math.clamp(pixelWorld, .018,.12)
 if not self.borderWidth or math.abs(thickness-self.borderWidth)>self.borderWidth*.25 then
  self.borderWidth=thickness
  for _,chunk in pairs(self.chunks)do for _,obj in ipairs(chunk.pool)do
   local axis=obj:GetAttribute("BorderAxis");local width=thickness*(obj:GetAttribute("Front")and FRONT_WIDTH or 1)
   if axis=="X"then obj.Size=Vector3.new(width,.002,obj.Size.Z)
   elseif axis=="Z"then obj.Size=Vector3.new(obj.Size.X,.002,width)end
  end end
 end
 self.frontClock+=dt
 if self.frontClock>.3 then self.frontClock=0;self:updateFrontLabels(camera)end
 self.fightsClock=(self.fightsClock or 0)+dt
 if self.fightsClock>.3 then self.fightsClock=0;self:updateFights()end
 for _,front in ipairs(self.fronts)do
  local anchor=self.frontAnchors and self.frontAnchors[front.key]
  local label=self.frontLabels[front.key]
  if not label then
   -- Bare bold number with a black outline, no plate (the front's troop label).
   label=ui("TextLabel",self.marks,{Name="FrontForces",BackgroundTransparency=1,TextColor3=white,TextSize=17,Font=Enum.Font.GothamBold,
    AutomaticSize=Enum.AutomaticSize.XY,Size=UDim2.fromOffset(0,0),AnchorPoint=Vector2.new(.5,.5),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3,Visible=false})
   ui("UIStroke",label,{Color=Color3.new(0,0,0),Thickness=1.5,LineJoinMode=Enum.LineJoinMode.Round})
   self.frontLabels[front.key]=label
  end
  local text,color=self:frontText(front)
  if label.Text~=text then label.Text=text end;label.TextColor3=color
  if anchor then
   local p,visible=camera:WorldToScreenPoint(anchor)
   label.Position=UDim2.fromOffset(p.X,p.Y);label.Visible=visible
  else label.Visible=false end
 end
 if self.image then self.image:flush()end
 local began=os.clock();local rendered=0
 while self.dirtyHead<=#self.dirtyQueue and rendered<16 do
  local key=self.dirtyQueue[self.dirtyHead];self.dirtyHead+=1
  local location=self.dirty[key];self.dirty[key]=nil
  if location then self:renderChunk(key,location);rendered+=1 end
  if os.clock()-began>.006 then break end
 end
 if self.dirtyHead>#self.dirtyQueue then self.dirtyQueue={};self.dirtyHead=1 end
 self.labelClock+=dt
 if self.labelsDirty and self.labelClock>1 then self.labelClock=0;self:refreshLabels()end
 -- Country names follow the camera; with a still camera twice a second is enough for fleet numbers.
 self.nameClock=(self.nameClock or 0)+dt
 local namesDue=camera.CFrame~=self.lastNameCamera or camera.ViewportSize~=self.lastNameViewport or self.nameClock>=.5 or self.namesCovered~=self.lobbyCovered
 self.namesCovered=self.lobbyCovered
 if namesDue then self.lastNameCamera=camera.CFrame;self.lastNameViewport=camera.ViewportSize;self.nameClock=0;self:placeNames(camera,pixelWorld)end
 -- The timer in the heading moves once a second.
 local second=self.battle and math.floor(self.battle.time or 0)
 if second~=self.shownSecond then self.shownSecond=second;self.needsHUD=true end
 if self.needsHUD then self:refreshHUD()end
 if self.clock>5 then self.clock=0;self.message=nil;self.needsHUD=true end
 self:layout(camera.ViewportSize)
end
-- Country names: size by area, hide where they would cover panels or larger neighbours.
function View:placeNames(camera,pixelWorld)
 -- Behind the lobby and the start banner the map shows no country names.
 if self.lobbyCovered then
  for _,obj in pairs(self.countryLabels)do obj.Visible=false;local st=self.nameState and self.nameState[obj];if st then st.visible=false end end
  return
 end
 -- Larger countries claim label space first; labels never cover panels or each other.
 local origin=self.marks.AbsolutePosition;local blocked={}
 for _,c in ipairs(self.gui:GetChildren())do
  if c:IsA("GuiObject")and c.Visible and c.BackgroundTransparency<1 and not c:GetAttribute("Marker")then
   local p=c.AbsolutePosition-origin;table.insert(blocked,{p.X,p.Y,p.X+c.AbsoluteSize.X,p.Y+c.AbsoluteSize.Y})
  end
 end
 local candidates={}
 -- Which country belongs to which person (UserId), for the avatars.
 local users={}
 for user,id in pairs(self.battle and self.battle.clients or {})do if tonumber(user)then users[id]=tonumber(user)end end
 -- Each label remembers what it was given (self.nameState) and Roblox is written only what changed;
 -- the text's measured size is read again only after the text or its size changed. (2026-11-15: an
 -- online match has eighty labels, many with avatars and flags, and every refresh re-set and re-read
 -- all of them: a 7 ms frame twice a second on a computer, several times that on a phone.)
 local states=self.nameState;if not states then states=setmetatable({},{__mode='k'});self.nameState=states end
 local function show(st,obj,on)if st.visible~=on then st.visible=on;obj.Visible=on end end
 local now=os.clock()
 for id,obj in pairs(self.countryLabels)do
  local st=states[obj];if not st then st={};states[obj]=st end
  local a=self.anchors[id];local f=self.factions[id]
  if not a or not f or f.count==0 then show(st,obj,false);continue end
  local c=self.grid:getCell(a.cell);local pos=self.grid:cellToWorld(c.x,c.y)
  local p,visible=camera:WorldToScreenPoint(pos)
  local width=math.min(a.width*.9,math.sqrt(a.area)*1.7)*self.grid.data.tileSize/pixelWorld
  local fontsize=math.clamp(width/math.max(4,utf8.len(f.name)*.58),8,30)
  if not(visible and width>=26)then show(st,obj,false);continue end
  local text=f.name.."\nFleet "..compact(f.fleet or 0);fontsize=math.floor(fontsize+.5)
  if st.text~=text then st.text=text;obj.Text=text;st.bounds=nil end
  if st.fontsize~=fontsize then st.fontsize=fontsize;obj.TextSize=fontsize;st.bounds=nil end
  local size=UDim2.fromOffset(math.floor(math.max(width,fontsize*utf8.len(f.name)*.65)),math.floor(fontsize*2.8))
  if st.size~=size then st.size=size;obj.Size=size;st.bounds=nil end
  local at=UDim2.fromOffset(math.floor(p.X+.5),math.floor(p.Y+.5))
  if st.at~=at then st.at=at;obj.Position=at end
  -- Rendered text can be wider than the label frame (the fleet line), so measure the text itself.
  local bounds=st.bounds;if not bounds then bounds=obj.TextBounds;st.bounds=bounds end
  if st.face==nil then st.face=obj:FindFirstChild("Avatar")or false;st.flag=obj:FindFirstChild("Flag")or false end
  local face,extra=st.face,0
  if face then
   local user=users[id];local shown=user~=nil or f.persona==true
   if st.faceShown~=shown then st.faceShown=shown;face.Visible=shown end
   if shown then
    -- (the avatar is looked at again when its owner changes, and every 3 s for a generated one)
    local who=tostring(user)..':'..tostring(f.persona)..':'..tostring(f.look)
    if st.faceFor~=who or now-(st.faceAt or 0)>3 then st.faceFor=who;st.faceAt=now;showAvatar(face,user,f.persona,f.look)end
    -- As tall as the name, just before it on the name's line (the top one of the two).
    local side=fontsize+2;local nameWidth=self:textWidth(f.name,fontsize);extra=side+3
    local fs,fp=UDim2.fromOffset(side,side),UDim2.new(.5,-math.floor(nameWidth/2)-3,.5,-math.floor(bounds.Y/4))
    if st.faceSize~=fs then st.faceSize=fs;face.Size=fs end
    if st.facePos~=fp then st.facePos=fp;face.Position=fp end
   end
  end
  local flag=st.flag
  if flag then
   if st.flagId~=f.flag then st.flagId=f.flag;Flags.set(flag,f.flag);st.flagShown=flag.Visible end
   if st.flagShown then
    local fh=math.max(8,math.floor(fontsize*.8));local fw=math.floor(fh*Flags.Aspect+.5);local nameWidth=self:textWidth(f.name,fontsize)
    local gs,gp=UDim2.fromOffset(fw,fh),UDim2.new(.5,math.floor(nameWidth/2)+4,.5,-math.floor(bounds.Y/4))
    if st.flagSize~=gs then st.flagSize=gs;flag.Size=gs end
    if st.flagPos~=gp then st.flagPos=gp;flag.Position=gp end
    extra=math.max(extra,fw+4)
   end
  end
  -- The avatar sits left of the text: the label's box grows by it on both sides (it stays centred).
  table.insert(candidates,{obj=obj,st=st,area=a.area,x=p.X,y=p.Y,w=math.max(bounds.X,fontsize*2)+6+extra*2,h=math.max(bounds.Y,fontsize*2.2)})
 end
 table.sort(candidates,function(a,b)return a.area>b.area end)
 for _,c in ipairs(candidates)do
  local box={c.x-c.w/2,c.y-c.h/2,c.x+c.w/2,c.y+c.h/2};local free=true
  for _,o in ipairs(blocked)do if box[1]<o[3]and box[3]>o[1]and box[2]<o[4]and box[4]>o[2]then free=false;break end end
  show(c.st,c.obj,free);if free then table.insert(blocked,box)end
 end

end
-- Fly the camera to a cell (Atlas listens for FocusCell; cleared first so the same cell flies again).
function View:focusCell(cell)
 if not cell then return end
 self.gui:SetAttribute("FocusCell",nil);self.gui:SetAttribute("FocusCell",cell)
end
-- Fly to a country: the middle of its largest stretch of water (the name's spot), else its start.
function View:focusCountry(id)
 local f=id and self.factions[id];if not f then return end
 local anchor=self.anchors[id]
 local cell=anchor and anchor.cell or f.startCell or next(self.owned[id]or {})
 self:focusCell(cell)
end
-- A cell on the front line with `enemy` (updateFrontLabels keeps one point per front).
function View:frontCell(enemy)
 local me=self.playerId;if not me then return nil end
 local point=self.frontAnchors and self.frontAnchors[pairKey(me,enemy)]
 local cell=point and self.grid:worldToCell(point)
 if cell then return cell.id end
 local f=self.factions[enemy];return f and f.startCell
end
function View:updateFights()
 local me=self.playerId and self.factions[self.playerId]
 local rows={}
 if me and me.alive then
  if me.expanding then
   -- (the fleet in expansion: all committed fleet less the attacks and the transports in flight)
   local fleet=(me.committed or 0)-(me.transportFleet or 0)
   for _,front in ipairs(self.fronts or {})do if front.mode=="attack"then fleet-=front.mine or 0 end end
   table.insert(rows,{icon="waves",text="Expanding · "..compact(math.max(0,fleet)).." fleet",color=Color3.fromRGB(111,208,186),cell=self.lastExpansion})
  end
  for _,front in ipairs(self.fronts or {})do
   local e=self.factions[front.enemy];local name=e and e.name or "?"
   if front.mode=="attack"then
    table.insert(rows,{icon="swords",text=name.." · "..compact(front.mine).." vs "..compact(front.theirs),color=OUTGOING,cell=self:frontCell(front.enemy)})
   else
    table.insert(rows,{icon="shield",text="Against you: "..name.." · "..compact(front.theirs),color=INCOMING,cell=self:frontCell(front.enemy)})
   end
  end
 end
 -- (on a phone the open leaderboard fills the side: the fights wait until it is closed)
 local show=#rows>0 and not self.lobbyCovered and self.phase=="playing"and not(self.compact and self.leaderboard.Visible)
 self.fightsPanel.Visible=show
 if not show then return end
 local open=not self.fightsFolded
 self.fightsTitle.Text="BATTLES · "..#rows;self.fightsToggle.Text=open and "–"or "+"
 for i,row in ipairs(self.fightRows)do
  local r=rows[i];row.Visible=open and r~=nil
  if r then row.Label.Text=r.text;row.Label.TextColor3=r.color;row:SetAttribute("Cell",r.cell);Icons.lead(row.Label,r.icon,{color=r.color})end
 end
 local n=open and math.min(#rows,#self.fightRows)or 0
 local lb=self.leaderboard
 -- Half as wide as the leaderboard (at least 170), right-aligned under it when it is shown, at its
 -- place otherwise.
 local lbW=lb.Size.X.Offset;local w=math.max(170,math.floor(lbW/2))
 self.fightsPanel.Size=UDim2.fromOffset(w,30+n*26+(n>0 and 4 or 0))
 local y=lb.Visible and(lb.AbsolutePosition.Y-self.gui.AbsolutePosition.Y+lb.AbsoluteSize.Y+8)or lb.Position.Y.Offset
 self.fightsPanel.Position=UDim2.new(1,lb.Position.X.Offset+lbW-w,0,y)
end
-- Phones (landscape ~844×390, portrait ~390×844) get a compact layout:
-- a slim status bar top-right, the action panel docked left, everything else on demand.
function View.isCompact(size)return size.X<900 or size.Y<520 end
-- Width of a country name in the labels' font (cached: measured once per name and size).
function View:textWidth(text,size)
 self.widths=self.widths or {};local key=size..":"..text
 local w=self.widths[key]
 if not w then
  w=game:GetService("TextService"):GetTextSize(text,size,Enum.Font.GothamBold,Vector2.new(10000,10000)).X;self.widths[key]=w
 end
 return w
end
-- The match line, after the avatar when it is shown.
function View:placeHeading()
 local right=self.hudRight or 300;local small=self.compact==true
 local h=small and 22 or 28;local side=small and 18 or 24;local inset=self.avatar.Visible and side+6 or 0;local top=small and 5 or 9
 -- The avatar as tall as the line's text, centred on it; the stats at the right end, the name between.
 self.avatar.Size=UDim2.fromOffset(side,side);self.avatar.Position=UDim2.fromOffset(10,top+math.floor((h-side)/2))
 local statsW=self.stats.Text~=""and self.stats.TextBounds.X+12 or 0
 self.stats.Size=UDim2.fromOffset(right-20,h);self.stats.Position=UDim2.fromOffset(10,top)
 self.heading.Size=UDim2.fromOffset(math.max(20,right-20-inset-statsW),h);self.heading.Position=UDim2.fromOffset(10+inset,top)
end
function View:layout(size)
 -- Positions depend only on the screen size.
 if size==self.lastLayoutSize then if self.compact and not self.showLeaders then self.leaderboard.Visible=false end;return end
 self.lastLayoutSize=size
 local compactMode=View.isCompact(size);self.compact=compactMode
 local right=compactMode and math.min(360,size.X-60)or 420
 -- On a phone the status line and the pause button go up into Roblox's own top bar, level with its
 -- buttons and to the right of them (the map gets that height back).
 local bar=self:topbar();local tb=compactMode and bar
 local pauseW=42
 self.pauseSpot=nil
 if tb then
  -- (the pause button keeps the same 12-point gap from Roblox's last button as theirs have)
  self.pauseSpot=Vector2.new(tb.x0+12,math.floor(tb.mid-pauseW/2))
  right=math.max(160,math.min(right,tb.x1-12-(tb.x0+12+pauseW+10)))
 elseif bar then
  -- A computer: only the round buttons (pause, and the Atlas's "?" after it) go up into the top bar,
  -- level with Roblox's own; the status panel stays where it was.
  self.pauseSpot=Vector2.new(bar.x0+12,math.floor(bar.mid-pauseW/2))
 end
 self.panel.AnchorPoint=compactMode and Vector2.new(1,0)or Vector2.zero
 self.panel.Position=tb and UDim2.fromOffset(tb.x1-12,math.floor(tb.mid-20))
  or compactMode and UDim2.new(1,-8,0,8)or UDim2.fromOffset(24,20)
 self.panel.Size=UDim2.fromOffset(right,compactMode and 40 or 58)
 self.heading.TextSize=compactMode and 15 or 19;self.stats.TextSize=compactMode and 15 or 19
 self.hudRight=right;self:placeHeading()
 self.status.TextSize=compactMode and 12 or 14;self.status.TextWrapped=not compactMode
 self.status.TextTruncate=compactMode and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None
 self.status.Position=UDim2.fromOffset(10,compactMode and 27 or 41);self.status.Size=UDim2.fromOffset(right-20,compactMode and 18 or 30)
 self.progress.Size=UDim2.fromOffset(right-20,compactMode and 4 or 6);self:fitHUD()
 -- On a phone the leaderboard opens from the status line, under it.
 self.leadersTap.Visible=compactMode
 -- On a computer it starts in Roblox's top bar, its top level with the round buttons there.
 local below=tb and(math.floor(tb.mid-20)+58+8)or compactMode and 74 or self.pauseSpot and self.pauseSpot.Y or 64
 local g=self:placeLeaders(compactMode)
 local lbRight=tb and(size.X-(tb.x1-12))or 8
 self.leaderboard.Position=compactMode and UDim2.new(1,-(g.w+lbRight),0,below)or UDim2.new(1,-(g.w+24),0,below)
 self.leaderboard.Size=UDim2.fromOffset(g.w,math.min(g.top+6+11*g.row,size.Y-below-8))
 if compactMode and not self.showLeaders then self.leaderboard.Visible=false end
 self.needsHUD=true
end
-- The free part of Roblox's top bar (right of its buttons) in this interface's offsets, or nil when there
-- is none. A full-size frame in a ScreenGui with ScreenInsets.TopbarSafeInsets covers exactly that part;
-- its AbsolutePosition minus the interface's is the offset (works past a notch too).
function View:topbar()
 local p=self.barProbe;if not p then return nil end
 local size=p.AbsoluteSize
 if size.Y<36 or size.X<200 then return nil end
 local pos=p.AbsolutePosition-self.gui.AbsolutePosition
 -- `mid`: the line through the middle of Roblox's own buttons (44-point circles 12 points under the bar's
 -- top, so their centre is 24 points above its bottom), to put ours level with them.
 return {x0=pos.X,x1=pos.X+size.X,y=pos.Y,h=size.Y,mid=pos.Y+math.max(size.Y/2,size.Y-24)}
end
-- The leaderboard's sizes: compact on a phone, larger on a computer (wider rows, bigger text).
function View:placeLeaders(compactMode)
 -- A phone: a card with a header (trophy, title, goal, close), badges for the places and bigger rows.
 local g=compactMode and {w=290,row=30,top=48,title=14,sub=12,text=14,dot=10}
  or {w=340,row=30,top=66,title=16,sub=13,text=15,dot=10}
 self.leaderGeo=g
 for _,o in ipairs({self.leaderIcon,self.leaderClose,self.leaderLine})do o.Visible=compactMode end
 if compactMode then
  self.leaderTitle.TextSize=g.title;self.leaderTitle.Position=UDim2.fromOffset(36,8);self.leaderTitle.Size=UDim2.fromOffset(120,24)
  self.leaderSub.TextSize=g.sub;self.leaderSub.TextXAlignment=Enum.TextXAlignment.Right
  self.leaderSub.Position=UDim2.fromOffset(120,8);self.leaderSub.Size=UDim2.fromOffset(g.w-120-50,24)
  self.leaderClose.Position=UDim2.fromOffset(g.w-38,6)
 else
  self.leaderTitle.TextSize=g.title;self.leaderTitle.Position=UDim2.fromOffset(14,10)
  self.leaderTitle.Size=UDim2.fromOffset(g.w-28,g.title+6)
  self.leaderSub.TextSize=g.sub;self.leaderSub.TextXAlignment=Enum.TextXAlignment.Left
  self.leaderSub.Position=UDim2.fromOffset(14,36);self.leaderSub.Size=UDim2.fromOffset(g.w-28,g.sub+6)
 end
 local rowW=g.w-16;local rankW=compactMode and 22 or 30;local valueW=compactMode and 62 or 70
 for i,row in ipairs(self.leaderRows)do
  row.Position=UDim2.fromOffset(8,g.top+(i-1)*g.row);row.Size=UDim2.fromOffset(rowW,g.row-2)
  local h=g.row-2
  row.Rank.TextSize=compactMode and 12 or g.text
  if compactMode then
   row.Rank.Size=UDim2.fromOffset(rankW,rankW);row.Rank.Position=UDim2.fromOffset(4,math.floor((h-rankW)/2))
   row.Rank.TextXAlignment=Enum.TextXAlignment.Center
  else
   row.Rank.Size=UDim2.fromOffset(rankW,h);row.Rank.Position=UDim2.fromOffset(2,0);row.Rank.TextXAlignment=Enum.TextXAlignment.Right
  end
  local dotX=compactMode and rankW+12 or rankW+6
  row.Dot.Size=UDim2.fromOffset(g.dot,g.dot);row.Dot.Position=UDim2.fromOffset(dotX,math.floor((h-g.dot)/2))
  row.Flag.Position=UDim2.fromOffset(dotX-2,math.floor((h-10)/2))
  local nameX=dotX+g.dot+8
  row.CountryName.TextSize=g.text;row.CountryName.Position=UDim2.fromOffset(nameX,0);row.CountryName.Size=UDim2.fromOffset(rowW-nameX-valueW-8,h)
  row.Share.TextSize=g.text;row.Share.Position=UDim2.fromOffset(rowW-valueW-8,0);row.Share.Size=UDim2.fromOffset(valueW,h)
 end
 return g
end
return View
