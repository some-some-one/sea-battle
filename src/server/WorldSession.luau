--!nonstrict
-- One authoritative session; later game services require this ModuleScript.
local shared=game:GetService("ReplicatedStorage"):WaitForChild("SeaBattle")
local data=require(shared.WorldData)
local grid=require(shared.WorldGrid).new(data)
local conquest=require(script.Parent.PixelConquest).new(grid)
return {data=data,grid=grid,conquest=conquest}
