--!nonstrict
-- Developer products for the Sea-battle experience (10774174567). The Creator Dashboard names and
-- base prices are in docs/products.md. Missing IDs and paused sales disable purchase offers.
--   grants: boost = a permanent boost; cosmetic = one cosmetic; credit = a thing bought and used later;
--           starter = the starter pack (once per account, only before any other purchase, 48 hours from
--           its first showing); unlock = an arsenal item (the same one silver opens — only sooner).
-- The author's rule: nothing that works in an online match is Robux only (tests/CatalogQA).
local Catalog=require(script.Parent.Catalog)
local P={}
-- Robux prices of single cosmetics: patterns by rarity, every flag the same (2026-11-12: a flag 49, so a
-- chest at 39 — and the first two at 15 — is the better deal).
-- (patterns from 49, 2026-11-12; the four picture flags 59)
P.CosmeticRobux={common=49,rare=59,epic=79,legendary=149}
P.FlagRobux=49
P.PictureFlagRobux=59
-- Silver given for a cosmetic that arrives again (a receipt for one already owned, a starter pack item):
-- cosmetics have no silver price any more, so by rarity.
P.CosmeticRefundSilver={common=800,rare=2000,epic=5000,legendary=12000}
-- The starter pack's contents.
-- 'home_flag': the flag of the player's own country (Roblox's country code; unknown or not in the catalog:
-- the first country flag in catalog order the player does not own).
P.Starter={silver=5000,items={'home_flag','pat_grid'},hours=48}
-- Silver given instead when a receipt arrives for something the account already has.
P.DuplicateSilver={silver2x=5000}
local productIds={
 silver2x=3730348978,
 starter_pack=3730349048,
 takeover=3730349054,
 cos_flag_anchor=3730349225,
 cos_flag_jolly=3730349257,
 cos_flag_star=3730349270,
 cos_flag_trident=3730349277,
 chest_first=3730608676,
 chest_1=3730587558,
 chest_3=3730587576,
 chest_10=3730587591,
 unlock_depthbomb=3730349080,
 unlock_cluster=3730349084,
 unlock_mobilize=3730349089,
 unlock_battery=3730349098,
 unlock_reload2x=3730349113,
 unlock_bombers=3730349119,
 cos_flag_cc_ru=3730404783,
 cos_flag_cc_ua=3730404793,
 cos_flag_cc_kz=3730404811,
 cos_flag_cc_us=3730404828,
 cos_flag_cc_gb=3730404846,
 cos_flag_cc_de=3730404860,
 cos_flag_cc_fr=3730404873,
 cos_flag_cc_it=3730404887,
 cos_flag_cc_es=3730404921,
 cos_flag_cc_pl=3730404938,
 cos_flag_cc_nl=3730404954,
 cos_flag_cc_be=3730404963,
 cos_flag_cc_ie=3730404974,
 cos_flag_cc_at=3730404989,
 cos_flag_cc_ch=3730404995,
 cos_flag_cc_se=3730405055,
 cos_flag_cc_no=3730405372,
 cos_flag_cc_fi=3730405388,
 cos_flag_cc_dk=3730405399,
 cos_flag_cc_is=3730405402,
 cos_flag_cc_ee=3730405414,
 cos_flag_cc_lv=3730405427,
 cos_flag_cc_lt=3730405464,
 cos_flag_cc_hu=3730405523,
 cos_flag_cc_ro=3730405535,
 cos_flag_cc_bg=3730405552,
 cos_flag_cc_gr=3730405563,
 cos_flag_cc_tr=3730405573,
 cos_flag_cc_am=3730405587,
 cos_flag_cc_ca=3730405597,
 cos_flag_cc_mx=3730405635,
 cos_flag_cc_br=3730405649,
 cos_flag_cc_ar=3730405666,
 cos_flag_cc_co=3730405685,
 cos_flag_cc_jp=3730405701,
 cos_flag_cc_kr=3730405713,
 cos_flag_cc_cn=3730405764,
 cos_flag_cc_in=3730405772,
 cos_flag_cc_id=3730405780,
 cos_flag_cc_bd=3730405798,
 cos_pat_ripple=3730349295,
 cos_pat_stripes=3730349310,
 cos_pat_wave=3730349320,
 cos_pat_grid=3730349333,
 cos_pat_chevron=3730349343,
 cos_pat_camo=3730349352,
 cos_pat_compass=3730349364,
 cos_pat_dots=3730587441,
 cos_pat_checker=3730587452,
 cos_pat_zigzag=3730587463,
 cos_pat_bricks=3730587467,
 cos_pat_scales=3730587471,
 cos_pat_crosshatch=3730587508,
 cos_pat_diamonds=3730587514,
 cos_pat_anchors=3730587518,
 cos_pat_stars=3730587529,
 cos_pat_whirlpool=3730587542,
}
P.list={
 silver2x={robux=199,title='×2 Silver Forever',grants={boost='silver2x'}},
 starter_pack={robux=99,title='Starter Pack',grants={starter=true}},
 takeover={robux=25,title='Take Command',grants={credit='takeover'},count=1},
 -- Chests (2026-11-12): one 39; the first two an account buys cost 15 each through `chest_first`, which the
 -- window offers instead of chest_1 until P.ChestFirstLimit is reached; the packs stay cheaper per chest.
 chest_1={robux=39,title='Chest',grants={credit='chest'},count=1,enabled=true},
 chest_first={robux=15,title='Chest (first two)',grants={credit='chest'},count=1,firstChest=true,enabled=true},
 chest_3={robux=99,title='3 Chests',grants={credit='chest'},count=3,enabled=true},
 chest_10={robux=299,title='10 Chests',grants={credit='chest'},count=10,enabled=true},
}
P.ChestOffers={'chest_1','chest_3','chest_10'}
P.ChestFirstLimit=2
-- How many chests at the first price this profile may still buy.
function P.chestFirstLeft(profile)
 return math.max(0,P.ChestFirstLimit-(profile and profile.chestFirst or 0))
end
for _,id in ipairs(Catalog.CosmeticOrder)do
 local item=Catalog.Cosmetics[id]
 P.list['cos_'..id]={robux=item.kind=='flag'and(item.country and P.FlagRobux or P.PictureFlagRobux)or P.CosmeticRobux[item.rarity],title=(item.kind=='flag'and 'Flag "'or 'Pattern "')..item.title..'"',grants={cosmetic=id}}
end
-- Arsenal items for Robux: the same unlock silver opens, only at once.
P.UnlockRobux={depthbomb=39,cluster=67,mobilize=149,battery=99,reload2x=129,bombers=349}
for _,key in ipairs(Catalog.ArsenalOrder)do
 P.list['unlock_'..key]={robux=P.UnlockRobux[key],title=Catalog.Arsenal[key].title,grants={unlock=key}}
end
for key,product in pairs(P.list)do
 product.key=key
 product.id=productIds[key] or 0
end
function P.byId(productId)
 if type(productId)~='number'or productId==0 then return nil end
 for _,product in pairs(P.list)do if product.id==productId then return product end end
 return nil
end
-- A configured product with sales enabled.
function P.available(key)
 local product=P.list[key]
 return product~=nil and product.id~=0 and product.enabled~=false
end
-- The starter pack is on offer for this profile at `now` (unix time): never paid anything, not used, and
-- within the hours since it was first shown (or not shown yet).
function P.starterOpen(profile,now)
 if not profile or profile.paid then return false end
 local s=profile.starter
 if s and(s.used or now>=(s.ends or 0))then return false end
 return true
end
return P
