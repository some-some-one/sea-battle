--!nonstrict
-- Avatars for bots that play as people (f.persona): ordinary-looking Roblox avatars put together here
-- from free items Roblox itself made (hair, faces, a few hats) and default skin and shirt colours — not
-- any real account's avatar. Built on the server (Players:CreateHumanoidModelFromDescription is server
-- only), cut down to the head and shoulders, and kept in ReplicatedStorage.SeaBattle.PersonaHeads under
-- the persona's `look` number; clients show a copy in a small ViewportFrame beside the name (ConquestView).
-- The ids were checked against economy.roblox.com (creator Roblox, the right asset type) on 2026-11-07.
local Players=game:GetService("Players")
local shared=game:GetService("ReplicatedStorage"):WaitForChild("SeaBattle")
local M={}
local HAIR={63690008,451220849,451221329,376548738,376524487,376526888,62234425,2956239660,62724852,48474294,
 80922374,13477818,26658141,32278814}
local HATS={9254254,1772336109}
local FACES={144075659,7317773,7699174,15432080,21635565,144075659,144075659}
local SKIN={Color3.fromRGB(234,184,146),Color3.fromRGB(204,142,105),Color3.fromRGB(160,95,53),Color3.fromRGB(124,92,70),
 Color3.fromRGB(245,205,48),Color3.fromRGB(253,234,141),Color3.fromRGB(255,204,153),Color3.fromRGB(105,64,40)}
local SHIRT={Color3.fromRGB(13,105,172),Color3.fromRGB(196,40,28),Color3.fromRGB(40,127,71),Color3.fromRGB(27,42,53),
 Color3.fromRGB(242,243,243),Color3.fromRGB(107,50,124),Color3.fromRGB(218,133,65),Color3.fromRGB(99,95,98),
 Color3.fromRGB(4,175,236),Color3.fromRGB(255,102,204)}
function M.folder()
 local f=shared:FindFirstChild("PersonaHeads")
 if not f then f=Instance.new("Folder");f.Name="PersonaHeads";f.Parent=shared end
 return f
end
-- The parts of a look come from its number, so the same number always gives the same avatar.
local function describe(look,withHat)
 local r=Random.new(look)
 local d=Instance.new("HumanoidDescription")
 local skin=SKIN[r:NextInteger(1,#SKIN)];local shirt=SHIRT[r:NextInteger(1,#SHIRT)]
 d.HeadColor=skin;d.LeftArmColor=skin;d.RightArmColor=skin;d.LeftLegColor=skin;d.RightLegColor=skin;d.TorsoColor=shirt
 if r:NextNumber()<.88 then d.HairAccessory=tostring(HAIR[r:NextInteger(1,#HAIR)])end
 d.Face=FACES[r:NextInteger(1,#FACES)]
 if withHat and r:NextNumber()<.15 then d.HatAccessory=tostring(HATS[r:NextInteger(1,#HATS)])end
 return d
end
-- Head, the top of the torso and what is worn on the head; everything anchored, no scripts or humanoid logic.
local function trim(model)
 local keep={Head=true,UpperTorso=true}
 for _,c in ipairs(model:GetChildren())do
  if c:IsA("BasePart")and not keep[c.Name]then c:Destroy()
  elseif c:IsA("Script")or c:IsA("LocalScript")then c:Destroy()end
 end
 for _,d in ipairs(model:GetDescendants())do
  if d:IsA("BasePart")then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.CastShadow=false end
 end
 local humanoid=model:FindFirstChildOfClass("Humanoid")
 if humanoid then humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
 model.PrimaryPart=model:FindFirstChild("Head")
 return model
end
local function build(look)
 for _,withHat in ipairs({true,false})do
  local ok,model=pcall(function()return Players:CreateHumanoidModelFromDescription(describe(look,withHat),Enum.HumanoidRigType.R15)end)
  if ok and model then return trim(model)end
  warn("[PersonaHeads] look "..look..": "..tostring(model))
 end
end
-- Builds a head for every persona in `game` (a match's state), a few at a time; old heads are cleared.
function M.build(game)
 local folder=M.folder();folder:ClearAllChildren()
 local epoch=game.epoch
 for _,f in ipairs(game.factions)do
  if f.persona and f.look then
   task.spawn(function()
    local model=build(f.look)
    if not model then return end
    if game.epoch~=epoch then model:Destroy();return end
    model.Name=tostring(f.look);model.Parent=folder
   end)
  end
 end
end
return M
