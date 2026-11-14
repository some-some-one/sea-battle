--!nonstrict
-- Silver for a match. Pure rules, no Roblox services: the match server pays its own results with them,
-- and a solo result (which the player's device reports) is first cut down to what the server can accept.
--
-- A result: {minutes (alive in the match), peakShare (the largest share of the world's water held, 0..1),
--   participants, kills (countries finished off), place (1 = best), won, quit (left before the end)}.
-- The lines (each rounded to E.Round):
--   participate  E.Participate, not for one who quit
--   survive      E.SurvivePerMinute a minute alive
--   water        E.WaterPerShare for each "fair share" of water at the peak (a fair share is the world's
--                water divided by the participants)
--   kills        E.PerKill for each country finished off
--   place        E.PlacePerMinute a minute x ((1 - (place-1)/(participants-1))^2), not for one who quit
--   win          E.WinPerMinute a minute, the winner only
--   boost        the same again with the "x2 silver" boost
-- Solo is worth a part of it by the bots' difficulty (E.SoloMultiplier); online is worth all of it.
-- Calibrated so that a middling online match (E.Reference: 17 minutes, 4 fair shares, 2 countries, 25th
-- of 80) pays about 1000.
local E={}
E.Round=5
E.Participate=150
E.SurvivePerMinute=20
E.WaterPerShare=40
E.PerKill=60
E.PlacePerMinute=20
E.WinPerMinute=25
E.SoloMultiplier={easy=.4,normal=.7,hard=1}
-- A solo match cannot pay more than this for each real minute since it began (by the server's clock), plus a base.
E.SoloCapPerMinute=220
E.SoloCapBase=100
E.Limits={minutes=240,kills=200,participants=130}
E.Reference={minutes=17,peakShare=4/80,participants=80,kills=2,place=25,won=false,quit=false}
-- Titles of the lines in the end-of-match card.
E.Titles={participate='Taking part',survive='Time in battle',water='Water',kills='Countries taken',place='Place',win='Victory',
 boost='×2 silver',admiral='Admiral +50%',limit='Solo limit'}
local function round(v)return math.floor(v/E.Round+.5)*E.Round end
local function number(v,low,high,default)
 if type(v)~='number'or v~=v then return default end
 return math.clamp(v,low,high)
end
-- mode: {kind = 'online' | 'solo', difficulty}; boosts: {silver2x, admiral}.
-- -> {lines = {{key, amount}, ...}, total}
function E.payout(result,mode,boosts)
 mode=mode or {};boosts=boosts or {}
 local k=mode.kind=='solo'and(E.SoloMultiplier[mode.difficulty]or E.SoloMultiplier.normal)or 1
 local minutes=math.max(0,result.minutes or 0)
 local participants=math.max(2,result.participants or 2)
 local lines={};local total=0
 local function line(key,amount)
  amount=round(amount*k)
  if amount>0 then table.insert(lines,{key,amount});total+=amount end
 end
 if not result.quit then line('participate',E.Participate)end
 line('survive',E.SurvivePerMinute*minutes)
 line('water',E.WaterPerShare*math.max(0,result.peakShare or 0)*participants)
 line('kills',E.PerKill*math.max(0,result.kills or 0))
 if not result.quit then
  local rank=1-(math.clamp(result.place or participants,1,participants)-1)/(participants-1)
  line('place',E.PlacePerMinute*minutes*rank*rank)
 end
 if result.won and not result.quit then line('win',E.WinPerMinute*minutes)end
 local base=total
 if boosts.admiral then local extra=round(base*.5);if extra>0 then table.insert(lines,{'admiral',extra});total+=extra end end
 if boosts.silver2x then if base>0 then table.insert(lines,{'boost',base});total+=base end end
 return {lines=lines,total=total}
end
function E.soloCap(realMinutes)
 return round(E.SoloCapBase+E.SoloCapPerMinute*math.max(0,realMinutes or 0))
end
-- A solo report from a player's device made safe: every field forced into its range, the minutes no
-- longer than the real time since the server saw the match begin.
function E.sanitizeSolo(report,realMinutes)
 report=type(report)=='table'and report or {}
 realMinutes=math.max(0,realMinutes or 0)
 local participants=math.floor(number(report.participants,2,E.Limits.participants,2))
 return {minutes=math.min(number(report.minutes,0,E.Limits.minutes,0),realMinutes),
  peakShare=number(report.peakShare,0,1,0),participants=participants,
  kills=math.floor(number(report.kills,0,math.min(E.Limits.kills,participants-1),0)),
  place=math.floor(number(report.place,1,participants,participants)),
  won=report.won==true,quit=report.quit==true}
end
-- The whole solo payout: sanitized, by difficulty, never above the cap for the real time played.
function E.soloPayout(report,realMinutes,difficulty,boosts)
 local result=E.sanitizeSolo(report,realMinutes)
 local pay=E.payout(result,{kind='solo',difficulty=difficulty},boosts)
 local cap=E.soloCap(realMinutes)
 if boosts and boosts.silver2x then cap*=2 end
 if pay.total>cap then table.insert(pay.lines,{'limit',cap-pay.total});pay.total=cap end
 return pay,result
end
return E
