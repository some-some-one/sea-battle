--!nonstrict
-- Runs before anything else arrives: a dark screen with the title replaces Roblox's loading screen and
-- the default camera view, and stays until the lobby has something to show (Lobby sets LobbyReady).
local Players=game:GetService("Players")
local ReplicatedFirst=game:GetService("ReplicatedFirst")
local TweenService=game:GetService("TweenService")
local player=Players.LocalPlayer

local gui=Instance.new("ScreenGui")
gui.Name="SeaBattleSplash";gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=100
local cover=Instance.new("Frame")
cover.Size=UDim2.fromScale(1,1);cover.BackgroundColor3=Color3.fromRGB(9,18,27);cover.BorderSizePixel=0;cover.Parent=gui
local font="rbxasset://fonts/families/BuilderSans.json"
local title=Instance.new("TextLabel")
title.AnchorPoint=Vector2.new(.5,.5);title.Position=UDim2.fromScale(.5,.46);title.Size=UDim2.new(1,-32,0,70)
title.BackgroundTransparency=1;title.Text="SEA BATTLE";title.TextScaled=true;title.TextColor3=Color3.new(1,1,1)
title.FontFace=Font.new(font,Enum.FontWeight.Heavy);title.Parent=cover
local limit=Instance.new("UITextSizeConstraint");limit.MaxTextSize=58;limit.Parent=title
local grad=Instance.new("UIGradient");grad.Rotation=90
grad.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(255,214,150));grad.Parent=title
local status=Instance.new("TextLabel")
status.AnchorPoint=Vector2.new(.5,0);status.Position=UDim2.new(.5,0,.46,46);status.Size=UDim2.fromOffset(240,24)
status.BackgroundTransparency=1;status.Text="Loading map";status.TextSize=15;status.TextColor3=Color3.fromRGB(111,208,186)
status.FontFace=Font.new(font,Enum.FontWeight.Bold);status.Parent=cover
gui.Parent=player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local started=os.clock()
local function ready()
 local atlas=player.PlayerGui:FindFirstChild("SeaBattleAtlas")
 return atlas and atlas:GetAttribute("LobbyReady")==true
end
-- Never stuck: after a minute the game shows whatever it has.
while not ready()and os.clock()-started<60 do
 status.Text="Loading map"..string.rep(".",math.floor(os.clock()*2)%4)
 task.wait(.25)
end
-- One more moment so the first map pixels and the lobby card are drawn under the cover.
task.wait(.4)
local fade=TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
TweenService:Create(cover,fade,{BackgroundTransparency=1}):Play()
TweenService:Create(title,fade,{TextTransparency=1}):Play()
TweenService:Create(status,fade,{TextTransparency=1}):Play()
task.wait(.55)
gui:Destroy()
