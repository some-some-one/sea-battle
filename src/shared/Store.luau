--!nonstrict
-- The client's side of purchases for Robux: whether a product exists, its price, the purchase prompt.
-- The grant itself is the server's (server/Purchases); the client only waits for its profile to change.
local MarketplaceService=game:GetService("MarketplaceService")
local Players=game:GetService("Players")
local Products=require(script.Parent.Products)
local Store={}
local prices={}       -- [key] = Robux from Roblox (the catalog's price until it answers)
local asked={}
local listeners={}
-- Paid random items (Products: random=true) are not allowed for some accounts by law (Roblox's PolicyService,
-- ArePaidRandomItemsRestricted). Asked once; until Roblox answers, or when it cannot, they count as restricted.
local restricted=true
task.spawn(function()
 local ok,info=pcall(function()return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(Players.LocalPlayer)end)
 restricted=not ok or type(info)~='table'or info.ArePaidRandomItemsRestricted==true
end)
function Store.randomRestricted()return restricted end
-- A configured product on sale that this player may buy.
function Store.available(key)
 local product=Products.list[key]
 if product and product.random and restricted then return false end
 return Products.available(key)
end
-- The price in Robux: Roblox's own once it has answered (asked once, in the background), the catalog's until then.
function Store.robux(key)
 local product=Products.list[key];if not product then return nil end
 if prices[key]then return prices[key]end
 if Products.available(key) and not asked[key]then
  asked[key]=true
  task.spawn(function()
   local ok,info=pcall(function()return MarketplaceService:GetProductInfo(product.id,Enum.InfoType.Product)end)
   if ok and type(info)=='table'and type(info.PriceInRobux)=='number'then prices[key]=info.PriceInRobux end
  end)
 end
 return product.robux
end
-- "R$ 25"
function Store.label(key)local r=Store.robux(key);return r and(r..' R$')or ''end
-- Open Roblox's purchase window for an available product.
function Store.prompt(key)
 if not Store.available(key) then return false end
 local product=Products.list[key]
 local ok=pcall(function()MarketplaceService:PromptProductPurchase(Players.LocalPlayer,product.id)end)
 return ok
end
-- fn(key, purchased) when a purchase window closes (purchased: the player paid; the grant comes with the profile).
function Store.onFinished(fn)table.insert(listeners,fn)end
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId,productId,purchased)
 if userId~=Players.LocalPlayer.UserId then return end
 local product=Products.byId(productId)
 for _,fn in ipairs(listeners)do task.spawn(fn,product and product.key,purchased)end
end)
return Store
