--!nonstrict
local TOAST_W=340     -- the notices' widest line (a phone has room for it beside the bar)
local B={};B.__index=B
local R=require(script.Parent.NavalRules)
local numberFormat=require(script.Parent.NumberFormat)
local compact=numberFormat.compact
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local CommandBar=require(script.Parent.CommandBar)
local Anim=require(script.Parent.Anim)
local PauseMenu=require(script.Parent.PauseMenu)
local Sfx=require(script.Parent.Sfx)
local accent=Theme.colors.accent
local idleButton=Theme.colors.button
local ink=Theme.colors.panel;local white=Theme.colors.text
local function ui(class,parent,props)local o=Instance.new(class);for k,v in pairs(props)do o[k]=v end;o.Parent=parent;return o end
local function text(parent,name,value,x,y,w,h,size)
 return ui('TextLabel',parent,{Name=name,Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,TextColor3=white,TextSize=size or 12,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham,ZIndex=12})
end
-- What each panel button does, so a key can press it too (B:hotkey).
local presses=setmetatable({},{__mode='k'})
local function button(parent,name,value,x,y,w,fn)
 local b=ui('TextButton',parent,{Name=name,Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,27),BackgroundColor3=Color3.fromRGB(43,73,88),TextColor3=white,TextSize=11,Font=Enum.Font.Gotham,BorderSizePixel=0,ZIndex=13});ui('UIStroke',b,{Name='SelectionStroke',ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=accent,Thickness=2,Enabled=false});local function press()b:SetAttribute('ActivatedAt',os.clock());fn()end;presses[b]=press;b.Activated:Connect(press);return b
end
local DEFAULT_DETAILS='Click another country to attack. Right-click (tap on a phone) for an alliance. Ports and airports go on land next to your water; everything else goes on your water.'
local reasons={land_attack_launched='Transport plane sent over land. It lands when it arrives.',landing_coast_required='Pick water off the chosen enemy\'s coast.',shore_land_required='This building only goes on land next to your water.',torpedo_line='A torpedo needs a straight water path from a ready missile platform to the target.',own_coast_required='Your water must be next to it.',gold='Not enough gold.',fleet='Not enough fleet.',own_water_required='Pick your own water.',too_close='Too close to another building.',ally_full='Your ally\'s fleet is already at its limit: nothing to send.',request_cooldown='Alliance offer already sent. The answer comes within 30 s.',
 building='Construction started.',not_ready='Missile platforms are still reloading.',airport_required='You need a finished airport: build one on land next to your water.',
 land_route='No continuous route over land.',land_required='Pick a spot over land.',water_required='Pick a water cell.',transport_limit='Three transport planes are already out.',
 launched='Sent.',fighter_moved='Fighter heading to its new patrol zone.',silo='You need a ready missile platform.',already_allied='You are already allies.',protected='This country is still under starting protection.',
 alliance_required='You cannot fight an ally, and help is for allies only.',requested='Alliance offer sent.',allied='Alliance formed for 5 minutes.',rejected='Offer declined.',betrayed='Alliance broken. Defense penalty for 30 seconds.',
 donated='Fleet sent to your ally.',retreated='Retreat: 75% of the remaining fleet returns in 2 seconds.',configured='Settings changed.',full='All player slots are taken.',stale='Things changed. Give the order again.',aircraft_limit='Fighter limit reached (12).'}
-- Units are small pixel shapes in the owner colour (see SHAPES): ships are bars, aircraft diamonds,
-- trains a short row of wagons on rails.
local unitColors={merchant=Color3.fromRGB(246,250,255),train=Color3.fromRGB(122,84,50),tradeplane=Color3.fromRGB(255,214,92),
 transport=Color3.fromRGB(255,160,64),fighter=Color3.fromRGB(232,64,56),missile=Color3.fromRGB(255,110,40)}
-- Finished journeys stay on the map as faint routes; the oldest go first past these limits.
local MAX_ROUTES,MAX_ROUTE_POINTS,ROUTE_TRANSPARENCY=160,60,.8
-- A finished flight's line stays straight but dims to nothing over ROUTE_FADE seconds, so a busy match
-- does not fill the map with old lines.
local ROUTE_FADE=25
local function routeVisibility(route)return(1-ROUTE_TRANSPARENCY)*math.max(0,1-(os.clock()-route.at)/ROUTE_FADE)end
-- Units are drawn this many seconds behind the newest server sample (samples come every 0.2 s).
local UNIT_DELAY,TRACER_TIME=.35,.3
local RELOAD_COLOR=Color3.fromRGB(255,170,64)
-- Unit shapes in the map's pixel style, built from axis-aligned rectangles (width, height in unit
-- pixels) in the owner's colour. Each piece is drawn twice: half a pixel larger on every side in a
-- darker shade of the same colour below (a thin rim, so the unit stands out on its own fill), and the
-- bright colour above; `mark` pieces are drawn dark on top (see UnitShapes for turning arsenal shapes). Sizes follow a train
-- wagon (see `pixel` below): a ship is a 4×2 bar as long as a wagon, an aircraft a diamond 5 wide, a
-- fighter a slightly larger diamond (7 at 0.85) with a dark "+" inside, a missile a small diamond 3.
local Shapes=require(script.Parent.UnitShapes)
local SHAPES,WEAPON_SHAPE=Shapes.list,Shapes.weapon
local RIM_GROW=1
local MISSILE_RIM=Color3.fromRGB(255,96,40)
local railColor,RAIL_TRANSPARENCY,WAGONS=Color3.fromRGB(40,34,30),.2,3
-- Icon of each building (IconAtlas names: the game's own art, no emoji).
local buildingIcons={port='anchor',airport='plane',oil='drop',gas='flame',defense='shield',sam='radar',silo='radiation',battery='cannon'}
local missileIcons={atom='rocket',hydrogen='burst',mirv='mirv',torpedo='torpedo',cluster='cluster',bomb='bomber'}
local Catalog=require(script.Parent.Catalog)
-- Per moving unit: colour, fading-trail length (points), whether a fading trail follows it while it moves,
-- and whether the finished journey stays on the map as a line. Only missiles leave a fading trail;
-- trade planes and transports show just the full line once they arrive; sea trade runs are drawn by the
-- trade network along their routes (updateLinks); patrolling fighters leave nothing.
local trailStyle={merchant={Color3.fromRGB(236,246,255),16,false,false},tradeplane={Color3.fromRGB(255,255,255),20,false,true},
 transport={Color3.fromRGB(255,236,196),20,false,true},fighter={Color3.fromRGB(214,228,255),16,false,false},missile={Color3.fromRGB(255,150,96),12,true,true}}
local linkColors={sea=Color3.fromRGB(130,226,214),land=Color3.fromRGB(242,206,124)}
local linkTransparency={[0]=.66,[1]=.5,[2]=.28}
local function linePart(parent,color)
 local p=Instance.new('Part');p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 p.Material=Enum.Material.SmoothPlastic;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 p.Color=color;p.Size=Vector3.new(.01,.002,.01);p.Parent=parent;return p
end
-- Overlay lines are opaque: translucent parts sort against the territory image (a SurfaceGui) by
-- distance and can vanish under it. A faint line is the line colour mixed toward the sea instead.
local SEA=Color3.fromRGB(78,134,212)
local function shade(p,color,visibility)
 if visibility<.03 then p.Transparency=1;return end
 p.Color=SEA:Lerp(color,math.min(1,visibility));p.Transparency=0
end
-- Height added to every overlay so it stays above the territory image (see View.overlayLift).
local lift=0
-- Height of an overlay layer above the territory image. `base` orders the layers (.028 lines and rails,
-- .031 trails, .033-.035 units, the higher the later); the gaps grow with the camera height (`lift` is
-- proportional to it), so the depth buffer can always tell a unit from the line under it — a fixed gap
-- of a few thousandths was too thin from high up, and units sometimes slid under trade lines.
local function layerY(base)return base+lift*(1+math.max(0,base-.028)*250)end
-- A flat bar from a to b, lying just above the territory layers.
local function placeLine(p,a,b,width,y)
 local d=Vector3.new(b.X-a.X,0,b.Z-a.Z);local length=d.Magnitude;y=layerY(y)
 if length<1e-4 then p.Transparency=1;return false end
 local mid=(a+b)/2
 p.Size=Vector3.new(width,.002,length+width*.5)
 p.CFrame=CFrame.lookAt(Vector3.new(mid.X,y,mid.Z),Vector3.new(b.X,y,b.Z))
 return true
end
function B.new(view)
 local self=setmetatable({v=view,markers={},selected=nil,target=nil,mode=nil,clock=0,unitState={},linkParts={},recentTrade={},routes={},routeCount=0,routeClock=0,rails={},rides={},rideCount=0,linkClock=1,tracers={}},B);view.battleUI=self
 self.overlay=Instance.new('Folder');self.overlay.Name='SeaBattleOverlays';self.overlay.Parent=workspace
 self.trailFolder=Instance.new('Folder');self.trailFolder.Name='UnitTrails';self.trailFolder.Parent=self.overlay
 self.linkFolder=Instance.new('Folder');self.linkFolder.Name='TradeLinks';self.linkFolder.Parent=self.overlay
 self.routeFolder=Instance.new('Folder');self.routeFolder.Name='Routes';self.routeFolder.Parent=self.overlay
 self.unitFolder=Instance.new('Folder');self.unitFolder.Name='UnitPixels';self.unitFolder.Parent=self.overlay
 self.railFolder=Instance.new('Folder');self.railFolder.Name='Rails';self.railFolder.Parent=self.overlay
 self.effectFolder=Instance.new('Folder');self.effectFolder.Name='MissileEffects';self.effectFolder.Parent=self.overlay;self.areas={};self.effects={}
 self.defenseZone=ui('Frame',view.marks,{Name='DefenseRange',AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=accent,BackgroundTransparency=.9,BorderSizePixel=0,ZIndex=1,Visible=false});self.defenseZone:SetAttribute('Marker',true);ui('UICorner',self.defenseZone,{CornerRadius=UDim.new(1,0)});ui('UIStroke',self.defenseZone,{Color=accent,Thickness=2,Transparency=.2})
 -- The command bar at the bottom (CommandBar): resources, attack share, one tile per order. A tile arms
 -- its order; the same tile (or its key) again, with the order still armed, drops it.
 -- (arsenal tiles — battery, torpedo, cluster missile, bombers, mobilisation — show only once opened)
 local kinds={'port','airport','oil','gas','defense','sam','silo','battery'}
 local missiles={'atom','hydrogen','mirv','torpedo','cluster','bomb'}
 local LETTERS={Build_battery='Z',Missile_torpedo='C',Missile_cluster='V',Missile_bomb='B',Mobilize='N'}
 local info={port='More fleet and trade. On land next to your water.',airport='Trade planes and trains, fighters. On land next to your water.',
  oil='Produces gold. On your water.',gas='Produces gold. On your water.',defense='Strengthens the defense of the water around it. On your water.',
  sam='Shoots down missiles flying at you. On your water.',silo='Launches atomic and hydrogen missiles. On your water.',
  battery='Every '..R.Battery.Interval..' s it hits the fleet of the nearest foreign country within '..R.Battery.Range..' cells. On your water.'}
 local missileInfo={torpedo='Travels underwater: missile defense cannot see it. Needs a straight water path from a missile platform to the target.',cluster='A nuclear strike plus five small warheads around it. Launches from a missile platform.',
  bomb='Strikes a spot up to 150 cells from your airport. Missile defense downs every other one.'}
 local slots={};local orders={}
 for i,kind in ipairs(kinds)do
  table.insert(slots,{key='Build_'..kind,icon=buildingIcons[kind],name=R.Buildings[kind].name,info=info[kind],hotkey=i<=7 and tostring(i)or LETTERS['Build_'..kind],
   arsenal=R.Buildings[kind].arsenal})
  orders['Build_'..kind]=function()
   self:setMode({action='build',kind=kind})
   self:hint(R.Buildings[kind].name..': '..(R.Buildings[kind].land and 'tap land next to your water'or 'tap your water'),buildingIcons[kind])
  end
 end
 -- Fighters and missiles leave from the nearest ready airport or silo: the player only picks the spot.
 table.insert(slots,{key='Fighter',icon='jet',name='Fighter',info='Patrols, shoots down enemy planes and steers enemy trade planes to you. Takes off from your airport.',hotkey='8'})
 orders.Fighter=function()self:setMode({action='fighter'});self:hint('Tap a patrol spot','jet')end
 for i,kind in ipairs(missiles)do
  table.insert(slots,{key='Missile_'..kind,icon=missileIcons[kind],name=R.Weapons[kind].name,info=missileInfo[kind]or 'Launches from the nearest ready missile platform.',
   hotkey=i==1 and'9'or i==2 and'0'or LETTERS['Missile_'..kind],arsenal=R.Weapons[kind].arsenal})
  orders['Missile_'..kind]=function()self:setMode({action='missile',kind=kind});self:hint(R.Weapons[kind].name..': tap the target',missileIcons[kind])end
 end
 -- Mobilisation: no place to pick, it acts at once.
 table.insert(slots,{key='Mobilize',icon='muster',name='Extra Fleet',info='Instantly adds a fifth of your fleet for gold. Once every 30 seconds at most.',hotkey=LETTERS.Mobilize,arsenal='mobilize'})
 orders.Mobilize=function()view:send('mobilize')end
 self.slotList=slots
 local function order(key)
  -- (a tile of something not opened does nothing: its key can still be pressed)
  if self.locked and self.locked[key]then return end
  local m=self.mode;local armed=m and(m.action=='build'and'Build_'..m.kind or m.action=='missile'and'Missile_'..m.kind or m.action=='fighter'and'Fighter')
  if armed==key then self:clearSelection();return end
  orders[key]()
 end
 local ratios=R.AttackShares
 self.bar=CommandBar.new(view.gui,{ratios=ratios,slots=slots,
  onRatio=function(r)
   if not r then -- the phone's share button steps through the shares
    local f=view.factions[view.playerId or 81];local now=f and f.ratio or R.AttackShare;local best=1
    for i,v in ipairs(ratios)do if math.abs(v-now)<math.abs(ratios[best]-now)then best=i end end
    r=ratios[best%#ratios+1]
   end
   view:send('ratio',r)
  end,
  onRetreat=function()view:send('retreat')end,onSlot=order,onCancel=function()self:clearSelection()end,
  -- The shop's gold button: the shop on the arsenal item it shows (Shop:openOn).
  onShop=function(key)local shop=view.lobby and view.lobby.shop;if shop then Sfx.play('click');self:clearSelection();shop:openOn(key and 'arsenal'or nil,key)end end})
 self.panel=self.bar.root
 self.buildButtons={};self.missileButtons={}
 for _,kind in ipairs(kinds)do self.buildButtons[kind]=self.bar.slots['Build_'..kind].button;presses[self.buildButtons[kind]]=function()order('Build_'..kind)end end
 self.fighterButton=self.bar.slots.Fighter.button;presses[self.fighterButton]=function()order('Fighter')end
 for _,kind in ipairs(missiles)do self.missileButtons[kind]=self.bar.slots['Missile_'..kind].button;presses[self.missileButtons[kind]]=function()order('Missile_'..kind)end end
 self.order=order
 -- The pause menu (PauseMenu): one round button near the status panel.
 self.pause=PauseMenu.new(view)
 self.settings=ui('Frame',view.gui,{Name='MatchSettings',Position=UDim2.fromOffset(24,128),Size=UDim2.fromOffset(300,212),BackgroundColor3=ink,BorderSizePixel=0,ZIndex=11})
 text(self.settings,'Title','NEW MATCH SETTINGS',12,8,276,24)
 local settingsButtons={{'difficulty','Difficulty',{'easy','normal','hard'}},{'mode','Mode',{'solo','online'}}}
 self.settingRows={}
 for i,entry in ipairs(settingsButtons)do
  local key=entry[1];self.settingRows[key]=button(self.settings,key,entry[2],12,34+(i-1)*28,276,function()
   local s=view.battle and view.battle.settings or {};local value
   if entry[3]then local list=entry[3];value=list[(table.find(list,s[key])or 0)%#list+1]else value=not s[key]end
   view:send('settings',{[key]=value})
  end)
 end
 -- Tapping another country opens this card next to the tap: its forces and what you can do with it.
 self.card=ui('Frame',view.gui,{Name='CountryCard',AnchorPoint=Vector2.new(.5,1),Size=UDim2.fromOffset(232,80),BackgroundColor3=ink,BorderSizePixel=0,ZIndex=16,Visible=false})
 ui('UICorner',self.card,{CornerRadius=UDim.new(0,10)});ui('UIStroke',self.card,{Name='Owner',Thickness=2})
 self.cardTitle=text(self.card,'Name','',12,8,190,20,14);self.cardTitle.Font=Enum.Font.GothamBold;self.cardTitle.ZIndex=17
 self.cardInfo=text(self.card,'Forces','',12,30,208,34,11);self.cardInfo.ZIndex=17
 button(self.card,'Close','×',198,6,26,function()self:closeCard()end).ZIndex=17
 self.cardButtons={}
 for i=1,3 do local b=button(self.card,'CardAction'..i,'',12,0,208,function()local act=self.cardActions and self.cardActions[i];self:closeCard();if act then act()end end);b.ZIndex=17;b.Visible=false;self.cardButtons[i]=b end
 -- Short notices at the top of the screen: refused orders, attacks on you, match news.
 -- (top left, off the middle of the map: 2026-11-13, the author's request)
 self.toasts=ui('Frame',view.gui,{Name='Toasts',AnchorPoint=Vector2.new(0,0),Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(TOAST_W,200),BackgroundTransparency=1,ZIndex=30})
 ui('UIListLayout',self.toasts,{Padding=UDim.new(0,6),HorizontalAlignment=Enum.HorizontalAlignment.Left,SortOrder=Enum.SortOrder.LayoutOrder})
 self.toastCount=0;self.seenEvents={};self.incoming={}
 -- Alliance offers to you: one card each above the bottom bar, with Accept / Decline.
 self.offers=ui('Frame',view.gui,{Name='AllianceOffers',AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-92),Size=UDim2.fromOffset(420,0),
  AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,ZIndex=30})
 ui('UIListLayout',self.offers,{Padding=UDim.new(0,6),HorizontalAlignment=Enum.HorizontalAlignment.Center,VerticalAlignment=Enum.VerticalAlignment.Bottom,SortOrder=Enum.SortOrder.LayoutOrder})
 self.offerCards={};self.offerHandled={}
 -- On a phone the action panel folds away so the map stays tappable.
 self.menu=button(view.gui,'Menu','Hide',8,8,96,function()self.collapsed=not self.collapsed end)
 self.menu.Size=UDim2.fromOffset(96,36);self.menu.TextSize=13;self.menu.Visible=false
 -- (the licence notice and its window are out of the match for now, by the author's request: they
 -- get their own place later; the text stays in shared/LicenseText)
 return self
end
function B:setMode(mode)
 self.mode=mode
 self:refreshSelection()
end
-- Keys 1–0 press the panel's buttons: buildings, the fighter, two missiles. The same key
-- again, with its order still armed, cancels it.
local HOTKEYS={{'build','port'},{'build','airport'},{'build','oil'},{'build','gas'},{'build','defense'},{'build','sam'},{'build','silo'},
 {'fighter'},{'missile','atom'},{'missile','hydrogen'}}
function B:hotkey(n)
 local v=self.v;local entry=HOTKEYS[n]
 if not entry or not v.playerId or v.phase~='playing'or not self.barShown or self.pause.open then return false end
 local action,kind=entry[1],entry[2]
 if self.mode and self.mode.action==action and self.mode.kind==kind then self:clearSelection();return true end
 local b=action=='build'and self.buildButtons[kind]or action=='fighter'and self.fighterButton or self.missileButtons[kind]
 if b and presses[b]then presses[b]();return true end
 return false
end
-- A letter key of an arsenal tile (Atlas: Z, C, V, B, N).
function B:pressSlot(key)
 local v=self.v
 if not v.playerId or v.phase~='playing'or not self.barShown or self.pause.open then return false end
 self.order(key);return true
end
function B:pressRetreat()if self.barShown then self.v:send('retreat')end end
-- The short hint above the command bar while an order is armed (nil: none).
function B:hint(value,icon)self.bar:setHint(value,icon)end
function B:clearSelection()
 self.mode=nil;self.selected=nil;self.target=nil
 self:hint(nil)
 self:closeCard();self:refreshSelection()
end
-- What an order costs you right now (buildings get dearer with each one built, fighters with each in the air).
function B:price(action,kind)
 local v=self.v;local battle=v.battle or {}
 if action=='build'then local prices=battle.prices and battle.prices[tostring(v.playerId)]or {};return prices[kind]or R.cost(kind,0)end
 if action=='fighter'then
  local n=0;for _,u in ipairs(battle.units or {})do if u.owner==v.playerId and u.kind=='fighter'then n+=1 end end
  return R.fighterCost(n)
 end
 return R.Weapons[kind].cost+(kind=='mirv'and(battle.mirvs or 0)*15000000 or 0)
end
function B:refreshSelection()
 local mode=self.mode;local f=self.v.factions[self.v.playerId or 81]
 local active=mode and(mode.action=='build'and 'Build_'..mode.kind or mode.action=='missile'and 'Missile_'..mode.kind or mode.action=='fighter'and 'Fighter')
 self.bar:setActive(active)
 for _,root in ipairs({self.settings})do
  for _,b in ipairs(root:GetDescendants())do if b:IsA('TextButton')then
   local name=b.Name;local selected=name==active
   if name:match('^Ratio')then selected=f and math.abs((f.ratio or R.AttackShare)-tonumber(name:sub(6))/100)<.001
   elseif self.settingRows[name]and type((self.v.battle and self.v.battle.settings or {})[name])=='boolean'then selected=self.v.battle.settings[name]end
   local flash=os.clock()-(b:GetAttribute('ActivatedAt')or -100) < .4
   b:SetAttribute('Selected',selected==true)
   b.BackgroundColor3=(selected or flash)and accent or(b:GetAttribute('Hover')and Theme.colors.hover or idleButton)
   b.TextColor3=(selected or flash)and ink or white
   b.SelectionStroke.Enabled=selected==true
  end end
 end
end
-- A tap on the map while a build, fighter or missile order is armed.
-- Your fighter nearest to the click (as drawn), within about a fingertip; nil when none is that close.
function B:fighterAt(cell)
 local v=self.v;local me=v.playerId;if not me or v.phase~='playing'then return nil end
 local c=v.grid:getCell(cell.id);if not c then return nil end
 local pos=v.grid:cellToWorld(c.x,c.y);local tile=v.grid.data.tileSize
 local reach=math.max(tile*2,(v.pixelWorld or tile)*24)
 local best,bestD
 for id,st in pairs(self.unitState)do
  if st.kind=='fighter'and st.owner==me and not st.dying and st.started then
   local d=Vector2.new(st.pos.X-pos.X,st.pos.Z-pos.Z).Magnitude
   if d<=reach and(not bestD or d<bestD)then best,bestD=id,d end
  end
 end
 return best
end
-- A click on your fighter selects it: the next click on the map moves its patrol there.
function B:selectFighter(id)
 self.selected={type='unit',id=id};self.mode={action='move',unit=id};self:refreshSelection()
 self:hint('Fighter selected: tap a new patrol spot','jet')
end
function B:click(cell)
 local v=self.v;local mode=self.mode
 if not mode then
  local fighter=self:fighterAt(cell)
  if fighter then self:selectFighter(fighter);return true end
  return false
 end
 -- Another of your fighters clicked while one is selected: switch to it.
 if mode.action=='move'then
  local other=self:fighterAt(cell)
  if other and other~=mode.unit then self:selectFighter(other);return true end
 end
 self.mode=nil;self.selected=nil;self:refreshSelection();self:hint(nil)
 if mode.action=='move'then v:send('move_fighter',{unit=mode.unit,cell=cell.id});return true end
 if mode.action=='build'then
  -- Building snaps to the nearest valid cell within about a fingertip (~28 screen points).
  v:send('build',{kind=mode.kind,cell=cell.id,reach=math.clamp(math.ceil(28*(v.pixelWorld or 0)/v.grid.data.tileSize),3,R.BuildSnap)})
 elseif mode.action=='fighter'then v:send('fighter',{cell=cell.id})
 elseif mode.action=='missile'then v:send('missile',{cell=cell.id,kind=mode.kind})end
 return true
end
function B:allied(other)
 local battle=self.v.battle or {};local me=self.v.playerId;if not me then return false end
 local a,b=math.min(me,other),math.max(me,other)
 return((battle.alliances or {})[a..':'..b]or 0)>(battle.time or 0)
end
function B:offered(other)
 local battle=self.v.battle or {}
 for _,q in ipairs(battle.requests or {})do if q.from==other and q.to==self.v.playerId and q.expires>(battle.time or 0)then return true end end
 return false
end
-- The card for another country, opened at the tapped water.
function B:openCard(owner,cell)
 local v=self.v;local f=v.factions[owner];if not f then return end
 local camera=workspace.CurrentCamera;local c=v.grid:getCell(cell.id)
 local point=camera:WorldToScreenPoint(v.grid:cellToWorld(c.x,c.y))
 self.cardTitle.Text=f.name;self.card.Owner.Color=Color3.fromRGB(table.unpack(f.color))
 self.cardInfo.Text='Fleet '..compact(f.fleet or 0)..'  •  attacking '..compact(f.committed or 0)..'\n'..v:share(f.count or 0)..' of the water'..(self:allied(owner)and '  •  ally'or '')
 local actions
 if self:allied(owner)then
  actions={{'Break alliance',function()v:send('break_alliance',owner)end,'close'},{'Break and attack',function()v:send('break_attack',{cell=cell.id})end,'swords'},
   {'Send ⅓ of fleet',function()v:send('donate',owner)end,'ship'}}
 else
  actions={{self:offered(owner)and 'Accept alliance'or 'Offer alliance',function()v:send('alliance',owner)end,'alliance'},{'Attack',function()v:send('capture',cell.id)end,'swords'}}
 end
 self.cardActions={}
 for i,b in ipairs(self.cardButtons)do
  local a=actions[i];b.Visible=a~=nil
  if a then b.Text=a[1];b.Position=UDim2.fromOffset(12,70+(i-1)*31);self.cardActions[i]=a[2];Icons.lead(b,a[3],{size=15})end
 end
 local height=78+#actions*31;self.card.Size=UDim2.fromOffset(232,height)
 local size=v.gui.AbsoluteSize;point=point+Vector3.new(v.marks.AbsolutePosition.X-v.gui.AbsolutePosition.X,v.marks.AbsolutePosition.Y-v.gui.AbsolutePosition.Y,0)
 self.card.Position=UDim2.fromOffset(math.clamp(point.X,124,size.X-124),math.clamp(point.Y-12,height+8,size.Y-8))
 self.card.Visible=true;self.cardOwner=owner
end
function B:closeCard()self.card.Visible=false;self.cardOwner=nil;self.cardActions=nil end
-- A notice at the top left for a moment (1.6 s, a button 3.2 s: 60% shorter since 2026-11-13); tone 'bad' is red, 'good' green.
-- `onClick` (optional) makes the notice a button: an attack notice flies the camera to the new front.
function B:toast(message,tone,onClick,icon)
 if not message or message==''then return end
 self.toastCount+=1
 local color=tone=='bad'and Color3.fromRGB(150,48,44)or tone=='good'and Color3.fromRGB(38,110,84)or ink
 local t=ui(onClick and 'TextButton'or 'TextLabel',self.toasts,{Name='Toast',LayoutOrder=self.toastCount,Text=message,AutomaticSize=Enum.AutomaticSize.XY,Size=UDim2.fromOffset(0,0),
  BackgroundColor3=color,BackgroundTransparency=.05,TextColor3=white,TextSize=13,Font=Enum.Font.GothamMedium,TextWrapped=false,ZIndex=31})
 ui('UICorner',t,{CornerRadius=UDim.new(0,8)});ui('UIPadding',t,{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12),PaddingTop=UDim.new(0,7),PaddingBottom=UDim.new(0,7)})
 ui('UISizeConstraint',t,{MaxSize=Vector2.new(TOAST_W,200)});t.TextWrapped=true
 if onClick then t.AutoButtonColor=true;t.Activated:Connect(function()onClick();t:Destroy()end)end
 if icon then Icons.lead(t,icon,{size=16,color=white})end
 local list=self.toasts:GetChildren();local labels={}
 for _,o in ipairs(list)do if o:IsA('TextLabel')or o:IsA('TextButton')then table.insert(labels,o)end end
 if #labels>4 then table.sort(labels,function(a,b)return a.LayoutOrder<b.LayoutOrder end);labels[1]:Destroy()end
 task.delay(onClick and 3.2 or 1.6,function()if t.Parent then t:Destroy()end end)
end
-- Match news meant for you and fresh attacks on you become notices.
function B:watchEvents(battle)
 local v=self.v;local first=self.eventsPrimed~=v.epoch
 for _,e in ipairs(battle.events or {})do
  local key=tostring(e.time)..e.text
  if not self.seenEvents[key]then
   self.seenEvents[key]=true
   -- Offers to you get their own card with buttons instead of a plain notice.
   if not first and(e.owner==v.playerId or e.owner==0)and not string.find(e.text,'Alliance offer',1,true)then
    self:toast(e.text)
    -- A country conquered sounds a short ship's horn, an alliance made its own chime; other news
    -- (an intercepted plane, a fleet received) is silent.
    if e.owner==v.playerId and string.find(e.text,'Victory over',1,true)then Sfx.play('conquest')
    elseif e.owner==v.playerId and string.find(e.text,'Alliance formed',1,true)then Sfx.play('allied')end
   end
  end
 end
 local now={}
 for _,front in ipairs(v.fronts or {})do if front.mode=='defense'then
  now[front.enemy]=true
  if not self.incoming[front.enemy]and not first then
   local e=v.factions[front.enemy];local enemy=front.enemy
   self:toast('Under attack: '..(e and e.name or 'enemy')..' ('..compact(front.theirs)..' fleet) · tap to look','bad',function()v:focusCell(v:frontCell(enemy))end,'swords')
   Sfx.play('alarm')
  end
 end end
 self.incoming=now;self.eventsPrimed=v.epoch
 self:updateOffers(battle)
end
function B:updateOffers(battle)
 local v=self.v;local me=v.playerId;local wanted={}
 for _,q in ipairs(battle.requests or {})do
  local key=q.from..':'..q.expires
  if me and q.to==me and q.expires>(battle.time or 0)and not self.offerHandled[key]then
   wanted[key]=q
   local card=self.offerCards[key]
   if not card then
    local from=q.from;local country=v.factions[from]
    card=ui('Frame',self.offers,{Name='Offer',Size=UDim2.fromOffset(420,48),BackgroundColor3=ink,BackgroundTransparency=.02,BorderSizePixel=0,ZIndex=31,LayoutOrder=q.expires})
    ui('UICorner',card,{CornerRadius=UDim.new(0,10)})
    ui('UIStroke',card,{Color=country and Color3.fromRGB(table.unpack(country.color))or accent,Thickness=2})
    local label=text(card,'Text','',12,0,206,48,13);label.ZIndex=32;label.Font=Enum.Font.GothamMedium
    Icons.lead(label,'alliance',{size=18,color=country and Color3.fromRGB(table.unpack(country.color))or accent})
    local function answer(action,tone)
     self.offerHandled[key]=true;card:Destroy();self.offerCards[key]=nil
     v:send(action,from)
    end
    local yes=ui('TextButton',card,{Name='Accept',Text='Accept',Position=UDim2.fromOffset(224,9),Size=UDim2.fromOffset(92,30),BackgroundColor3=Color3.fromRGB(38,110,84),
     TextColor3=white,TextSize=13,Font=Enum.Font.GothamMedium,BorderSizePixel=0,ZIndex=32})
    yes:SetAttribute('NoSkin',true);ui('UICorner',yes,{CornerRadius=UDim.new(0,8)});yes.Activated:Connect(function()answer('accept')end)
    Icons.lead(yes,'check',{size=14,gap=5})
    local no=ui('TextButton',card,{Name='Decline',Text='Decline',Position=UDim2.fromOffset(320,9),Size=UDim2.fromOffset(92,30),BackgroundColor3=Color3.fromRGB(150,48,44),
     TextColor3=white,TextSize=13,Font=Enum.Font.GothamMedium,BorderSizePixel=0,ZIndex=32})
    no:SetAttribute('NoSkin',true);ui('UICorner',no,{CornerRadius=UDim.new(0,8)});no.Activated:Connect(function()answer('reject')end)
    Icons.lead(no,'close',{size=13,gap=5})
    self.offerCards[key]=card;Sfx.play('offer')
   end
   local country=v.factions[q.from]
   card.Text.Text=(country and country.name or 'A country')..' offers an alliance · '..math.max(0,math.ceil(q.expires-(battle.time or 0)))..' s'
  end
 end
 for key,card in pairs(self.offerCards)do if not wanted[key]then card:Destroy();self.offerCards[key]=nil end end
end
function B:update(camera,dt)
 local v=self.v;self.clock+=dt
 if self.epoch~=v.epoch then self.epoch=v.epoch;self:clearSelection();self:clearOverlays()end
 local f=v.factions[v.playerId or 81];local started=f and f.alive and v.playerId~=nil
 -- Match settings live in the lobby now (Lobby.luau); the old panel stays hidden.
 self.settings.Visible=false
 local size=v.gui.AbsoluteSize;local compactMode=v.compact==true
 local battle=v.battle or {};local s=battle.settings or {}
 local shown=started==true and v.phase=='playing'
 self.barShown=shown
 -- Sound: the match begins (solo: the coast is picked; online: the countdown ends).
 local live=shown and(v.source=='solo'or v.source=='server')
 if live and not self.sfxLive then Sfx.play('start')end
 self.sfxLive=live
 if f then
  local prices={}
  for kind in pairs(self.buildButtons)do prices['Build_'..kind]=self:price('build',kind)end
  prices.Fighter=self:price('fighter')
  -- Mobilisation costs by the fleet it would add now (a fifth of the cap, or what there is room for).
  local room=math.max(0,(f.cap or 0)-(f.fleet or 0)-(f.committed or 0))
  prices.Mobilize=math.ceil(math.floor(math.min((f.cap or 0)*R.Mobilize.Share,room))*R.Mobilize.GoldPerFleet)
  -- Arsenal tiles show only for what the player has opened.
  local mask=Catalog.mask(v.profile and v.profile.unlocks)
  if mask~=self.arsenalMask then
   self.arsenalMask=mask;self.locked={}
   for _,slot in ipairs(self.slotList)do
    local locked=slot.arsenal~=nil and not Catalog.unlocked(mask,slot.arsenal)
    self.locked[slot.key]=locked or nil;self.bar:setShown(slot.key,not locked)
   end
  end
  -- The shop button: what is still to open, and whether the shop has been opened yet.
  local shop=v.lobby and v.lobby.shop
  local seen=shop~=nil and shop.seenArsenal==true
  if mask~=self.shopMask or seen~=self.shopSeen then
   self.shopMask=mask;self.shopSeen=seen
   local items={}
   for _,key in ipairs(Catalog.ArsenalOrder)do
    local item=Catalog.Arsenal[key]
    if not Catalog.unlocked(mask,key)then table.insert(items,{key=key,icon=item.icon,name=item.title})end
   end
   self.bar:setShop(items,seen)
  end
  for kind in pairs(self.missileButtons)do prices['Missile_'..kind]=self:price('missile',kind)end
  self.bar:update(f,prices)
 end
 self.bar:layout(size,compactMode,shown)
 -- Alliance offers sit just above the bar.
 self.offers.Position=UDim2.new(.5,0,0,(self.bar.top or size.Y-92)-8)
 -- The pause button: in Roblox's top bar next to its buttons (ConquestView:layout). When there is no
 -- bar: under the status panel on a desktop, top left on a phone.
 local hud=v.panel;local y=compactMode and 8 or(hud.AbsolutePosition.Y-v.gui.AbsolutePosition.Y+hud.AbsoluteSize.Y+8)
 local x=compactMode and 8 or(hud.AbsolutePosition.X-v.gui.AbsolutePosition.X)
 if v.pauseSpot then x,y=v.pauseSpot.X,v.pauseSpot.Y end
 self.pause:update(v.playerId~=nil and v.phase~='choosing',x,y)
 self.menu.Visible=false
 local translated={easy='easy',normal='normal',hard='hard',solo='single player',online='online'}
 for key,b in pairs(self.settingRows)do
  local names={difficulty='Difficulty',mode='Mode'}
  local value=s[key];local shown=type(value)=='number'and(math.floor(value*100+.5)..'% of the water')or translated[value]or(value and 'yes'or 'no')
  b.Text=names[key]..': '..shown
 end
 if self.clock>.25 then self.clock=0;self:watchEvents(battle)end
 -- Button highlights only need a few refreshes a second (mode changes refresh at once).
 self.selectionClock=(self.selectionClock or 0)+dt
 if self.selectionClock>.2 then self.selectionClock=0;self:refreshSelection()end
 -- Building markers move only with the camera: redraw them when it moves, when buildings or the
 -- selection change, and once a second for construction progress — not on every frame.
 local selectedKey=self.selected and(self.selected.type..self.selected.id)or''
 self.markerClock=(self.markerClock or 0)+dt
 local redraw=camera.CFrame~=self.lastCamera or camera.ViewportSize~=self.lastViewport or battle.structures~=self.lastStructures
  or selectedKey~=self.lastSelected or self.markerClock>1
 if redraw then
  self.lastCamera=camera.CFrame;self.lastViewport=camera.ViewportSize;self.lastStructures=battle.structures;self.lastSelected=selectedKey;self.markerClock=0
  self.defenseZone.Visible=false
 end
 local now=os.clock();local grid=v.grid;local tile=grid.data.tileSize
 local width=math.max(.012,(v.borderWidth or .035)*1.4);local widthChanged=self.lineWidth~=width;self.lineWidth=width
 if lift~=(v.overlayLift or 0)then lift=v.overlayLift or 0;widthChanged=true end
 local function worldOf(cell)local c=grid:getCell(cell);return c and grid:cellToWorld(c.x,c.y)end
 local seen={}
 local function marker(key,pos,icon,owner,level,building)
  local point,visible=camera:WorldToScreenPoint(pos)
  local b=self.markers[key]
  if not b then
   -- A plate in the owner's colour with the building's white glyph (a structure plate).
   b=text(v.marks,key,'',0,0,26,26,16);b:SetAttribute('Marker',true);b.ZIndex=2;b.AnchorPoint=Vector2.new(.5,.5)
   b.BackgroundColor3=Color3.fromRGB(60,80,92);b.BackgroundTransparency=0
   ui('UICorner',b,{CornerRadius=UDim.new(1,0)});ui('UIStroke',b,{Name='Owner',Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
   local glyph=Icons.image(b,icon,16,Color3.new(1,1,1),{Name='Glyph',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.66,.66),ZIndex=3})
   glyph:SetAttribute('Marker',true)
   local badge=text(b,'Level','',0,0,14,13,9);badge:SetAttribute('Marker',true);badge.AnchorPoint=Vector2.new(.5,.5);badge.Position=UDim2.new(1,-3,1,-3)
   badge.TextXAlignment=Enum.TextXAlignment.Center;badge.BackgroundColor3=accent;badge.BackgroundTransparency=0;badge.TextColor3=ink;badge.ZIndex=3
   ui('UICorner',badge,{CornerRadius=UDim.new(1,0)})
   -- Construction progress: a small bar under the icon that fills until the building is ready.
   local bar=ui('Frame',b,{Name='Progress',AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,1,3),Size=UDim2.fromOffset(24,5),
    BackgroundColor3=ink,BackgroundTransparency=.1,BorderSizePixel=0,ZIndex=3,Visible=false})
   bar:SetAttribute('Marker',true);ui('UICorner',bar,{CornerRadius=UDim.new(1,0)})
   local fill=ui('Frame',bar,{Name='Fill',Size=UDim2.fromScale(0,1),BackgroundColor3=accent,BorderSizePixel=0,ZIndex=4})
   fill:SetAttribute('Marker',true);ui('UICorner',fill,{CornerRadius=UDim.new(1,0)})
   self.markers[key]=b
  end
  local selected=self.selected and key==(self.selected.type=='unit'and 'Unit_'or 'Structure_')..self.selected.id
  b:SetAttribute('Selected',selected==true);b.Size=UDim2.fromOffset(selected and 32 or 26,selected and 32 or 26)
  if b:GetAttribute('Icon')~=icon then b:SetAttribute('Icon',icon);Icons.set(b.Glyph,icon)end
  b.Position=UDim2.fromOffset(point.X,point.Y);b.Visible=visible
  b.Glyph.ImageTransparency=building and .5 or 0;if not building then b.Progress.Visible=false end
  local country=v.factions[owner]
  local color=country and Color3.fromRGB(table.unpack(country.color))or Color3.fromRGB(120,140,150)
  b.BackgroundColor3=color:Lerp(Color3.fromRGB(16,26,34),.25)
  b.Owner.Color=selected and Color3.new(1,1,1)or color:Lerp(Color3.fromRGB(10,16,22),.55)
  b.Owner.Thickness=selected and 3 or 2
  b.Level.Visible=(level or 1)>1;b.Level.Text=tostring(level or 1)
  seen[key]=true
 end
 -- Bars of buildings under construction, collected on redraw and filled every frame.
 local bars=redraw and {}or self.bars or {}
 for _,a in ipairs(redraw and battle.structures or {})do
  local pos=worldOf(a.cell)
  if pos then
   local key='Structure_'..a.id;local building=(a.ready or 0)>(battle.time or 0)
   marker(key,pos,buildingIcons[a.kind]or 'help',a.owner,a.level,building)
   if building then bars[key]={ready=a.ready,seconds=R.Buildings[a.kind]and R.Buildings[a.kind].seconds or 1}
   elseif a.reload and a.reload>(battle.time or 0)then bars[key]={ready=a.reload,seconds=R.reload(a.kind,a.level),reload=true}end
  end
  -- Missile defence: a thin circle in the owner's colour marks the interception range.
  if pos and a.kind=='sam'then
   local key='SamRange_'..a.id;local ring=self.markers[key]
   if not ring then
    ring=ui('Frame',v.marks,{Name=key,AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1})
    ring:SetAttribute('Marker',true);ui('UICorner',ring,{CornerRadius=UDim.new(1,0)});ui('UIStroke',ring,{Name='Line',Thickness=1.5})
    self.markers[key]=ring
   end
   local center,visible=camera:WorldToScreenPoint(pos);local edge=camera:WorldToScreenPoint(pos+Vector3.new(R.samRange(a.level or 1)*tile,0,0))
   local diameter=math.abs(edge.X-center.X)*2;local country=v.factions[a.owner]
   ring.Position=UDim2.fromOffset(center.X,center.Y);ring.Size=UDim2.fromOffset(diameter,diameter)
   -- Owner colour lifted toward white so the line stands out against that owner's own fill.
   ring.Line.Color=(country and Color3.fromRGB(table.unpack(country.color))or white):Lerp(white,.45)
   ring.Line.Transparency=(a.ready or 0)>(battle.time or 0)and .55 or 0
   -- WorldToScreenPoint only says whether the centre is on screen; a large ring can still cross the view.
   ring.Visible=center.Z>0 and diameter>8;seen[key]=true
  end
  if a.kind=='defense'and self.selected and self.selected.type=='structure'and self.selected.id==a.id then
   local center,visible=camera:WorldToScreenPoint(pos);local edge=camera:WorldToScreenPoint(pos+Vector3.new(R.DefenseRange*tile,0,0))
   local diameter=math.abs(edge.X-center.X)*2
   self.defenseZone.Position=UDim2.fromOffset(center.X,center.Y);self.defenseZone.Size=UDim2.fromOffset(diameter,diameter);self.defenseZone.Visible=visible
  end
 end
 self.bars=bars
 -- Server time arrives ten times a second; run it on locally in between so the bar fills smoothly.
 if battle.time~=self.barTime then self.barTime=battle.time;self.barClock=now end
 local clockNow=(battle.time or 0)+math.min(.2,now-(self.barClock or now))
 for key,info in pairs(bars)do
  local b=self.markers[key]
  if b then
   local done=math.clamp(1-(info.ready-clockNow)/math.max(.1,info.seconds),0,1)
   b.Progress.Visible=done<1;b.Progress.Fill.Size=UDim2.fromScale(done,1)
   -- Construction fills teal, a missile defence or platform reloading fills orange.
   b.Progress.Fill.BackgroundColor3=info.reload and RELOAD_COLOR or accent
   if done>=1 then if not info.reload then b.TextTransparency=0 end;bars[key]=nil end
  else bars[key]=nil end
 end
 -- Units arrive as server samples five times a second, and packets come unevenly. Each sample is kept with
 -- its server time and units are drawn UNIT_DELAY seconds in the past, between two known samples, so they
 -- move at an even speed instead of stopping and jumping whenever a packet is late.
 -- The lobby's demo gives its own clock (view.simClock) and runs faster than real time (view.timeScale):
 -- the delay stays UNIT_DELAY real seconds, i.e. that many seconds of match at its current speed.
 local scale=v.timeScale or 1
 if v.simClock then self.simTime=math.max(self.simTime or 0,v.simClock())
 else
  self.simTime=(self.simTime or 0)+dt
  if battle.time and battle.time~=self.seenTime then
   self.seenTime=battle.time;local diff=battle.time-self.simTime
   if math.abs(diff)>1 then self.simTime=battle.time else self.simTime+=diff*.15 end
  end
 end
 local renderT=self.simTime-UNIT_DELAY*scale
 local fresh=battle.unitsTime~=nil and battle.unitsTime~=self.unitsTime
 if fresh then self.unitsTime=battle.unitsTime end
 local alive={}
 for _,u in ipairs(battle.units or {})do
  local target=worldOf(u.cell);local st=self.unitState[u.id]
  if target then
   if not st then st={pos=target,trail={target},parts={},path={target},samples={}};self.unitState[u.id]=st end
   st.cell=u.cell;st.owner=u.owner;st.kind=u.kind;st.origin=u.origin;st.destination=u.destination;st.dying=nil;alive[u.id]=true
   st.weapon=u.weapon;st.patrol=u.patrol;if u.hitBy then st.hitBy=u.hitBy end
   if fresh then
    -- Trains, ships and aircraft ride the corner path the server planned: the sample is the distance
    -- along it, so they move in straight lines instead of stepping between grid cells.
    local sample={t=battle.unitsTime,pos=target}
    if type(u.rail)=='table'and #u.rail>1 then
     local rail=self:railFor(u);local arc
     -- The share of its route already travelled (sent to a tenth of a cell) places it between cells.
     if u.along and u.steps and u.steps>0 then arc=rail.arcs[#rail.arcs]*math.clamp(u.along/u.steps,0,1)
     else arc=rail.cellArc[u.cell]or self:railProject(rail,target,st.lastRail==rail and st.lastArc or nil)end
     if arc then sample.rail=rail;sample.arc=arc;sample.pos=self:railPoint(rail,arc);st.lastRail=rail;st.lastArc=arc end
    end
    local last=st.samples[#st.samples]
    if last and(sample.pos-last.pos).Magnitude>tile*40 then st.samples={};st.trail={sample.pos};st.path={sample.pos}end
    table.insert(st.samples,sample);if #st.samples>16 then table.remove(st.samples,1)end
    -- A new shot number: one small projectile from this fighter to its target.
    if u.shot and u.shot~=st.shot then
     local target=tonumber(string.match(u.shot,':(%d+)$'))
     if st.shot~=nil or #st.samples>1 then table.insert(self.tracers,{t=battle.unitsTime,from=u.id,to=target,owner=u.owner})end
    end
    st.shot=u.shot
    -- Missile defence hit: a shot from the defence to the missile, which hangs in the air meanwhile.
    if u.hitBy and not st.hitTraced then
     st.hitTraced=true
     for _,a in ipairs(battle.structures or {})do if a.id==u.hitBy then
      table.insert(self.tracers,{t=battle.unitsTime,fromPos=worldOf(a.cell),to=u.id,owner=a.owner,big=true});break
     end end
    end
   end
   st.returning=u.returning
  end
 end
 for id,st in pairs(self.unitState)do
  local sm=st.samples;local newest=sm[#sm]
  -- A new unit is drawn from the moment the drawing clock reaches its first position: shown earlier it
  -- would stand still for UNIT_DELAY and only then set off (a visible freeze in the fast lobby demo).
  if not st.started and newest and renderT>=sm[1].t then st.started=true end
  -- A unit that left the server list still plays out its last samples before it fades.
  if not alive[id]and not st.dying and(not newest or renderT>=newest.t)then st.dying=now;if st.kind=='missile'then self:missileEnded(st,camera)end end
  if newest then
   local a,b=sm[1],nil
   for i=#sm,1,-1 do if sm[i].t<=renderT then a,b=sm[i],sm[i+1];break end end
   if b then
    local f=math.clamp((renderT-a.t)/math.max(1e-3,b.t-a.t),0,1)
    -- Two samples on different copies of a path (the path cache was trimmed between them): measure the
    -- older one along the newer path, so a train's wagons do not jump ahead to the next sample.
    if a.rail and b.rail and a.rail~=b.rail then a.rail=b.rail;a.arc=self:railProject(b.rail,a.pos,b.arc)end
    if a.rail and a.rail==b.rail then st.rail=a.rail;st.arc=a.arc+(b.arc-a.arc)*f;st.pos=self:railPoint(a.rail,st.arc)
    else st.pos=a.pos:Lerp(b.pos,f);st.rail=nil;st.arc=nil end
   else
    -- Past the newest sample (a late packet): keep going a little along the last motion.
    local p=a==newest and sm[#sm-1];local over=math.min(renderT-a.t,.15)
    if p and alive[id]and over>0 and a.t>p.t then
     if a.rail and p.rail and a.rail~=p.rail then p.rail=a.rail;p.arc=self:railProject(a.rail,p.pos,a.arc)end
     if a.rail and a.rail==p.rail then st.rail=a.rail;st.arc=a.arc+(a.arc-p.arc)/(a.t-p.t)*over;st.pos=self:railPoint(a.rail,st.arc)
     else st.pos=a.pos+(a.pos-p.pos)/(a.t-p.t)*over;st.rail=a.rail;st.arc=a.arc end
    else st.pos=a.pos;st.rail=a.rail;st.arc=a.arc end
   end
  end
  local style=trailStyle[st.kind];local fade=st.dying and math.clamp((now-st.dying)/1.2,0,1)or 0
  if style then
   local changed=widthChanged or st.dying~=nil
   if not st.dying and(st.pos-st.trail[#st.trail]).Magnitude>=tile*.7 then
    table.insert(st.trail,st.pos);if #st.trail>style[2]then table.remove(st.trail,1)end;changed=true
   end
   if style[4]and not st.dying and(st.pos-st.path[#st.path]).Magnitude>=tile*2 then
    table.insert(st.path,st.pos)
    -- Patrols never end: past 4× the route budget drop every other point to stay bounded.
    if #st.path>MAX_ROUTE_POINTS*4 then local half={};for i=1,#st.path,2 do table.insert(half,st.path[i])end;st.path=half end
   end
   local n=#st.trail-1
   if style[3]and changed then
    for i=1,math.max(n,#st.parts)do
     local p=st.parts[i]
     if i<=n then
      if not p then p=linePart(self.trailFolder,style[1]);st.parts[i]=p end
      if placeLine(p,st.trail[i],st.trail[i+1],width*(.9+1.1*i/n),.031)then shade(p,style[1],(1-fade)*(.12+.6*i/n))end
     elseif p then p.Transparency=1 end
    end
   end
   -- The newest segment follows the unit every frame.
   if style[3]then
    st.head=st.head or linePart(self.trailFolder,style[1])
    if placeLine(st.head,st.trail[#st.trail],st.pos,width*2,.031)then shade(st.head,style[1],(1-fade)*.72)end
   end
  end
  if st.dying and not st.kept then
   st.kept=true;if st.shape then for _,p in ipairs(st.shape)do p:Destroy()end;st.shape=nil end
   if st.wagons then for _,p in ipairs(st.wagons)do p:Destroy()end;st.wagons=nil end
   table.insert(st.path,st.pos);self:keepRoute(id,st,width)
  end
  if st.dying and fade>=1 then
   for _,p in ipairs(st.parts)do p:Destroy()end;if st.head then st.head:Destroy()end;self.unitState[id]=nil
  end
 end
 -- Pixel size follows the zoom: about one map cell up close, never smaller than ~6 screen points.
 local pixelWorld=v.pixelWorld or tile;local size=math.max(tile*1.4,pixelWorld*6)
 -- One "pixel" of a unit's shape: a quarter of a wagon's length (a ship is as long as a wagon):
 -- 0.4 of a map cell up close, 1.75 screen points at the farthest.
 local pixel=math.max(tile*.4,pixelWorld*1.75)
 -- Drawn from the local state, so a unit the server already removed still finishes its last samples.
 -- Only what changed is written: colours and sizes when they differ, positions of moved units in one
 -- BulkMoveTo call (hundreds of separate CFrame writes per frame were the costliest part on phones).
 local moveParts,moveFrames={},{}
 local colorOf={}
 local function ownerColor(owner)
  local c=colorOf[owner];if c then return c end
  local country=v.factions[owner];c=country and Color3.fromRGB(table.unpack(country.color))or white;colorOf[owner]=c;return c
 end
 -- Units use a brighter, more saturated owner colour than the muted territory fill, so they stand out on it.
 local vividOf={}
 local function vivid(owner)
  local c=vividOf[owner];if c then return c end
  local h,sat,val=ownerColor(owner):ToHSV()
  c=Color3.fromHSV(h,math.max(sat,.6),math.max(val,.95));vividOf[owner]=c;return c
 end
 local function setColor(p,c)if p.Color~=c then p.Color=c end end
 local function setSize(p,sz)if p.Size~=sz then p.Size=sz end end
 local selectedUnit=self.selected and self.selected.type=='unit'and self.selected.id
 for id,st in pairs(self.unitState)do
  if st.dying or not st.started then continue end
  local kind=st.kind;local selected=selectedUnit==id
  if st.rail and st.arc and kind=='train'then
   -- Locomotive in the owner colour, wagons behind it along the track.
   local length=math.max(tile*1.6,pixelWorld*7);local gap=length*1.3
   if not st.wagons then st.wagons={};for k=1,WAGONS do st.wagons[k]=linePart(self.unitFolder,unitColors.train)end end
   if st.drawnArc~=st.arc or st.drawnLength~=length or st.drawnLift~=lift or st.drawnSelected~=selected then
    st.drawnArc=st.arc;st.drawnLength=length;st.drawnLift=lift;st.drawnSelected=selected
    local sz=Vector3.new(length*.55,.002,length)
    for k,p in ipairs(st.wagons)do
     local pos,dir=self:railPoint(st.rail,math.max(0,st.arc-(k-1)*gap))
     setColor(p,k==1 and(selected and white or ownerColor(st.owner))or unitColors.train);setSize(p,sz)
     table.insert(moveParts,p);table.insert(moveFrames,CFrame.lookAt(Vector3.new(pos.X,layerY(.034),pos.Z),Vector3.new(pos.X+dir.X,layerY(.034),pos.Z+dir.Z)))
    end
   end
  else
   -- Pixel shapes in the owner's colour with a thin darker rim (see SHAPES); arsenal weapons face
   -- where they fly, the rest never turn.
   local shapeName=kind=='merchant'and 'ship'or kind=='fighter'and 'fighter'or kind=='missile'and(WEAPON_SHAPE[st.weapon]or 'missile')or 'plane'
   local shape=SHAPES[shapeName];local pieces,mark,light=shape.pieces,shape.mark or {},shape.light or {}
   local n,nm,nl=#pieces,#mark,#light
   if not st.shape or st.shapeName~=shapeName then
    for _,p in ipairs(st.shape or {})do p:Destroy()end
    st.shapeName=shapeName;st.drawnPos=nil
    st.shape={};for i=1,n*2+nm+nl do st.shape[i]=linePart(self.unitFolder,white)end
   end
   local owner=vivid(st.owner)
   local fill=kind=='fighter'and st.returning and owner:Lerp(Color3.fromRGB(120,120,120),.6)or shape.fill and owner:Lerp(shape.fill,shape.mix or .5)or owner
   local rim=selected and white or shape.rim or kind=='missile'and MISSILE_RIM or fill:Lerp(Color3.new(0,0,0),.45)
   local dark=fill:Lerp(Color3.new(0,0,0),.6)
   local q=(selected and pixel*1.4 or pixel)*(shape.scale or 1)
   for i=1,n do setColor(st.shape[i],rim);setColor(st.shape[n+i],fill)end
   for i=1,nl do setColor(st.shape[n*2+i],white)end
   for i=1,nm do setColor(st.shape[n*2+nl+i],shapeName=='mirv'and Color3.fromRGB(20,20,24)or dark)end
   local heading=0
   if shape.turn then
    local to=st.destination and self:cellPoint(st.destination)
    if to then local d=to-st.pos;if d.Magnitude>tile*.5 then st.heading=math.atan2(-d.Z,d.X)end end
    heading=st.heading or 0
   end
   if st.drawnPos~=st.pos or st.drawnSize~=q or st.drawnLift~=lift or st.drawnHeading~=heading then
    st.drawnPos=st.pos;st.drawnSize=q;st.drawnLift=lift;st.drawnHeading=heading
    local turn=CFrame.Angles(0,heading,0)
    local function at(piece,y)
     local off=turn:VectorToWorldSpace(Vector3.new((piece[3]or 0)*q,0,(piece[4]or 0)*q))
     return CFrame.new(st.pos.X+off.X,y,st.pos.Z+off.Z)*turn
    end
    for i,piece in ipairs(pieces)do
     local w,h=piece[1],piece[2]
     local rimPart,fillPart=st.shape[i],st.shape[n+i]
     setSize(rimPart,Vector3.new((w+RIM_GROW)*q,.002,(h+RIM_GROW)*q));setSize(fillPart,Vector3.new(w*q,.002,h*q))
     table.insert(moveParts,rimPart);table.insert(moveFrames,at(piece,layerY(.033)))
     table.insert(moveParts,fillPart);table.insert(moveFrames,at(piece,layerY(.034)))
    end
    for i,piece in ipairs(light)do
     local p=st.shape[n*2+i];setSize(p,Vector3.new(piece[1]*q,.002,piece[2]*q))
     table.insert(moveParts,p);table.insert(moveFrames,at(piece,layerY(.0345)))
    end
    for i,piece in ipairs(mark)do
     local p=st.shape[n*2+nl+i];setSize(p,Vector3.new(piece[1]*q,.002,piece[2]*q))
     table.insert(moveParts,p);table.insert(moveFrames,at(piece,layerY(.035)))
    end
   end
  end
 end
 if #moveParts>0 then workspace:BulkMoveTo(moveParts,moveFrames,Enum.BulkMoveMode.FireCFrameChanged)end
 self:updateFighterRings(camera,ownerColor)
 self:updateMissileAreas(lift)
 self:updateAim(camera)
 self:updateEffects(lift)
 -- Fighter shots: a small bright square flies from the shooter to its target in TRACER_TIME seconds.
 for i=#self.tracers,1,-1 do
  local tr=self.tracers[i];local age=renderT-tr.t
  local from=tr.fromPos or(self.unitState[tr.from]and self.unitState[tr.from].pos);local b=tr.to and self.unitState[tr.to]
  if age>TRACER_TIME or not from or not b or renderT-tr.t>3 then if tr.part then tr.part:Destroy()end;table.remove(self.tracers,i)
  elseif age>=0 then
   if not tr.part then
    local country=v.factions[tr.owner]
    tr.part=linePart(self.unitFolder,(country and Color3.fromRGB(table.unpack(country.color))or white):Lerp(white,.5))
   end
   local pos=from:Lerp(b.pos,age/TRACER_TIME);local s=size*(tr.big and .6 or .45)
   tr.part.Size=Vector3.new(s,.002,s);tr.part.CFrame=CFrame.new(pos.X,layerY(.035),pos.Z)
  end
 end
 self.routeClock+=dt
 -- Dim kept flight lines step by step and drop the ones that have faded out.
 self.fadeClock=(self.fadeClock or 0)+dt
 if self.fadeClock>=.5 then self.fadeClock=0
  for key,r in pairs(self.routes)do
   local visibility=routeVisibility(r)
   if visibility<=0 then for _,p in ipairs(r.parts)do p:Destroy()end;self.routes[key]=nil;self.routeCount-=1
   else for _,p in ipairs(r.parts)do if p.Transparency<1 then shade(p,r.color,visibility)end end end
  end
 end
 if self.routeClock>.3 and(self.routeWidth~=width or self.routeLift~=lift)then self.routeClock=0;self.routeWidth=width;self.routeLift=lift
  for _,r in pairs(self.routes)do self:placeRoute(r,width)end
  for _,r in pairs(self.rails)do self:placeRail(r,width)end
 end
 if redraw then for key,o in pairs(self.markers)do if not seen[key]then o:Destroy();self.markers[key]=nil end end end
 self:updateRailways(battle,width)
 self.linkClock+=dt
 if self.linkClock>.5 or widthChanged then self.linkClock=0;self:updateLinks(battle,width,now,worldOf)end
end
-- Circles for your fighters: a thin ring around each one marks how far
-- it reaches for foreign trade planes; the selected one is brighter and also shows its patrol area.
local function ring(parent,name)
 local r=ui('Frame',parent,{Name=name,AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1,Visible=false})
 r:SetAttribute('Marker',true);ui('UICorner',r,{CornerRadius=UDim.new(1,0)});ui('UIStroke',r,{Name='Line',Thickness=1.5})
 return r
end
function B:updateFighterRings(camera,ownerColor)
 local v=self.v;local me=v.playerId;self.fighterRings=self.fighterRings or {}
 local tile=v.grid.data.tileSize;local used={}
 local selectedUnit=self.selected and self.selected.type=='unit'and self.selected.id
 if selectedUnit and(not self.unitState[selectedUnit]or self.unitState[selectedUnit].dying)then self:clearSelection();selectedUnit=nil end
 local function place(key,pos,radius,color,transparency,thickness)
  local r=self.fighterRings[key];if not r then r=ring(v.marks,key);self.fighterRings[key]=r end
  local center=camera:WorldToScreenPoint(pos);local edge=camera:WorldToScreenPoint(pos+Vector3.new(radius*tile,0,0))
  local diameter=math.abs(edge.X-center.X)*2
  r.Position=UDim2.fromOffset(center.X,center.Y);r.Size=UDim2.fromOffset(diameter,diameter)
  r.Line.Color=color;r.Line.Transparency=transparency;r.Line.Thickness=thickness
  r.Visible=center.Z>0 and diameter>6;used[key]=true
 end
 if me and v.phase=='playing'then
  for id,st in pairs(self.unitState)do
   if st.kind=='fighter'and st.owner==me and st.started and not st.dying then
    -- Rings only for the fighter the player has selected (no standing rings on every fighter).
    local selected=id==selectedUnit
    if selected then place('FighterRange_'..id,st.pos,R.FighterHunt,white,0,2)end
    if selected and st.patrol then
     local c=v.grid:getCell(st.patrol)
     if c then place('FighterPatrol_'..id,v.grid:cellToWorld(c.x,c.y),R.PatrolRadius,white,.35,1.5)end
    end
   end
  end
 end
 for key,r in pairs(self.fighterRings)do if not used[key]then r:Destroy();self.fighterRings[key]=nil end end
end
-- Missiles: the area a missile in flight will hit is shaded pale red (yours and the enemy's alike); a hit
-- flashes and sends a shock ring out to the blast's edge and shakes the camera when it is in view (or on
-- your water); a missile shot down by a missile defence leaves a small white puff.
local AREA_COLOR,AREA_ALPHA=Color3.fromRGB(255,120,120),.74
local FLASH_COLOR,SHOCK_COLOR,PUFF_COLOR=Color3.fromRGB(255,240,200),Color3.fromRGB(255,120,50),Color3.fromRGB(235,235,235)
local function blastRadius(weapon)
 if weapon=='mirv'then return R.Mirv.spread end -- the warheads fall within this of the aim
 local spec=R.Weapons[weapon or 'atom'];return spec and spec.outer or 22
end
local function disc(parent,color)
 local p=Instance.new('Part');p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
 p.Shape=Enum.PartType.Cylinder;p.Material=Enum.Material.SmoothPlastic;p.Color=color;p.Parent=parent;return p
end
local function placeDisc(p,pos,radius,y)
 local d=math.max(.01,radius*2)
 p.Size=Vector3.new(.002,d,d);p.CFrame=CFrame.new(pos.X,y,pos.Z)*CFrame.Angles(0,0,math.pi/2)
end
function B:cellPoint(cell)
 local c=cell and self.v.grid:getCell(cell);if not c then return nil end
 return self.v.grid:cellToWorld(c.x,c.y)
end
function B:updateMissileAreas(lift)
 local tile=self.v.grid.data.tileSize;local seen={}
 local pulse=.06*math.sin(os.clock()*5)
 for id,st in pairs(self.unitState)do
  if st.kind=='missile'and not st.dying and st.destination and st.weapon~=nil and st.weapon~='shell'then
   local area=self.areas[id]
   local pos=self:cellPoint(st.destination)
   if pos then
    if not area then area={part=disc(self.effectFolder,AREA_COLOR)};self.areas[id]=area end
    placeDisc(area.part,pos,blastRadius(st.weapon)*tile,layerY(.0296));area.part.Transparency=AREA_ALPHA+pulse
    seen[id]=true
   end
  end
 end
 for id,area in pairs(self.areas)do if not seen[id]then area.part:Destroy();self.areas[id]=nil end end
end
function B:missileEnded(st,camera)
 local tile=self.v.grid.data.tileSize;local now=os.clock()
 if st.hitBy then
  table.insert(self.effects,{at=now,pos=st.pos,kind='puff',radius=3*tile,parts={disc(self.effectFolder,PUFF_COLOR)}})
  return
 end
 -- A MIRV carrier itself does no damage: its warheads do, each with its own blast.
 if st.weapon=='mirv'then return end
 local pos=self:cellPoint(st.destination)or st.pos
 local spec=R.Weapons[st.weapon or 'atom']or R.Weapons.atom
 table.insert(self.effects,{at=now,pos=pos,kind='blast',inner=math.max(spec.shell and 1 or 3,spec.inner)*tile,radius=spec.outer*tile,
  parts={disc(self.effectFolder,SHOCK_COLOR),disc(self.effectFolder,FLASH_COLOR)}})
 -- A battery's shell: the small burst only (a faint thud on screen, no shake).
 if spec.shell then
  if self.sfxLive then local sp,vis=camera:WorldToViewportPoint(pos);if vis and sp.X>=0 and sp.Y>=0 and sp.X<=camera.ViewportSize.X and sp.Y<=camera.ViewportSize.Y then Sfx.blast('shell',true)end end
  return
 end
 -- Shake the camera for a hit in view, or on this player's own water.
 local v=self.v;local screen,visible=camera:WorldToViewportPoint(pos)
 local onScreen=visible and screen.X>=0 and screen.Y>=0 and screen.X<=camera.ViewportSize.X and screen.Y<=camera.ViewportSize.Y
 local mine=v.playerId and st.destination and v:owner(st.destination)==v.playerId
 -- The blast is heard at full volume in view or on your water, faintly elsewhere; never in the lobby's
 -- background match.
 if self.sfxLive then Sfx.blast(st.weapon,onScreen or mine)end
 if onScreen or mine then
  local power=st.weapon=='hydrogen'and 1 or st.weapon=='warhead'and .3 or .55
  if (v.gui:GetAttribute('ShakePower')or 0)<power or os.clock()-(v.gui:GetAttribute('ShakeAt')or 0)>.3 then
   v.gui:SetAttribute('ShakePower',power);v.gui:SetAttribute('ShakeAt',os.clock())
  end
 end
end
function B:updateEffects(lift)
 local now=os.clock()
 for i=#self.effects,1,-1 do
  local e=self.effects[i];local age=now-e.at
  if e.kind=='puff'then
   local t=age/.5
   if t>=1 then for _,p in ipairs(e.parts)do p:Destroy()end;table.remove(self.effects,i)
   else placeDisc(e.parts[1],e.pos,e.radius*(.4+.6*t),layerY(.0305));e.parts[1].Transparency=.2+.8*t end
  else
   -- Shock ring: grows to the blast's edge in 0.8 s and fades; flash: the core, gone in 0.6 s.
   local t=age/1.1
   if t>=1 then for _,p in ipairs(e.parts)do p:Destroy()end;table.remove(self.effects,i)
   else
    local grow=1-(1-math.min(1,age/.8))^3
    placeDisc(e.parts[1],e.pos,e.radius*grow,layerY(.0300));e.parts[1].Transparency=.35+.65*t
    e.parts[1].Color=SHOCK_COLOR:Lerp(Color3.fromRGB(200,40,40),t)
    local f=math.min(1,age/.6)
    placeDisc(e.parts[2],e.pos,e.inner*(.5+.8*f),layerY(.0302));e.parts[2].Transparency=f
   end
  end
 end
end
-- A new stream (a new match, or switching between the lobby's demo and the server): units, trails, kept
-- routes, trade links and shots of the old one are removed at once instead of fading out.
function B:clearUnits()
 for _,folder in ipairs({self.trailFolder,self.linkFolder,self.routeFolder,self.unitFolder})do folder:ClearAllChildren()end
 self.unitState={};self.tracers={};self.routes={};self.routeCount=0;self.linkParts={};self.recentTrade={};self.tradePaths={}
 self.rides={};self.rideCount=0;self.simTime=nil;self.seenTime=nil;self.unitsTime=nil
 self.effectFolder:ClearAllChildren();self.areas={};self.effects={}
end
-- Sea trade network, drawn along the ships' own water routes (never straight across land): every
-- station-to-port run a ship has sailed stays as a faint line, brighter while a ship is on it now (2)
-- or was in the last 20 seconds (1). A run no ship has sailed yet is not drawn.
function B:updateLinks(battle,width,now,worldOf)
 local byId={};local wanted={}
 self.tradePaths=self.tradePaths or {}
 for _,s in ipairs(battle.structures or {})do byId[s.id]=s end
 local function keyOf(a,b)return math.min(a,b)..'-'..math.max(a,b)end
 for _,u in ipairs(battle.units or {})do if u.origin and u.destination and u.kind=='merchant'and type(u.rail)=='table'and #u.rail>1 then
  local key=keyOf(u.origin,u.destination)
  local known=self.tradePaths[key]
  if not known or known.signature~=table.concat(u.rail,',')then
   local rail=self:railFor(u);self.tradePaths[key]={points=rail.points,signature=table.concat(u.rail,','),a=u.origin,b=u.destination}
  end
  self.recentTrade[key]=now;wanted[key]=2
 end end
 for key,path in pairs(self.tradePaths)do
  local a,b=byId[path.a],byId[path.b]
  -- A route whose ends changed hands is dropped, even while a ship is still on it.
  if not a or not b or a.owner~=b.owner then self.tradePaths[key]=nil;self.recentTrade[key]=nil;wanted[key]=nil
  elseif not wanted[key]then wanted[key]=(self.recentTrade[key]and now-self.recentTrade[key]<=20)and 1 or 0 end
 end
 for key,strength in pairs(wanted)do
  local path=self.tradePaths[key];local line=self.linkParts[key]
  if line and(line.points~=path.points or line.strength~=strength or line.width~=width)then for _,p in ipairs(line.parts)do p:Destroy()end;line=nil end
  if not line then
   line={parts={},points=path.points,strength=strength,width=width};self.linkParts[key]=line
   local color=linkColors.sea
   for i=1,#path.points-1 do
    local p=linePart(self.linkFolder,color);line.parts[i]=p
    if placeLine(p,path.points[i],path.points[i+1],width*(strength==2 and 1.1 or .75),.028)then shade(p,color,1-linkTransparency[strength])end
   end
  end
 end
 for key,line in pairs(self.linkParts)do if not wanted[key]then for _,p in ipairs(line.parts)do p:Destroy()end;self.linkParts[key]=nil end end
end
-- Keep a finished journey as a faint line. Trade runs between the same two buildings share one route.
function B:keepRoute(id,st,width)
 local style=trailStyle[st.kind];if not style or not style[4]or #st.path<2 then return end
 local key=st.origin and st.destination and(st.kind..':'..math.min(st.origin,st.destination)..'-'..math.max(st.origin,st.destination))or('unit:'..id)
 local points=st.rail and st.rail.points or st.path
 -- Long journeys keep every n-th point so one route never needs more than MAX_ROUTE_POINTS segments.
 if #points>MAX_ROUTE_POINTS then
  local step=#points/MAX_ROUTE_POINTS;local thin={}
  for i=1,MAX_ROUTE_POINTS do table.insert(thin,points[math.floor((i-1)*step)+1])end
  table.insert(thin,points[#points]);points=thin
 end
 local route=self.routes[key]
 if route then for _,p in ipairs(route.parts)do p:Destroy()end else self.routeCount+=1 end
 route={parts={},points=points,at=os.clock(),color=style[1]};self.routes[key]=route
 for i=1,#points-1 do route.parts[i]=linePart(self.routeFolder,style[1])end
 self:placeRoute(route,width)
 while self.routeCount>MAX_ROUTES do
  local oldest,oldestKey;for k,r in pairs(self.routes)do if not oldest or r.at<oldest.at then oldest,oldestKey=r,k end end
  for _,p in ipairs(oldest.parts)do p:Destroy()end;self.routes[oldestKey]=nil;self.routeCount-=1
 end
end
function B:placeRoute(route,width)
 for i,p in ipairs(route.parts)do
  if placeLine(p,route.points[i],route.points[i+1],width*.6,.0295)then shade(p,route.color,routeVisibility(route))end
 end
end
-- A train's ride as corner points with distances along it; drawn track comes from the network instead.
function B:railFor(u)
 local signature=table.concat(u.rail,',');local rail=self.rides[signature]
 if rail then return rail end
 local grid=self.v.grid;local w=grid.width
 rail={points={},arcs={},cellArc={}}
 local total=0
 for k,id in ipairs(u.rail)do
  local c=grid:getCell(id);local p=grid:cellToWorld(c.x,c.y)
  if k==1 then rail.cellArc[id]=0 else
   local prev=u.rail[k-1];local a=rail.points[k-1]
   local ax,ay=(prev-1)%w,(prev-1)//w;local bx,by=(id-1)%w,(id-1)//w
   local n=math.max(math.abs(bx-ax),math.abs(by-ay),1);local length=(p-a).Magnitude
   -- Exact cell positions for axis-aligned track; other legs are found by projection.
   if ax==bx or ay==by then for step=1,n do rail.cellArc[(ay+math.sign(by-ay)*step)*w+ax+math.sign(bx-ax)*step+1]=total+length*step/n end end
   total+=length
  end
  rail.points[k]=p;rail.arcs[k]=total
 end
 self.rides[signature]=rail;self.rideCount+=1
 -- Trim finished journeys only: paths still ridden keep their table, or a train would lose its place on them.
 if self.rideCount>400 then
  local used={}
  for _,st in pairs(self.unitState)do if st.lastRail then used[st.lastRail]=true end;for _,sm in ipairs(st.samples)do if sm.rail then used[sm.rail]=true end end end
  local kept,n={},0;for key,r in pairs(self.rides)do if used[r]or r==rail then kept[key]=r;n+=1 end end
  self.rides,self.rideCount=kept,n
 end
 return rail
end
-- The shared railway network: one thin line per straight run, rebuilt when the server changes it.
function B:updateRailways(battle,width)
 if self.railwaysVersion==battle.railwaysVersion then return end
 self.railwaysVersion=battle.railwaysVersion
 local grid=self.v.grid;local wanted={}
 for _,row in ipairs(battle.railways or {})do
  local id,corners=row[1],row[2];wanted[id]=true
  if not self.rails[id]then
   local rail={parts={},points={}}
   for k,cell in ipairs(corners)do local c=grid:getCell(cell);rail.points[k]=grid:cellToWorld(c.x,c.y)end
   for k=1,#rail.points-1 do rail.parts[k]=linePart(self.railFolder,railColor)end
   self.rails[id]=rail;self:placeRail(rail,width)
  end
 end
 for id,rail in pairs(self.rails)do if not wanted[id]then for _,p in ipairs(rail.parts)do p:Destroy()end;self.rails[id]=nil end end
end
function B:placeRail(rail,width)
 for k,p in ipairs(rail.parts)do
  if placeLine(p,rail.points[k],rail.points[k+1],width*.6,.0292)then p.Color=railColor;p.Transparency=0 end
 end
end
-- Distance along the path of the point nearest to `pos` (preferring the stretch near `hint`).
function B:railProject(rail,pos,hint)
 local best,bestScore
 for k=2,#rail.points do
  local a,b=rail.points[k-1],rail.points[k];local ab=b-a;local len2=ab:Dot(ab)
  local t=len2>0 and math.clamp((pos-a):Dot(ab)/len2,0,1)or 0
  local arc=rail.arcs[k-1]+(rail.arcs[k]-rail.arcs[k-1])*t
  local score=(a+ab*t-pos).Magnitude+(hint and math.abs(arc-hint)*.05 or 0)
  if not bestScore or score<bestScore then best,bestScore=arc,score end
 end
 return best or 0
end
-- Position and heading at a distance along the track.
function B:railPoint(rail,arc)
 local points,arcs=rail.points,rail.arcs
 for k=2,#points do
  if arc<=arcs[k]or k==#points then
   local a,b=points[k-1],points[k];local span=arcs[k]-arcs[k-1]
   local t=span>0 and math.clamp((arc-arcs[k-1])/span,0,1)or 0
   local dir=b-a;if dir.Magnitude<1e-6 then dir=Vector3.new(0,0,1)end
   return a:Lerp(b,t),dir.Unit
  end
 end
 return points[1],Vector3.new(0,0,1)
end
function B:clearOverlays()
 for _,st in pairs(self.unitState)do for _,p in ipairs(st.parts)do p:Destroy()end;if st.head then st.head:Destroy()end;for _,p in ipairs(st.shape or {})do p:Destroy()end;for _,p in ipairs(st.wagons or {})do p:Destroy()end end
 for _,r in pairs(self.rails)do for _,p in ipairs(r.parts)do p:Destroy()end end
 self.rails={};self.rides={};self.rideCount=0;self.railwaysVersion=nil
 for _,r in pairs(self.routes)do for _,p in ipairs(r.parts)do p:Destroy()end end
 self.routes={};self.routeCount=0
 for _,line in pairs(self.linkParts)do for _,p in ipairs(line.parts)do p:Destroy()end end;self.tradePaths={}
 for _,tr in ipairs(self.tracers)do if tr.part then tr.part:Destroy()end end
 self.unitState={};self.linkParts={};self.recentTrade={};self.tracers={};self.simTime=nil;self.unitsTime=nil
end
function B:isUI(obj)
 if self.bar:isUI(obj)then return true end
 if self.pause:isUI(obj)then return true end
 for _,panel in ipairs({self.settings,self.card,self.offers})do if panel.Visible and(obj==panel or obj:IsDescendantOf(panel))then return true end end;return false
end
reasons.locked='Unlock this in the shop first: Arsenal.';reasons.cooldown='Extra fleet already called. Wait half a minute.'
reasons.fleet_full='Your fleet is at its limit: no more fits.';reasons.range='Too far: bombers reach 150 cells from your airport.'
reasons.mobilized='Extra fleet has arrived.'
B.reasons=reasons
-- Aim preview (a placement ghost), with a mouse: while a building or a missile is armed,
-- the cell under the pointer is checked the way the server will check it. A building's ghost stands where
-- a click would really build (snapped to the nearest valid cell, as B:click asks), green when it can,
-- red with the reason when it cannot; a missile shows its blast circles (a MIRV the circle its warheads
-- fall in, the target country highlighted by the hover). A short caption says what and for how much.
-- Phones keep tap-to-build (the server snaps the tap).
local GOOD,BAD=Color3.fromRGB(126,222,152),Color3.fromRGB(255,110,96)
function B:siteBuckets()
 local battle=self.v.battle or {}
 if battle.structures~=self.siteList then
  self.siteList=battle.structures;local w=self.v.grid.width;local b={}
  for _,a in ipairs(battle.structures or {})do
   local x,y=(a.cell-1)%w,(a.cell-1)//w;local key=(x//32)..':'..(y//32)
   b[key]=b[key]or {};table.insert(b[key],a)
  end
  self.siteMap=b
 end
 return self.siteMap
end
-- The server's Game:siteError on this device's copy of the map (nil: the building can stand here).
function B:siteError(kind,id)
 local v=self.v;local grid=v.grid;local me=v.playerId;local info=R.Buildings[kind]
 if info.land then
  if grid:isWater(id)then return 'shore_land_required'end
  local coast=false
  for _,n in ipairs(grid:neighborIds(id))do if grid:isWater(n)and v:owner(n)==me then coast=true;break end end
  if not coast then return 'own_coast_required'end
 elseif not grid:isWater(id)or v:owner(id)~=me then return 'own_water_required'end
 local w=grid.width;local x,y=(id-1)%w,(id-1)//w;local map=self:siteBuckets();local near=R.SameKindSpacing
 for by=(y-near)//32,(y+near)//32 do for bx=(x-near)//32,(x+near)//32 do
  for _,a in ipairs(map[bx..':'..by]or {})do
   if a.cell==id then return 'occupied'end
   local d=math.sqrt(((a.cell-1)%w-x)^2+((a.cell-1)//w-y)^2)
   if d<=near and(a.kind==kind or d<=R.BuildSpacing)then return 'too_close'end
  end
 end end
 return nil
end
-- Game:buildSite: the cell itself, or the nearest valid one within `reach`.
function B:buildSite(kind,id,reach)
 local err=self:siteError(kind,id);if not err then return id end
 local grid=self.v.grid;local w,h=grid.width,grid.height;local x,y=(id-1)%w,(id-1)//w;local best,bestD
 for dy=-reach,reach do for dx=-reach,reach do
  local d=dx*dx+dy*dy;local nx,ny=x+dx,y+dy
  if d<=reach*reach and(not bestD or d<bestD)and nx>=0 and nx<w and ny>=0 and ny<h then
   local c=ny*w+nx+1;if not self:siteError(kind,c)then best,bestD=c,d end
  end
 end end
 return best,err
end
function B:missileError(kind,id)
 local v=self.v;local battle=v.battle or {};local me=v.playerId
 if not v.grid:isWater(id)then return 'water_required'end
 local enemy=v:owner(id)
 if enemy==me then return 'own'end
 if enemy>0 and self:allied(enemy)then return 'ally'end
 local any,ready=false,false
 local spec=R.Weapons[kind]
 if spec and spec.airport then
  -- Bombers: one of your ready airports within range of the target.
  local w=v.grid.width;local tx,ty=(id-1)%w,(id-1)//w;local near=false
  for _,a in ipairs(battle.structures or {})do
   if a.owner==me and a.kind=='airport'and(a.ready or 0)<=(battle.time or 0)then
    any=true
    if((a.cell-1)%w-tx)^2+((a.cell-1)//w-ty)^2<=spec.range^2 then near=true end
   end
  end
  if not any then return 'airport_required'end
  if not near then return 'range'end
  return nil
 end
 local line=false
 for _,a in ipairs(battle.structures or {})do
  if a.owner==me and a.kind=='silo'and(a.ready or 0)<=(battle.time or 0)then any=true
   if(a.reload or 0)<=(battle.time or 0)then ready=true;if spec and spec.torpedo and not line and self:waterLine(a.cell,id)then line=true end end
  end
 end
 if not any then return 'silo'end
 if not ready then return 'not_ready'end
 if spec and spec.torpedo and not line then return 'torpedo_line'end
 return nil
end
-- Game:waterLine on this device's map: a straight line of water from one cell to another (the torpedo's way).
function B:waterLine(from,to)
 local grid=self.v.grid;local w=grid.width
 local ax,ay=(from-1)%w,(from-1)//w;local bx,by=(to-1)%w,(to-1)//w
 local dx,dy=bx-ax,by-ay;local steps=math.max(1,math.ceil(math.max(math.abs(dx),math.abs(dy))*2))
 for i=0,steps do
  local t=i/steps
  if not grid:isWater(math.floor(ay+dy*t+.5)*w+math.floor(ax+dx*t+.5)+1)then return false end
 end
 return true
end
local aimReasons={own='This is your water.',ally='This is an ally.'}
function B:aimParts()
 if self.aim then return self.aim end
 local marks=self.v.marks;local a={}
 local function circle(name,z)
  local f=ui('Frame',marks,{Name=name,AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=GOOD,BackgroundTransparency=.85,BorderSizePixel=0,ZIndex=z,Visible=false})
  f:SetAttribute('Marker',true);ui('UICorner',f,{CornerRadius=UDim.new(1,0)});ui('UIStroke',f,{Name='Line',Color=GOOD,Thickness=2,Transparency=.1})
  return f
 end
 a.ring=circle('AimRing',4);a.inner=circle('AimInner',4)
 a.ghost=circle('AimGhost',6);a.ghost.Size=UDim2.fromOffset(30,30);a.ghost.BackgroundColor3=Color3.fromRGB(30,46,58);a.ghost.BackgroundTransparency=.15
 a.ghost.Line.Thickness=2.5
 a.glyph=Icons.image(a.ghost,'anchor',18,Color3.new(1,1,1),{Name='Glyph',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=7})
 a.glyph:SetAttribute('Marker',true)
 a.caption=ui('TextLabel',marks,{Name='AimCaption',AnchorPoint=Vector2.new(.5,1),AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.fromOffset(0,24),
  BackgroundColor3=ink,BackgroundTransparency=.08,TextColor3=white,TextSize=13,FontFace=Theme.font(Enum.FontWeight.Bold),ZIndex=8,Visible=false})
 a.caption:SetAttribute('Marker',true);ui('UICorner',a.caption,{CornerRadius=UDim.new(0,8)})
 ui('UIPadding',a.caption,{PaddingLeft=UDim.new(0,9),PaddingRight=UDim.new(0,9)})
 a.captionLine=ui('UIStroke',a.caption,{Color=GOOD,Thickness=1.5,Transparency=.2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 self.aim=a;return a
end
function B:hideAim()
 local a=self.aim;if not a then return end
 a.ring.Visible=false;a.inner.Visible=false;a.ghost.Visible=false;a.caption.Visible=false;self.aimKey=nil
end
function B:updateAim(camera)
 local v=self.v;local mode=self.mode;local cell=v.pointerCell
 if not mode or(mode.action~='build'and mode.action~='missile')or not cell or v.phase~='playing'or not v.playerId then self:hideAim();return end
 local a=self:aimParts();local grid=v.grid;local tile=grid.data.tileSize
 -- The check is redone when the pointer moves to another cell, and a few times a second otherwise.
 local now=os.clock();local key=mode.action..(mode.kind or'')..cell.id
 if key~=self.aimKey or now-(self.aimAt or 0)>.3 then
  self.aimKey=key;self.aimAt=now
  local f=v.factions[v.playerId]or {};local price=self:price(mode.action,mode.kind);local afford=(f.gold or 0)>=price
  local r={}
  if mode.action=='build'then
   local reach=math.clamp(math.ceil(28*(v.pixelWorld or 0)/tile),3,R.BuildSnap)
   local site,err=self:buildSite(mode.kind,cell.id,reach)
   local info=R.Buildings[mode.kind]
   r.cell=site or cell.id;r.ok=site~=nil and afford;r.icon=buildingIcons[mode.kind]or'help'
   local why=err=='shore_land_required'and(info.name..' only goes on land next to your water.')or err=='own_coast_required'and(info.name..': your water must be next to it.')or reasons[err]
   r.text=site and(info.name..' · '..compact(price)..(afford and''or' · not enough gold'))or(why or'You cannot build here.')
   -- (the reach of what it acts on: a defence post, a missile defence, a coastal battery's fire)
   r.radius=mode.kind=='defense'and R.DefenseRange or mode.kind=='sam'and R.samRange(1)or mode.kind=='battery'and R.Battery.Range or nil
  else
   local err=self:missileError(mode.kind,cell.id);local spec=R.Weapons[mode.kind]
   r.cell=cell.id;r.ok=err==nil and afford;r.missile=true
   if mode.kind=='mirv'then
    r.radius=R.Mirv.spread
    local tg=v:owner(cell.id);local target=tg>0 and tg~=v.playerId and v.factions[tg]
    r.text=err and(aimReasons[err]or reasons[err]or'Not here.')or(spec.name..' · '..(target and target.name or'one warhead')..' · '..compact(price))
   else
    r.radius=spec.outer;r.inner=spec.inner
    r.text=err and(aimReasons[err]or reasons[err]or'Not here.')or(spec.name..' · '..compact(price))
   end
   if not err and not afford then r.text=spec.name..' · '..compact(price)..' · not enough gold'end
  end
  self.aimResult=r
 end
 local r=self.aimResult;local c=grid:getCell(r.cell);if not c then self:hideAim();return end
 local pos=grid:cellToWorld(c.x,c.y);local point=camera:WorldToScreenPoint(pos)
 local color=r.ok and GOOD or BAD
 local function place(f,radius)
  if not radius or radius<=0 then f.Visible=false;return end
  local edge=camera:WorldToScreenPoint(pos+Vector3.new(radius*tile,0,0));local d=math.abs(edge.X-point.X)*2
  f.Position=UDim2.fromOffset(point.X,point.Y);f.Size=UDim2.fromOffset(d,d);f.Visible=point.Z>0 and d>6
  f.BackgroundColor3=color;f.Line.Color=color
 end
 place(a.ring,r.radius);a.ring.BackgroundTransparency=r.missile and .82 or .9
 place(a.inner,r.inner);a.inner.BackgroundTransparency=.7
 -- A building's ghost: its icon on a plate ringed green or red, breathing a little.
 a.ghost.Visible=not r.missile and point.Z>0
 if a.ghost.Visible then
  local s=30+2*math.sin(now*6)
  a.ghost.Position=UDim2.fromOffset(point.X,point.Y);a.ghost.Size=UDim2.fromOffset(s,s);a.ghost.Line.Color=color
  if a.glyph:GetAttribute('Icon')~=r.icon then a.glyph:SetAttribute('Icon',r.icon);Icons.set(a.glyph,r.icon)end
  a.glyph.ImageTransparency=r.ok and 0 or .35
 end
 a.caption.Text=r.text;a.captionLine.Color=color;a.caption.TextColor3=r.ok and white or Color3.fromRGB(255,190,180)
 local above=r.missile and 18 or 22
 a.caption.Position=UDim2.fromOffset(point.X,point.Y-above);a.caption.Visible=point.Z>0
end
return B
