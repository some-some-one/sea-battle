--!nonstrict
-- Sound effects (no music): interface feedback and match events. One place for the asset ids, volumes and
-- pacing; everything else calls `Sfx.play(name)`.
--  * Sounds are licensed library audio that any experience may use: Roblox's own "Roblox GUI" set,
--    Pro Sound Effects and APM Music stings (Creator Store, free).
--  * The pause menu's sound switch (ScreenGui attribute "SoundOn") silences everything.
--  * Every button of the interface gets a hover and a click sound by itself (Sfx.init watches the
--    ScreenGui), so new buttons need no code.
local SoundService=game:GetService("SoundService")
local TweenService=game:GetService("TweenService")
local UIS=game:GetService("UserInputService")

local S={}
-- id: asset; volume; gap: least seconds between two plays; pitch; max: faded out (over `fade` seconds, 1 by
-- default) after this many seconds;
-- overlap: several may sound at once (explosions).
S.sounds={
 hover={id=17208339919,volume=.22,gap=.06},        -- Roblox GUI - Hover 01
 click={id=17208396156,volume=.5,gap=.04},         -- Roblox GUI - Select
 build={id=17208380755,volume=.6,gap=.1},          -- Roblox GUI - Purchase: a building is placed
 order={id=17208399163,volume=.5,gap=.15},         -- Roblox GUI - Send: an attack or expansion order goes out
 retreat={id=17208405682,volume=.5,gap=.2},        -- Roblox GUI - Swipe
 offer={id=17208361335,volume=.7,gap=.5},          -- Roblox GUI - Notification High: an alliance is offered to you
 allied={id=17208209318,volume=.7,gap=.5},         -- Roblox GUI - Call Accept: an alliance is made
 deny={id=17208353912,volume=.5,gap=.25},          -- Roblox GUI - Negative: an order is refused
 found={id=17208327798,volume=.7,gap=1},           -- Roblox GUI - Aura: an online match is found
 alarm={id=9113085764,volume=.3,gap=3},            -- Alarm Buzzer 5 (Pro Sound Effects): you are attacked
 start={id=1842059783,volume=.7,gap=3,max=9},      -- Heroic Arrival (sting a), APM Music: the match begins
 win={id=1837953839,volume=.7,gap=3,max=10},       -- Champions Sting, APM Music
 lose={id=115055593775910,volume=.6,gap=3,max=8},  -- Downfall StingB, APM Music
 -- (short by the author's request: the horn, the take-off and the blast are cut after `max` seconds)
 conquest={id=9119077419,volume=.5,gap=4,max=1.2,fade=.6},  -- Ship Horn USS Constellation 2 (Pro Sound Effects): a country falls to you
 jet={id=9117089319,volume=.45,gap=.5,max=1.2,fade=.5},     -- New Super Missile Pass Bys 2 (Pro Sound Effects): your fighter takes off
 blast={id=9114224354,volume=.9,gap=.1,max=1.3,fade=.7,overlap=true}, -- Earthquake Explosion 1 (Pro Sound Effects): a missile hits
}
local gui,group
local made,lastAt={},{}
local hooked=setmetatable({},{__mode='k'})

local function sound(name)
 local s=made[name]
 if not s then
  local def=S.sounds[name]
  s=Instance.new("Sound");s.Name=name;s.SoundId="rbxassetid://"..def.id;s.SoundGroup=group;s.Parent=group or SoundService
  made[name]=s
 end
 return s
end
function S.enabled()return gui==nil or gui:GetAttribute("SoundOn")~=false end
-- opts: volume and pitch multipliers (optional).
function S.play(name,opts)
 local def=S.sounds[name]
 if not def or not S.enabled()then return end
 local now=os.clock()
 if now-(lastAt[name]or -1e9)<(def.gap or 0)then return end
 lastAt[name]=now
 opts=opts or {}
 local s=sound(name)
 if def.overlap then
  s=s:Clone();s.Parent=group or SoundService
  task.delay((def.max or 8)+2,function()s:Destroy()end)
 else s:Stop()end
 s.Volume=def.volume*(opts.volume or 1);s.PlaybackSpeed=(def.pitch or 1)*(opts.pitch or 1);s.TimePosition=0
 s:Play()
 if def.max then
  local volume=s.Volume
  task.delay(def.max,function()
   -- (only if this play is still the one sounding)
   if not s.Parent or not s.IsPlaying or(not def.overlap and lastAt[name]~=now)then return end
   local t=TweenService:Create(s,TweenInfo.new(def.fade or 1),{Volume=0});t:Play()
   t.Completed:Once(function()if def.overlap or lastAt[name]==now then s:Stop();s.Volume=volume end end)
  end)
 end
end
-- Hover and click for one button. Big invisible buttons (the dim layers behind windows) stay silent.
local function small(b)
 local screen=gui.AbsoluteSize;local size=b.AbsoluteSize
 return size.X*size.Y<screen.X*screen.Y*.3
end
local function hook(b)
 if not b:IsA("GuiButton")or hooked[b]then return end
 hooked[b]=true
 b.MouseEnter:Connect(function()
  if b.Active and UIS:GetLastInputType()~=Enum.UserInputType.Touch and small(b)then S.play('hover')end
 end)
 b.Activated:Connect(function()if b.Active and small(b)then S.play('click')end end)
end
-- Called once by the Atlas with the interface's ScreenGui, before the interface is built.
function S.init(screen)
 gui=screen
 group=Instance.new("SoundGroup");group.Name="SeaBattleSfx";group.Volume=.8;group.Parent=SoundService
 for name in pairs(S.sounds)do sound(name)end
 for _,d in ipairs(screen:GetDescendants())do hook(d)end
 screen.DescendantAdded:Connect(hook)
end
-- The answer to one of the player's own commands.
local ORDER={advancing=true,reinforced=true,countered=true,land_attack_launched=true}
local QUIET={queue=true,unqueue=true,leave=true,snapshot=true,ratio=true,start=true,settings=true}
function S.reply(action,ok,reason)
 if QUIET[action]then return end
 if not ok then S.play('deny');return end
 if action=='build'or action=='mobilize'then S.play('build')
 elseif action=='fighter'then S.play('jet')
 elseif action=='missile'then S.play('order')
 elseif action=='retreat'or reason=='stopped'or reason=='retreated'then S.play('retreat')
 elseif reason=='allied'then S.play('allied')
 elseif ORDER[reason]then S.play('order')
 elseif action=='move_fighter'then S.play('order',{pitch=1.15})
 elseif action=='donate'then S.play('order')end
end
-- A missile hit: bigger and deeper for a hydrogen bomb, small and short for a MIRV warhead.
function S.blast(weapon,near)
 local volume,pitch=.8,1
 if weapon=='hydrogen'then volume,pitch=1,.72 elseif weapon=='warhead'or weapon=='bomblet'then volume,pitch=.35,1.5 elseif weapon=='shell'then volume,pitch=.14,2.2 end
 S.play('blast',{volume=volume*(near and 1 or .35),pitch=pitch*(.95+math.random()*.1)})
end
return S
