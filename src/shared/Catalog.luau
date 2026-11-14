--!nonstrict
-- Everything a player can own, in one place: the arsenal (combat unlocks), boosts and cosmetics. Prices
-- in silver live here; prices in Robux and product ids live in shared/Products.
-- The author's rule: whatever works in an online match can be opened for silver. Robux only opens the
-- same thing sooner. So every arsenal item has a `silver` price (tests/CatalogQA checks it).
-- Cosmetics and currency boosts are free of that rule: they may be Robux only.
local C={}
C.Rarity={
 common={title='Common',color={150,173,178}},
 rare={title='Rare',color={86,156,255}},
 epic={title='Epic',color={176,140,255}},
 legendary={title='Legendary',color={255,196,84}},
}
-- Cosmetics: {id, kind = 'flag' | 'pattern', title, rarity, silver (nil: Robux only), prize (may be the
-- day-7 prize of the daily bonus)}. The art is shared/CosmeticArt under the same id.
-- Since 2026-11-12 (the author's decision) flags are real countries' flags and four picture flags, and flags and patterns
-- are sold for Robux only (shared/Products), besides the chest and the day-7 prize; silver opens the arsenal.
--  * a flag (pennant) stands beside the country's name on the map and in the leaderboard;
--  * a pattern lies over the country's own water in a second tint of its colour.
local list={
 -- Picture flags of our own (2026-11-12: the only ones kept besides the real flags).
 {id='flag_anchor',kind='flag',title='Anchor',rarity='rare',prize=true},
 {id='flag_jolly',kind='flag',title='Jolly Roger',rarity='epic',prize=true},
 {id='flag_star',kind='flag',title='Star',rarity='epic'},
 {id='flag_trident',kind='flag',title='Trident',rarity='legendary'},
 {id='flag_cc_kz',kind='flag',country='KZ',title='Kazakhstan',rarity='rare',prize=true},
 {id='flag_cc_us',kind='flag',country='US',title='United States',rarity='rare',prize=true},
 {id='flag_cc_gb',kind='flag',country='GB',title='United Kingdom',rarity='rare',prize=true},
 {id='flag_cc_de',kind='flag',country='DE',title='Germany',rarity='rare',prize=true},
 {id='flag_cc_fr',kind='flag',country='FR',title='France',rarity='rare',prize=true},
 {id='flag_cc_it',kind='flag',country='IT',title='Italy',rarity='rare',prize=true},
 {id='flag_cc_es',kind='flag',country='ES',title='Spain',rarity='rare',prize=true},
 {id='flag_cc_pl',kind='flag',country='PL',title='Poland',rarity='rare',prize=true},
 {id='flag_cc_nl',kind='flag',country='NL',title='Netherlands',rarity='rare',prize=true},
 {id='flag_cc_be',kind='flag',country='BE',title='Belgium',rarity='rare',prize=true},
 {id='flag_cc_ie',kind='flag',country='IE',title='Ireland',rarity='rare',prize=true},
 {id='flag_cc_at',kind='flag',country='AT',title='Austria',rarity='rare',prize=true},
 {id='flag_cc_ch',kind='flag',country='CH',title='Switzerland',rarity='rare',prize=true},
 {id='flag_cc_se',kind='flag',country='SE',title='Sweden',rarity='rare',prize=true},
 {id='flag_cc_no',kind='flag',country='NO',title='Norway',rarity='rare',prize=true},
 {id='flag_cc_fi',kind='flag',country='FI',title='Finland',rarity='rare',prize=true},
 {id='flag_cc_dk',kind='flag',country='DK',title='Denmark',rarity='rare',prize=true},
 {id='flag_cc_is',kind='flag',country='IS',title='Iceland',rarity='rare',prize=true},
 {id='flag_cc_ee',kind='flag',country='EE',title='Estonia',rarity='rare',prize=true},
 {id='flag_cc_ru',kind='flag',country='RU',title='Russia',rarity='rare',prize=true},
 {id='flag_cc_lv',kind='flag',country='LV',title='Latvia',rarity='rare',prize=true},
 {id='flag_cc_lt',kind='flag',country='LT',title='Lithuania',rarity='rare',prize=true},
 {id='flag_cc_hu',kind='flag',country='HU',title='Hungary',rarity='rare',prize=true},
 {id='flag_cc_ro',kind='flag',country='RO',title='Romania',rarity='rare',prize=true},
 {id='flag_cc_bg',kind='flag',country='BG',title='Bulgaria',rarity='rare',prize=true},
 {id='flag_cc_gr',kind='flag',country='GR',title='Greece',rarity='rare',prize=true},
 {id='flag_cc_tr',kind='flag',country='TR',title='Turkey',rarity='rare',prize=true},
 {id='flag_cc_am',kind='flag',country='AM',title='Armenia',rarity='rare',prize=true},
 {id='flag_cc_ca',kind='flag',country='CA',title='Canada',rarity='rare',prize=true},
 {id='flag_cc_mx',kind='flag',country='MX',title='Mexico',rarity='rare',prize=true},
 {id='flag_cc_br',kind='flag',country='BR',title='Brazil',rarity='rare',prize=true},
 {id='flag_cc_ar',kind='flag',country='AR',title='Argentina',rarity='rare',prize=true},
 {id='flag_cc_co',kind='flag',country='CO',title='Colombia',rarity='rare',prize=true},
 {id='flag_cc_jp',kind='flag',country='JP',title='Japan',rarity='rare',prize=true},
 {id='flag_cc_kr',kind='flag',country='KR',title='South Korea',rarity='rare',prize=true},
 {id='flag_cc_ua',kind='flag',country='UA',title='Ukraine',rarity='rare',prize=true},
 {id='flag_cc_cn',kind='flag',country='CN',title='China',rarity='rare',prize=true},
 {id='flag_cc_in',kind='flag',country='IN',title='India',rarity='rare',prize=true},
 {id='flag_cc_id',kind='flag',country='ID',title='Indonesia',rarity='rare',prize=true},
 {id='flag_cc_bd',kind='flag',country='BD',title='Bangladesh',rarity='rare',prize=true},
 -- Patterns, common to legendary (the shop shows them in this order).
 {id='pat_ripple',kind='pattern',title='Ripple',rarity='common'},
 {id='pat_stripes',kind='pattern',title='Stripes',rarity='common'},
 {id='pat_dots',kind='pattern',title='Polka Dots',rarity='common'},
 {id='pat_checker',kind='pattern',title='Checkers',rarity='common'},
 {id='pat_zigzag',kind='pattern',title='Zigzag',rarity='common'},
 {id='pat_wave',kind='pattern',title='Wave',rarity='rare',prize=true},
 {id='pat_grid',kind='pattern',title='Grid',rarity='rare'},
 {id='pat_chevron',kind='pattern',title='Chevron',rarity='rare'},
 {id='pat_bricks',kind='pattern',title='Bricks',rarity='rare'},
 {id='pat_scales',kind='pattern',title='Scales',rarity='rare'},
 {id='pat_crosshatch',kind='pattern',title='Crosshatch',rarity='rare'},
 {id='pat_camo',kind='pattern',title='Camo',rarity='epic'},
 {id='pat_diamonds',kind='pattern',title='Diamonds',rarity='epic'},
 {id='pat_anchors',kind='pattern',title='Anchors',rarity='epic'},
 {id='pat_stars',kind='pattern',title='Stars',rarity='epic'},
 {id='pat_compass',kind='pattern',title='Compass',rarity='legendary'},
 {id='pat_whirlpool',kind='pattern',title='Whirlpool',rarity='legendary'},
}
C.Cosmetics={}
C.CosmeticOrder={}
for _,item in ipairs(list)do C.Cosmetics[item.id]=item;table.insert(C.CosmeticOrder,item.id)end
-- The arsenal: combat unlocks. {key, title, kind, icon, plain (one sentence: what it does), facts (two
-- short ones), silver, product (the Robux product that opens the same thing sooner), bit (in the mask a
-- match keeps for a country)}. Rules and numbers: shared/NavalRules (R.Buildings.battery, R.Weapons.torpedo /
-- cluster / bomb, R.Battery, R.Mobilize, R.reload).
local arsenal={
 -- (the key stays "depthbomb": the torpedo took the depth bomb's place, profiles and the product keep it)
 {key='depthbomb',title='Torpedo',kind='weapon',icon='torpedo',plain='Travels underwater to the target: missile defense cannot see it.',
  facts={'Needs a straight water path from a missile platform','Hits harder than a nuke'},silver=20000,bit=4},
 {key='cluster',title='Cluster Missile',kind='weapon',icon='cluster',plain='A nuclear strike plus five small warheads around it.',
  facts={'One missile defense cannot stop every warhead','Launches from a missile platform'},silver=40000,bit=8},
 {key='mobilize',title='Extra Fleet',kind='action',icon='muster',plain='Instantly adds a fifth of your fleet for gold.',
  facts={'Once every 30 seconds at most','Never goes over your normal limit'},silver=40000,bit=1},
 {key='battery',title='Coastal Battery',kind='building',icon='cannon',plain='Placed on your water: every 4 s it fires at enemy fleets nearby on its own.',
  facts={'Reaches water up to 45 cells away','Never fires at allies or protected newcomers'},silver=50000,bit=2},
 {key='reload2x',title='Fast Reload',kind='boost',icon='reload',plain='Missile platforms and missile defense reload twice as fast.',
  facts={'Works on all your platforms and missile defense','Active from the start of the match'},silver=150000,bit=32},
 {key='bombers',title='Bombers',kind='weapon',icon='bomber',plain='Strike a spot from an airport, no missile platform needed.',
  facts={'Up to 150 cells from your airport','Missile defense downs every other one'},silver=200000,bit=16},
}
C.Arsenal={}
C.ArsenalOrder={}
for _,item in ipairs(arsenal)do item.product='unlock_'..item.key;C.Arsenal[item.key]=item;table.insert(C.ArsenalOrder,item.key)end
-- The unlocks of a profile as one number (a bit per item): what a match keeps for a country.
function C.mask(unlocks)
 local m=0
 for key,item in pairs(C.Arsenal)do if unlocks and unlocks[key]then m=bit32.bor(m,item.bit)end end
 return m
end
function C.unlocked(mask,key)
 local item=C.Arsenal[key]
 return item~=nil and bit32.btest(mask or 0,item.bit)
end
-- Slots a cosmetic can be worn in: the kind is the slot.
C.Slots={flag=true,pattern=true}
-- The day-7 prize: the first unowned prize item in catalog order, then a random eligible country flag.
-- Returns nil when nothing is left (the bonus pays silver instead).
-- random(n) -> 1..n (the server's Random).
function C.dailyPrize(owned,home,random)
 local countries={}
 for _,id in ipairs(C.CosmeticOrder)do
  local item=C.Cosmetics[id]
  if item and item.prize and not(owned and owned[id])then
   if not item.country then return id end
   if type(home)=='string'and home~=''and string.upper(home)~=item.country then table.insert(countries,id)end
  end
 end
 if #countries==0 then return nil end
 return countries[random and random(#countries)or 1]
end
-- The chest (2026-11-12, by the author's request): one random flag or pattern the
-- player does not own yet. A rarity is drawn by its odds, then an item of that rarity at random; a rarity
-- with nothing left drops out and the others share its odds. Never a duplicate.
-- Chests are bought for Robux (shared/Products: 1, 3 or 10) and kept in the profile until opened;
-- when nothing is left to give, an opened chest pays C.ChestSilver instead.
C.ChestOdds={common=.62,rare=.25,epic=.10,legendary=.03}
C.ChestSilver=1500
C.RarityOrder={'common','rare','epic','legendary'}
local function chestAllowed(item,owned)
 if item.kind~='flag'and item.kind~='pattern'then return false end
 return not(owned and owned[item.id])
end
-- What a chest can still give, by rarity: {[rarity] = {ids}}.
function C.chestPool(owned)
 local pool={}
 for _,id in ipairs(C.CosmeticOrder)do
  local item=C.Cosmetics[id]
  if chestAllowed(item,owned)then pool[item.rarity]=pool[item.rarity]or {};table.insert(pool[item.rarity],id)end
 end
 return pool
end
-- The player's own odds: {[rarity] = share 0..1} (0 for a rarity with nothing left), and how many items are left.
function C.chestOdds(owned)
 local pool=C.chestPool(owned)
 local total,left=0,0
 for rarity,odds in pairs(C.ChestOdds)do if pool[rarity]then total+=odds;left+=#pool[rarity]end end
 local out={}
 for rarity,odds in pairs(C.ChestOdds)do out[rarity]=(pool[rarity]and total>0)and odds/total or 0 end
 return out,left
end
-- One chest: an item id, or nil when nothing is left. random() -> 0..1, randomInt(n) -> 1..n.
function C.chestRoll(owned,random,randomInt)
 local pool=C.chestPool(owned)
 local odds=C.chestOdds(owned)
 local r=random();local chosen
 for _,rarity in ipairs(C.RarityOrder)do
  if odds[rarity]>0 then chosen=rarity;r-=odds[rarity];if r<0 then break end end
 end
 if not chosen then return nil end
 local ids=pool[chosen]
 return ids[randomInt(#ids)]
end
-- The country flag of an ISO code (nil when there is none in the catalog).
function C.countryFlag(code)
 if type(code)~='string'then return nil end
 local id='flag_cc_'..string.lower(code)
 return C.Cosmetics[id]and id or nil
end
-- What is worn in a slot, only if it is really owned and of that kind (for the match: the flag and the
-- pattern the others will see).
function C.worn(profile,slot)
 local id=profile and profile.equipped and profile.equipped[slot]
 local item=id and C.Cosmetics[id]
 if item and item.kind==slot and profile.owned and profile.owned[id]then return id end
 return nil
end
return C
