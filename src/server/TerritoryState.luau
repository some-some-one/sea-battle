--!nonstrict
-- Server-only foundation. There is intentionally no public capture RemoteEvent.
-- Costs, combat and timing will be designed with the author in the next stages.
local Territory = {}
Territory.__index = Territory

function Territory.new(grid)
	local self=setmetatable({grid=grid,regions={}},Territory)
	for _,region in ipairs(grid.regions) do
		self.regions[region.id]={ownerId=0,development=0,structures={}}
	end
	return self
end

function Territory:canClaim(regionId,ownerId,allowStart)
	local state=self.regions[regionId]
	if not state or type(ownerId)~="number" or ownerId%1~=0 or ownerId<=0 then return false,"invalid" end
	if state.ownerId~=0 then return false,"occupied" end
	local hasTerritory=false
	for _,owned in ipairs(self.regions) do
		if owned.ownerId==ownerId then hasTerritory=true; break end
	end
	if not hasTerritory then return allowStart==true,"start_required" end
	for _,neighborId in ipairs(self.grid.regions[regionId].neighbors) do
		if self.regions[neighborId].ownerId==ownerId then return true end
	end
	return false,"not_adjacent"
end

function Territory:claim(regionId,ownerId,allowStart)
	local allowed,reason=self:canClaim(regionId,ownerId,allowStart)
	if not allowed then return false,reason end
	self.regions[regionId].ownerId=ownerId
	return true
end

return Territory
