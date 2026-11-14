--!nonstrict
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local StarterGui=game:GetService("StarterGui")
local shared=game:GetService("ReplicatedStorage"):WaitForChild("SeaBattle")
local data=require(shared.WorldData)
local grid=require(shared.WorldGrid).new(data)
local renderer=require(shared.WorldRenderer).new(grid)
local player=Players.LocalPlayer
local camera=workspace.CurrentCamera
camera.CameraType=Enum.CameraType.Scriptable
camera.FieldOfView=45
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All,false) end)
-- No chat window, input bar or bubbles (the place has them off too; the server delivers no message: server/NoTalk).
pcall(function()
	local tcs=game:GetService("TextChatService")
	for _,name in ipairs({"ChatWindowConfiguration","ChatInputBarConfiguration","BubbleChatConfiguration"}) do
		local c=tcs:FindFirstChildOfClass(name); if c then c.Enabled=false end
	end
end)

local Theme=require(shared.Theme)
local C={ink=Color3.fromRGB(12,29,43),panel=Theme.colors.panel,
	text=Theme.colors.text,muted=Theme.colors.muted,
	accent=Theme.colors.accent,line=Color3.fromRGB(54,85,96),
	sand=Color3.fromRGB(220,203,149)}
local gui=Instance.new("ScreenGui")
gui.Name="SeaBattleAtlas"
gui.IgnoreGuiInset=false
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=player:WaitForChild("PlayerGui")
-- Sound effects: every button made from here on gets its hover and click sound (shared/Sfx).
require(shared.Sfx).init(gui)
-- The world map is wide: phones play it in landscape.
pcall(function() player.PlayerGui.ScreenOrientation=Enum.ScreenOrientation.LandscapeSensor end)

local function make(class,parent,props)
	local obj=Instance.new(class)
	for key,value in pairs(props) do obj[key]=value end
	obj.Parent=parent
	return obj
end
local function frame(parent,pos,size,color)
	return make("Frame",parent,{Position=pos,Size=size,BackgroundColor3=color or C.panel,BorderSizePixel=0,ZIndex=3})
end
local function text(parent,value,pos,size,fontSize,color,font)
	return make("TextLabel",parent,{Text=value,Position=pos,Size=size,BackgroundTransparency=1,
		TextColor3=color or C.text,TextSize=fontSize or 14,Font=font or Enum.Font.Gotham,
		TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,
		BorderSizePixel=0,ZIndex=4})
end

local focus=Vector2.zero
local zoom=1
local height=2300
local selected=nil
local gameView=nil
local physical=true
local gridVisible=false
local touchPinching=false
local boundaries=nil
local tileGrid=nil
local selectionLift=nil
local selection=Instance.new("Folder")
selection.Name="SeaBattleSelection"
selection.Parent=workspace

local function surface(parent,name,x,z,sx,sz,color,alpha,y)
	local p=Instance.new("Part")
	p.Name=name
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=false
	p.CastShadow=false
	p.Material=Enum.Material.SmoothPlastic
	p.Size=Vector3.new(math.max(.004,sx),.002,math.max(.004,sz))
	p.Position=Vector3.new(x,y or .024,z)
	p.Color=color
	p.Transparency=alpha or 0
	p.Parent=parent
	return p
end

-- Merge consecutive boundary edges before creating local overlay geometry.
local function buildBoundaries()
 local root=Instance.new("Folder")
 root.Name="SeaBattleSectorBorders"
 local s=data.tileSize
 for index,edge in ipairs(data.boundaries or {}) do
  local x,y,length,vertical=table.unpack(edge)
  if vertical==0 then
   surface(root,"H",(x+length/2-data.width/2)*s,(y-data.height/2)*s,length*s,s*.35,C.accent,.57)
  else
   surface(root,"V",(x-data.width/2)*s,(y+length/2-data.height/2)*s,s*.35,length*s,C.accent,.57)
  end
  if index%750==0 then task.wait() end
 end
 return root
end

local layerBusy=false
-- T switches the water sectors overlay on and off (a developer view; no on-screen control).
local function toggleLayer()
	if layerBusy then return end
	layerBusy=true
	physical=not physical
	if not boundaries then boundaries=buildBoundaries() end
	boundaries.Parent=physical and nil or workspace
	layerBusy=false
end

-- Controls are explained in the help ("?", H); no hint bar over the map.

-- "How to play" over everything, the lobby included (shared/Guide); help.Visible shows and hides it.
local guide=require(shared.Guide).new(gui)
local help=guide.root
-- "?" on a computer: a round button like the pause button, next to it in Roblox's top bar (placed each frame).
local PauseMenu=require(shared.PauseMenu)
local helpButton=PauseMenu.round(gui,"HelpButton","help")
helpButton.Activated:Connect(function() help.Visible=not help.Visible end)

-- Background music (shared/Music, tracks in shared/Soundtrack): a round button beside "?" (in the lobby
-- the first in the bar) and the M key switch it; the choice is kept in the profile.
local Icons=require(shared.Icons)
local music=require(shared.Music).new()
music:setAfter('title')
local musicButton=PauseMenu.round(gui,"MusicButton","music")
local musicIcon=musicButton:FindFirstChildWhichIsA("ImageLabel",true)
-- (over the lobby, ZIndex 40..47, which otherwise takes its taps; under the shop and chest windows, 50+)
musicButton.ZIndex=48;if musicIcon then musicIcon.ZIndex=49 end
local musicFromProfile=false
local function showMusic()
	if musicIcon then Icons.set(musicIcon,music.enabled and "music" or "music_off") end
	musicButton.BackgroundTransparency=music.enabled and .12 or .35
end
local function toggleMusic()
	local on=music:toggle();showMusic()
	if gameView then task.spawn(function() pcall(function() gameView:request("music",{on=on}) end) end) end
end
musicButton.Activated:Connect(toggleMusic)
-- The mood for what is on screen: the lobby's title, waiting for an online match, a match at peace or at war
-- (a front with another country now, or in the last 40 s), the result.
local warUntil=0
local function musicMood()
	if not gameView then return "title" end
	local lobby=gameView.lobby
	if lobby and lobby.endShown then return lobby.endWon and "victory" or "defeat" end
	if gameView:playing() then
		for _,front in ipairs(gameView.fronts or {}) do
			if front.enemy and front.enemy~=0 then warUntil=os.clock()+40 break end
		end
		return os.clock()<warUntil and "war" or "calm"
	end
	local q=lobby and lobby.queue and lobby.queue.state
	if q=="queued" or q=="teleporting" then return "wait" end
	if gameView.source=="server" and gameView.phase~="playing" then return "wait" end
	if lobby and lobby.mode=="menu" then return "title" end
	return "calm"
end

-- A tapped cell gets a thin frame; everything else about it is in the country card and the notices.
local function choose(cell,preview)
	if preview then return end
	selection:ClearAllChildren();selected=cell
	if not cell then return end
	local pos=grid:cellToWorld(cell.x,cell.y)
	local s=data.tileSize
	for _,offset in ipairs({{0,-s/2,s,s*.06},{0,s/2,s,s*.06},{-s/2,0,s*.06,s},{s/2,0,s*.06,s}}) do
		surface(selection,"Cell",pos.X+offset[1],pos.Z+offset[2],offset[3],offset[4],C.sand,0,.032+(gameView and gameView.overlayLift or 0))
	end
end

gameView=require(shared.ConquestView).new(grid,gui)
-- the pause menu's "Music" row uses the same switch
gameView.musicToggle=toggleMusic
gameView.musicOn=function() return music.enabled end
-- The lobby's "How to play" opens the same help window.
gui:GetAttributeChangedSignal("HelpRequest"):Connect(function() help.Visible=true end)
-- A new match shows the whole world again.
gui:GetAttributeChangedSignal("ResetCamera"):Connect(function() focus=Vector2.zero; zoom=1 end)
-- After the start the camera flies to the player's country (set by the lobby).
gui:GetAttributeChangedSignal("FocusCell"):Connect(function()
	local cell=grid:getCell(gui:GetAttribute("FocusCell"))
	if not cell then return end
	local target=grid:cellToWorld(cell.x,cell.y)
	local from,fromZoom=focus,zoom
	-- FocusZoom (optional, read once): how close to fly; the start of a match flies closer than Home.
	local to,toZoom=Vector2.new(target.X,target.Z),gui:GetAttribute("FocusZoom")or .3
	gui:SetAttribute("FocusZoom",nil)
	task.spawn(function()
		local t=0
		while t<1 do
			t=math.min(1,t+task.wait()/.9)
			local e=1-(1-t)^3
			focus=from:Lerp(to,e);zoom=fromZoom+(toZoom-fromZoom)*e
		end
	end)
end)
Theme.skin(gui)

-- InputObject.Position is GUI-relative; GetMouseLocation includes the top inset.
-- Keep clicks, drag, hover and zoom in the same GUI coordinate space.
local function pointer()
 local inset=game:GetService("GuiService"):GetGuiInset()
 return UIS:GetMouseLocation()-inset
end
local function plane(screen)
	local ray=camera:ScreenPointToRay(screen.X,screen.Y)
	if math.abs(ray.Direction.Y)<.00001 then return nil end
	return ray.Origin+ray.Direction*((.015-ray.Origin.Y)/ray.Direction.Y)
end
local function isUI(position)
	for _,obj in ipairs(player.PlayerGui:GetGuiObjectsAtPosition(position.X,position.Y)) do
		if gameView and gameView:isUI(obj) then return true end
		if obj:IsA("GuiButton")
			or (help.Visible and (obj==help or obj:IsDescendantOf(help))) then return true end
	end
	return false
end
local function applyCamera()
	local viewport=camera.ViewportSize
	local half=math.max(data.height*data.tileSize/2,data.width*data.tileSize/2/math.max(1,viewport.X/viewport.Y))*1.08
	height=half*zoom/math.tan(math.rad(camera.FieldOfView/2))
	focus=Vector2.new(math.clamp(focus.X,-data.width*data.tileSize*.5,data.width*data.tileSize*.5),
		math.clamp(focus.Y,-data.height*data.tileSize*.5,data.height*data.tileSize*.5))
	camera.CFrame=CFrame.lookAt(Vector3.new(focus.X,height,focus.Y),Vector3.new(focus.X,0,focus.Y),Vector3.new(0,0,-1))
	camera.Focus=CFrame.new(focus.X,0,focus.Y)
end
local function zoomAt(factor,screen)
	local before=plane(screen)
	zoom=math.clamp(zoom*factor,data.minZoom or .08,1.5)
	applyCamera()
	local after=plane(screen)
	if before and after then focus+=Vector2.new(before.X-after.X,before.Z-after.Z) end
	applyCamera()
end
local function toggleGrid()
	gridVisible=not gridVisible
	if not tileGrid then
		tileGrid=Instance.new("Folder")
		tileGrid.Name="SeaBattleCellGrid"
		local s=data.tileSize
		for x=0,data.width do surface(tileGrid,"GridV",(x-data.width/2)*s,0,s*.035,data.height*s,C.text,.86,.021) end
		for y=0,data.height do surface(tileGrid,"GridH",0,(y-data.height/2)*s,data.width*s,s*.035,C.text,.86,.021) end
	end
	tileGrid.Parent=gridVisible and zoom<.5 and workspace or nil
end

local function cellAt(screen)
	local position=plane(screen)
	return position and grid:worldToCell(position)
end
local DIGITS={[Enum.KeyCode.One]=1,[Enum.KeyCode.Two]=2,[Enum.KeyCode.Three]=3,[Enum.KeyCode.Four]=4,[Enum.KeyCode.Five]=5,
	[Enum.KeyCode.Six]=6,[Enum.KeyCode.Seven]=7,[Enum.KeyCode.Eight]=8,[Enum.KeyCode.Nine]=9,[Enum.KeyCode.Zero]=10}
-- Arsenal tiles (BattleView): they exist only once opened in the shop.
local LETTERS={[Enum.KeyCode.Z]='Build_battery',[Enum.KeyCode.C]='Missile_torpedo',[Enum.KeyCode.V]='Missile_cluster',[Enum.KeyCode.B]='Missile_bomb',[Enum.KeyCode.N]='Mobilize'}
local LONG_PRESS=.5
local keys={}
local drag=nil
-- The pointer last used: a mouse (hover cards and highlights) or a touch screen (none). Keys and window
-- focus do not change it.
local usingMouse=not UIS.TouchEnabled
UIS.InputChanged:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseMovement then usingMouse=true end end)
UIS.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.Touch then usingMouse=false
	elseif input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.MouseButton2 then usingMouse=true end
end)
local down=nil
local touchPositions={}
UIS.InputBegan:Connect(function(input,processed)
	if UIS:GetFocusedTextBox() then return end
	if input.UserInputType==Enum.UserInputType.Keyboard and (not processed or input.KeyCode==Enum.KeyCode.Escape) then
		local key=input.KeyCode
		keys[key]=true
		local playing=gameView and gameView:playing()
		local digit=DIGITS[key]
		-- Home: your own country (the whole world before you have one); F: always the whole world.
		if key==Enum.KeyCode.Home and playing then gameView:focusCountry(gameView.playerId)
		elseif key==Enum.KeyCode.Home or key==Enum.KeyCode.F then focus=Vector2.zero; zoom=1
		elseif key==Enum.KeyCode.H then help.Visible=not help.Visible
		elseif key==Enum.KeyCode.M then toggleMusic()
		elseif key==Enum.KeyCode.G then toggleGrid()
		elseif key==Enum.KeyCode.T then task.spawn(toggleLayer)
		elseif key==Enum.KeyCode.Escape or key==Enum.KeyCode.X then choose(nil); help.Visible=false;if gameView and gameView.battleUI then gameView.battleUI:clearSelection() end
		elseif digit and playing then gameView.battleUI:hotkey(digit)
		elseif LETTERS[key] and playing then gameView.battleUI:pressSlot(LETTERS[key])
		elseif key==Enum.KeyCode.Q and playing then gameView:stepShare(-1)
		elseif key==Enum.KeyCode.E and playing then gameView:stepShare(1)
		elseif key==Enum.KeyCode.Backspace and playing then gameView.battleUI:pressRetreat()
		elseif key==Enum.KeyCode.Tab and playing then gameView:toggleLeaders()
		elseif key==Enum.KeyCode.P and gameView and gameView.battleUI then
			-- P: the pause menu (while its button is shown).
			local pm=gameView.battleUI.pause
			if pm.open or pm.button.Visible then pm:show(not pm.open) end
		elseif key==Enum.KeyCode.Space and gameView then
			-- Space: the same as a click at the cursor (expand, attack, or place the armed order).
			local p=pointer()
			if not help.Visible and not isUI(p) then local cell=cellAt(p);if cell then choose(cell);gameView:click(cell)end end
		elseif key==Enum.KeyCode.Equals or key==Enum.KeyCode.KeypadPlus then zoomAt(.8,pointer())
		elseif key==Enum.KeyCode.Minus or key==Enum.KeyCode.KeypadMinus then zoomAt(1.25,pointer()) end
	elseif input.UserInputType==Enum.UserInputType.MouseButton2 and not processed then
		-- Right-click: cancels an armed order, or opens the card of the country under the cursor.
		choose(nil)
		local p=Vector2.new(input.Position.X,input.Position.Y)
		if gameView and not help.Visible and not isUI(p) then gameView:contextClick(cellAt(p))
		elseif gameView and gameView.battleUI then gameView.battleUI:clearSelection()end
	elseif input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
		local p=Vector2.new(input.Position.X,input.Position.Y)
		if input.UserInputType==Enum.UserInputType.Touch then
			touchPositions[input]=p
			local count=0
			for _ in pairs(touchPositions) do count+=1 end
			if count>1 then drag=nil; down=nil; return end
		end
		if processed or help.Visible or isUI(p) then return end
		local press={position=p,moved=false,input=input}
		down=press;drag=p
		-- A long press (half a second without moving) opens the action menu, like a right-click.
		if input.UserInputType==Enum.UserInputType.Touch then
			task.delay(LONG_PRESS,function()
				if down~=press or press.moved or touchPinching or not gameView then return end
				press.long=true
				local cell=cellAt(press.position)
				if cell then choose(nil);gameView:contextClick(cell)end
			end)
		end
	end
end)
UIS.InputChanged:Connect(function(input,processed)
	if input.UserInputType==Enum.UserInputType.MouseWheel and not processed and not help.Visible then
		zoomAt(math.exp(-input.Position.Z*.14),pointer())
	elseif input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
		if input.UserInputType==Enum.UserInputType.Touch then touchPositions[input]=Vector2.new(input.Position.X,input.Position.Y) end
		if drag and down and not touchPinching and (input.UserInputType~=Enum.UserInputType.Touch or input==down.input) then
			local p=Vector2.new(input.Position.X,input.Position.Y)
			local a,b=plane(drag),plane(p)
			if a and b then focus+=Vector2.new(a.X-b.X,a.Z-b.Z) end
			if (p-down.position).Magnitude>6 then down.moved=true end
			drag=p
		end
	end
end)
UIS.InputEnded:Connect(function(input)
	keys[input.KeyCode]=nil
	if input.UserInputType==Enum.UserInputType.Touch then touchPositions[input]=nil end
	if input.UserInputType==Enum.UserInputType.MouseButton1 or (down and input==down.input) then
		if down and not down.moved and not down.long and not touchPinching then
			local position=plane(down.position)
			if position then
				local cell=grid:worldToCell(position);choose(cell)
				-- A tap opens a country's card (alliance or attack); a mouse click attacks at once.
				if gameView then gameView:click(cell,input.UserInputType==Enum.UserInputType.Touch)end
			end
		end
		drag=nil; down=nil
	end
end)
UIS.WindowFocusReleased:Connect(function() keys={}; down=nil; drag=nil; touchPositions={} end)
local previousPinch=1
UIS.TouchPinch:Connect(function(positions,scale,_,state,processed)
	if processed then return end
	if state==Enum.UserInputState.Begin then previousPinch=scale; touchPinching=true; down=nil; drag=nil end
	if #positions>=2 and scale>0 then
		zoomAt(previousPinch/scale,(positions[1]+positions[2])/2)
		previousPinch=scale
	end
	if state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then touchPinching=false end
end)

-- Behind the lobby the camera starts close on North America and drifts east as the demo match goes on,
-- reaching East Asia by its end (LocalMatch:progress); a new demo match brings it back.
local DEMO_ZOOM=.42
local function geoWorld(lon,lat)
	local c=grid:geoToCell(lon,lat)
	if not c then return Vector2.zero end
	local p=grid:cellToWorld(c.x,c.y)
	return Vector2.new(p.X,p.Z)
end
local demoFrom,demoTo=geoWorld(-100,42),geoWorld(118,36)
local demoCamera=false
local function updateDemoCamera(dt)
	local on=gameView.source=='demo'and gameView.lobby~=nil and gameView.lobby.mode=='menu'
	if on then
		local target=demoFrom:Lerp(demoTo,gameView.localMatch:progress())
		-- A big jump (first frame, or a new match from the start) snaps; otherwise ease along.
		if not demoCamera or (target-focus).Magnitude>data.width*data.tileSize*.25 then focus=target;zoom=DEMO_ZOOM
		else local k=math.min(1,dt*1.5);focus=focus:Lerp(target,k);zoom+=(DEMO_ZOOM-zoom)*k end
	elseif demoCamera then focus=Vector2.zero;zoom=1 end
	demoCamera=on
end

local elapsed=0
RunService:BindToRenderStep("SeaBattleCamera",Enum.RenderPriority.Camera.Value+1,function(dt)
	local direction=Vector2.zero
	if not help.Visible then
		if keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left] then direction+=Vector2.new(-1,0) end
		if keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right] then direction+=Vector2.new(1,0) end
		if keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up] then direction+=Vector2.new(0,-1) end
		if keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down] then direction+=Vector2.new(0,1) end
	end
	if direction.Magnitude>0 then focus+=direction.Unit*height*.35*math.min(dt,.1) end
	updateDemoCamera(dt)
	applyCamera()
	-- A missile hit in view shakes the camera for a moment (BattleView sets ShakePower / ShakeAt).
	local shakeAge=os.clock()-(gui:GetAttribute("ShakeAt") or -10)
	-- (strong enough to be seen: about 2% of the screen for an atom bomb, twice that for a hydrogen one)
	if shakeAge<.9 then
		local amp=(gui:GetAttribute("ShakePower") or 0)*(1-shakeAge/.9)^2*height*.04
		local t=os.clock()*28
		camera.CFrame+=Vector3.new(math.noise(t,1.7)*amp,0,math.noise(t,9.3)*amp)
	end
	if gameView then
		-- Mouse hover: the country under the cursor is highlighted and gets a small info card (not on
		-- touch screens, not over the interface, not while dragging the map).
		local p=pointer()
		if usingMouse and not drag and not help.Visible and not isUI(p) then gameView:hover(cellAt(p),p) else gameView:hover(nil)end
		gameView:update(camera,zoom,dt)
	end
	-- The selected-cell frame rides above the territory image like the other overlays.
	if gameView and gameView.overlayLift~=selectionLift then
		selectionLift=gameView.overlayLift
		for _,p in ipairs(selection:GetChildren()) do p.Position=Vector3.new(p.Position.X,.032+selectionLift,p.Position.Z) end
	end
	if tileGrid then tileGrid.Parent=gridVisible and zoom<.5 and workspace or nil end
	elapsed+=dt
	if elapsed>.12 then
		elapsed=0
        local halfY=height*math.tan(math.rad(camera.FieldOfView/2))
        local halfX=halfY*camera.ViewportSize.X/camera.ViewportSize.Y
        task.spawn(function() renderer:update(focus,halfX,halfY,zoom) end)
	end
	-- The "?" beside the pause button on every device, phones included (2026-11-12, the author's request).
	guide:layout(gui.AbsoluteSize)
	local lobby=gui:GetAttribute("LobbyOpen")==true
	helpButton.Visible=not lobby
	-- In Roblox's top bar right after the pause button, with the same 12-point gap (first when there is
	-- no pause button); top right when there is no bar.
	local spot=gameView.pauseSpot
	if spot then
		local pause=gameView.battleUI and gameView.battleUI.pause.button
		helpButton.Position=UDim2.fromOffset(spot.X+(pause and pause.Visible and PauseMenu.SIZE+12 or 0),spot.Y)
	else helpButton.Position=UDim2.new(1,-PauseMenu.SIZE-24,0,14) end
	-- Music: the button right after "?" (first in the bar in the lobby, where "?" is hidden).
	musicButton.Visible=true
	if spot then
		local pause=gameView.battleUI and gameView.battleUI.pause.button
		local x=spot.X+(pause and pause.Visible and PauseMenu.SIZE+12 or 0)+(helpButton.Visible and PauseMenu.SIZE+12 or 0)
		musicButton.Position=UDim2.fromOffset(x,spot.Y)
	else musicButton.Position=UDim2.new(1,-PauseMenu.SIZE*2-36,0,14) end
	-- (the switch as saved, once the profile has arrived)
	if not musicFromProfile and gameView.profile then
		musicFromProfile=true;music:setEnabled(gameView.profile.music~=false);showMusic()
	end
	music:setMood(musicMood())
	music:update(dt)
end)
applyCamera()
gui:SetAttribute("AtlasReady",true)
print("[SeaBattle] Atlas camera and controls ready")
