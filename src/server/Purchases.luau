--!nonstrict
-- Purchases for Robux: MarketplaceService.ProcessReceipt. A receipt is granted inside one write of the
-- player's profile: the purchase id is checked against the ids already there, the thing is given, the id
-- is added and the account is marked as paying — all together. Only after that write succeeded is the
-- purchase reported as granted; otherwise Roblox is told "not processed yet" and offers the receipt
-- again later. The player need not be on this server: the grant goes to their record.
--
-- A receipt for something the account already has (a second click on another device, an offer that had
-- closed by the time the payment went through) is never thrown away: the money was paid, so it gives
-- silver instead — the item's price in silver, or Products.DuplicateSilver.
--  * The starter pack is shown and sold only in its window (Products.starterOpen); a receipt that
--    still arrives outside it, or a second one, is granted its silver all the same.
local Players=game:GetService("Players")
local shared=game:GetService("ReplicatedStorage"):WaitForChild("SeaBattle")
local Products=require(shared.Products)
local Catalog=require(shared.Catalog)
local Profiles=require(script.Parent.Profiles)

local Pu={}
-- The silver a cosmetic is worth when it arrives again: by rarity (a common pattern's silver price is not
-- used here, so a duplicate is worth the same whatever it costs in the shop).
local function cosmeticSilver(id)
 local item=Catalog.Cosmetics[id]
 return item and Products.CosmeticRefundSilver[item.rarity]or Products.CosmeticRefundSilver.rare
end
local packRandom=Random.new()
local function randomInt(n)return packRandom:NextInteger(1,n)end
-- The starter pack's 'home_flag': the player's own country flag, else a random country flag not owned.
local function homeFlag(rec,home,fixed)
 local id=Catalog.countryFlag(home)
 if id then return id end
 if fixed then return Products.Starter.fixedFlag end
 return Catalog.randomCountryFlag(rec.owned,randomInt)
end
-- Give `product` to the record. -> {kind, ..., refund = silver given instead (when already owned)}
-- home: the player's ISO country code when known (the starter pack's flag). fixed: paid random items are
-- restricted for this account (Roblox policy): the starter pack holds nothing drawn — the country's flag or
-- Products.Starter.fixedFlag, and Products.Starter.fixedPattern.
function Pu.grant(rec,product,now,home,fixed)
 local g=product.grants or {}
 local function silver(amount)rec.silver+=amount;rec.silverEarned+=amount;return amount end
 if g.boost then
  if rec.boosts[g.boost]then return {kind='boost',boost=g.boost,refund=silver(Products.DuplicateSilver[g.boost]or 0)}end
  rec.boosts[g.boost]=true
  return {kind='boost',boost=g.boost}
 elseif g.cosmetic then
  local item=Catalog.Cosmetics[g.cosmetic]
  if rec.owned[g.cosmetic]then return {kind='cosmetic',item=g.cosmetic,refund=silver(item and cosmeticSilver(g.cosmetic)or Products.Starter.silver)}end
  rec.owned[g.cosmetic]=true
  return {kind='cosmetic',item=g.cosmetic}
 elseif g.unlock then
  local item=Catalog.Arsenal and Catalog.Arsenal[g.unlock]
  if rec.unlocks[g.unlock]then return {kind='unlock',key=g.unlock,refund=silver(item and item.silver or 0)}end
  rec.unlocks[g.unlock]=true
  return {kind='unlock',key=g.unlock}
 elseif g.credit then
  rec.credits[g.credit]=(rec.credits[g.credit]or 0)+(product.count or 1)
  -- (a chest at the first price is counted, so the window stops offering it after the limit)
  if product.firstChest then rec.chestFirst=(rec.chestFirst or 0)+(product.count or 1)end
  return {kind='credit',credit=g.credit}
 elseif g.starter then
  local pack=Products.Starter
  local s=rec.starter or {started=now,ends=now+pack.hours*3600}
  if s.used then return {kind='starter',refund=silver(pack.silver)}end
  s.used=true;rec.starter=s
  local given=silver(pack.silver)
  -- (anything already owned, or nothing left of a kind to give, turns into silver)
  if pack.boost then
   if rec.boosts[pack.boost]then given+=silver(Products.DuplicateSilver[pack.boost]or 0)else rec.boosts[pack.boost]=true end
  end
  local items={}
  for _,id in ipairs(pack.items)do
   if id=='home_flag'then id=homeFlag(rec,home,fixed)
   elseif id=='random_pattern'then id=fixed and Products.Starter.fixedPattern or Catalog.starterPattern(rec.owned,function()return packRandom:NextNumber()end)end
   if not id then given+=silver(Products.CosmeticRefundSilver.rare)
   elseif rec.owned[id]then given+=silver(cosmeticSilver(id))else Catalog.giveAndWear(rec,id);table.insert(items,id)end
  end
  local unlocked=false
  for _,key in ipairs(pack.unlocks or {})do
   local item=Catalog.Arsenal[key]
   if rec.unlocks[key]then given+=silver(item and item.silver or 0)else rec.unlocks[key]=true;unlocked=true end
  end
  return {kind='starter',silver=given,items=items,unlocked=unlocked}
 end
 return {kind='nothing'}
end
-- One receipt: {PlayerId, ProductId, PurchaseId}. -> true when it is granted (now or earlier), false to
-- be asked again; and what was given. hooks.granted(userId, product, info) is called for a new grant.
function Pu.process(profiles,receipt,hooks)
 local product=Products.byId(receipt.ProductId)
 if not product then warn("[Purchases] unknown product "..tostring(receipt.ProductId));return false end
 local userId=receipt.PlayerId;local purchaseId=tostring(receipt.PurchaseId)
 -- (asked before the write: the write's callback must not wait)
 local fixed=product.grants and product.grants.starter and hooks and hooks.restricted and hooks.restricted(userId)or false
 local ok,info=profiles:transact(userId,function(rec)
  if table.find(rec.receipts,purchaseId)then return true,{duplicateReceipt=true}end
  local given=Pu.grant(rec,product,os.time(),hooks and hooks.home and hooks.home(userId),fixed)
  Profiles.remember(rec.receipts,purchaseId,Profiles.RECEIPTS)
  rec.paid=true
  return true,given
 end)
 -- (a record loaded only for this receipt is not kept)
 if not Players:GetPlayerByUserId(userId)then profiles:release(userId)end
 if ok~=true then return false end
 if not info.duplicateReceipt and hooks and hooks.granted then task.spawn(hooks.granted,userId,product,info)end
 return true,info
end
return Pu
