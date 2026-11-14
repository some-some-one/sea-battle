--!nonstrict
-- The soundtrack (2026-11-12, by the author's request: tracks by mood). Every track
-- is licensed library music from Roblox's Creator Store (APMOfficial, "Courtesy of APM Music"): free for any
-- Roblox experience, no attribution required; the help window names it all the same. Each id was checked
-- in Studio: it loads and plays (length in seconds below, rounded).
-- Moods (shared/Music picks one): title — the lobby; wait — the online queue and countdown; calm — a match
-- at peace; war — while the player fights another country (and 40 s after); victory / defeat — once,
-- after the result.
local T={}
T.credit='Music: APM Music, licensed through the Roblox library'
T.moods={
 title={
  {1837132634,'Prelude to the Odyssey',93},   -- the first track the game ever plays
  {1845349070,'Epic Quest',92},
  {9042799548,'Protector Of The Sky',144},
  {1837252471,'Legends Unfold',163},
  {1839321940,'The Kingdom',131},
 },
 wait={
  {1835239194,'Uncertain Outcome',123},
  {9043585893,'Night Search (b)',210},
  {9045929119,'Ancient Grounds (underscore)',128},
 },
 calm={
  {9042589035,'Summer Dawn (strings)',148},
  {9042189669,'Inspirational Moment (c)',124},
  {1842007544,'Into the Blue Sky (b)',145},
  {9046394240,'Taking Flight',152},
  {9046380861,'Golden Sunsets',134},
  {1848105094,'Everlasting A',128},
  {1840878735,'Brave Hearts (A)',92},
  {1845404643,'Progression',136},
  {9048112554,'Into The Atmosphere (b)',95},
  {1844248813,'Impressions Of Beauty (c)',94},
  {9045218281,'The Great Beyond (no percussion)',115},
  {1835238974,'Hope Amidst Desolation (strings)',99},
  {1837302624,'Follow the Light (alternate 1)',104},
  {1840765228,'Gloriana (C)',267},
  {9044561897,'When Stars Collide (underscore)',150},
 },
 war={
  {9048541013,'Battleground',131},
  {1848161656,'War Lords A',123},
  {1837240654,'On the Warpath',115},
  {1839391424,'Triumph Of The Braves',97},
  {9038839763,'Storm The Fortress E',119},
  {1839725229,'Royal Supremacy',121},
  {9042559426,'Destiny War',133},
  {1846428560,'Forces Of Nature B',122},
  {9046503137,'Imminent Closure',110},
  {1841702548,'Dark Water a',150},
  {1839736658,'Epic Rider',91},
 },
 victory={{1847032089,'Return Of The King',111}},
 defeat={{1844256509,'Final Farewell (c)',136}},
}
return T
