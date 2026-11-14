-- Shared match sizing and equal total growth per country (pixels / simulation second).
local BOT_COUNT=80
local EXPANSION_SPEED=200
return {
 BotCount=BOT_COUNT,
 PlayerId=BOT_COUNT+1,
 ParticipantCount=BOT_COUNT+1,
 BotSpeed=EXPANSION_SPEED,
 PlayerSpeed=EXPANSION_SPEED,
 SpawnQuotas={['north-america']=12,['south-america']=12,europe=11,africa=11,asia=11,oceania=11,
  ['ocean-islands']=10,antarctica=2},
}
