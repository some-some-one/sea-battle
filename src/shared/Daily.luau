--!nonstrict
-- The daily bonus: one reward a day (UTC), days 1 to 7, then a new cycle from day 1. Pure rules, no
-- Roblox services: the server applies them inside the profile's transaction, the lobby reads the same
-- state to draw the card.
--  * A missed day resets the series to day 1 — except one free skip in each cycle (GraceSkipsPerWeek).
--  * Day 7 also gives a prize: a cosmetic item the player does not own, or PrizeFallback silver when
--    everything is owned (the server picks it, shared/Catalog).
--  * A clock that went back never gives a second reward: a day not later than the last claimed one waits.
local D={}
D.Rewards={100,150,200,300,400,500,1000}
D.Day7Prize=true
D.PrizeFallback=1000
D.GraceSkipsPerWeek=1
D.Seconds=86400
function D.day(unixTime)return math.floor(unixTime/D.Seconds)end
-- daily: {cycleDay, lastClaimDay, graceUsed, cycleStart, totalClaims} (server/Profiles).
-- -> {canClaim, day (1..7: the one to claim now, or the last one claimed), silver, prize, nextAt (unix
--     time of the next reward when it cannot be claimed now), streakBroken, usesGrace, claimed (days of
--     this cycle already claimed)}
function D.state(daily,today)
 local last=daily.lastClaimDay or -1;local cycleDay=daily.cycleDay or 0
 if last>=0 and today<=last then
  local day=math.clamp(cycleDay,1,7)
  return {canClaim=false,day=day,silver=D.Rewards[day],prize=D.Day7Prize and day==7,nextAt=(last+1)*D.Seconds,
   streakBroken=false,usesGrace=false,claimed=cycleDay}
 end
 local day,broken,grace=1,false,false
 if last>=0 and cycleDay>=1 and cycleDay<7 then
  local missed=today-last-1
  if missed<=0 then day=cycleDay+1
  elseif missed<=D.GraceSkipsPerWeek-(daily.graceUsed or 0)then day=cycleDay+1;grace=true
  else broken=true end
 end
 return {canClaim=true,day=day,silver=D.Rewards[day],prize=D.Day7Prize and day==7,nextAt=nil,streakBroken=broken,usesGrace=grace,
  claimed=day-1}
end
-- -> newDaily, {day, silver, prize}; nil when today's reward is already taken.
function D.claim(daily,today)
 local s=D.state(daily,today)
 if not s.canClaim then return nil end
 local missed=math.max(0,today-(daily.lastClaimDay or -1)-1)
 local new={cycleDay=s.day,lastClaimDay=today,totalClaims=(daily.totalClaims or 0)+1,
  graceUsed=s.day==1 and 0 or(daily.graceUsed or 0)+(s.usesGrace and missed or 0),
  cycleStart=s.day==1 and today or(daily.cycleStart or today)}
 return new,{day=s.day,silver=s.silver,prize=s.prize==true}
end
return D
