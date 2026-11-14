--!nonstrict
-- Player-style names for bots that play as people (Game:assignPersonas). They must not give the bot away:
-- no Russian names or words (not even transliterated), no sea or navy words that every bot would share.
-- Ordinary English gamer-style usernames are put together from the parts below (the way people make
-- theirs: a word or a first name, sometimes a prefix, digits or a tag). The list is built once, the same
-- every time (a fixed seed), and holds COUNT unique names; any match with a real account is a coincidence.
local COUNT=400
local words={"Frost","Pixel","Shadow","Nova","Blaze","Echo","Luna","Toast","Mango","Panda","Ninja","Bacon",
 "Noodle","Cookie","Ghost","Storm","Sky","Star","Byte","Glitch","Taco","Pickle","Waffle","Jelly","Bean","Rocket",
 "Comet","Turbo","Zippy","Fuzzy","Lucky","Sunny","Bubbles","Cactus","Dino","Kitty","Fox","Wolf","Bear","Tiger",
 "Dragon","Ruby","Jade","Onyx","Neon","Cyber","Retro","Hyper","Mega","Ultra","Silent","Crazy","Sleepy","Happy",
 "Spicy","Cosmic","Atomic","Pumpkin","Muffin","Peanut","Sprinkle","Marshmallow","Raptor","Falcon","Viper","Phantom",
 "Blitz","Vortex","Pepper","Biscuit","Cupcake","Gizmo","Rascal","Shiny","Velvet","Crimson","Golden","Arctic"}
local names={"Jake","Ethan","Mason","Liam","Noah","Lucas","Owen","Ryan","Tyler","Dylan","Logan","Caleb","Emma",
 "Ava","Mia","Lily","Zoe","Chloe","Ella","Grace","Nora","Isla","Maya","Leo","Max","Sam","Ben","Finn","Kai","Theo",
 "Jack","Alex","Charlie","Aiden","Harper","Riley","Jayden","Bella","Evan","Cole","Luke","Ivy","Hazel","Milo"}
local prefixes={"Itz","Im","xX","The","Real","Just","Lil","Mr","Its","Not"}
local tags={"YT","Playz","Gaming","TV","Pro","xD","HD"}
local rng=Random.new(240613)
local function pick(t)return t[rng:NextInteger(1,#t)]end
local function digits()
 local r=rng:NextNumber()
 if r<.4 then return tostring(rng:NextInteger(1,99))end
 if r<.75 then return tostring(rng:NextInteger(2005,2016))end
 return tostring(rng:NextInteger(100,999))
end
local function make()
 local style=rng:NextInteger(1,9)
 if style==1 then return pick(words)..pick(words)..digits()                       -- FrostPanda27
 elseif style==2 then return pick(words).."_"..pick(words)                        -- Toast_Bean
 elseif style==3 then local p=pick(prefixes);local w=pick(words)                  -- ItzNova, xXShadowXx
  return p=="xX"and("xX"..w.."Xx")or(p..w)
 elseif style==4 then return string.lower(pick(names)).."_"..digits()             -- lucas_2012
 elseif style==5 then return pick(names)..pick(tags)                              -- EmmaPlayz
 elseif style==6 then return pick(names)..pick(words)..digits()                   -- JakeBlaze77
 elseif style==7 then return string.lower(pick(words)..pick(words))               -- sleepymuffin
 elseif style==8 then return pick(prefixes)..pick(names)                          -- ItzMaya
 else return pick(words)..pick(names).."_"..pick(tags)end                         -- NeonKai_YT
end
local list,seen={},{}
while #list<COUNT do
 local n=make()
 if #n>=4 and #n<=20 and not seen[n]then seen[n]=true;table.insert(list,n)end
end
return list
