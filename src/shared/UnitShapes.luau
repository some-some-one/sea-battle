--!nonstrict
-- Unit shapes in the map's pixel style (BattleView draws them on the map, ArsenalDemo in the shop's
-- previews): axis-aligned rectangles in unit pixels, in the owner's colour, each with a thin darker rim.
-- A piece is {width, height, x, y}: x, y move it from the unit's centre (0 when left out). `light`
-- pieces are drawn white under the dark marks. A shape with `turn` faces where the unit flies (drawn
-- pointing along +x); `fill` / `mix` blend the owner colour toward a colour, `rim` replaces the rim's.
-- Arsenal weapons have their own (2026-11-11, by the author's request, so one sees what flies):
--  * bomber   — a plane seen from above: fuselage, wide wings, tail plane, cockpit and engines;
--  * torpedo  — a long dark body with fins, its colour washed toward the sea (it runs under water),
--               two bubbles behind it;
--  * cluster  — a fat body with three dark bomblets in it, a nose and two fins;
--  * mirv     — the biggest: a heavy body with a white skull, nose cone and fins;
--  * shell    — a coastal battery's shot: one bright pixel.
local SEA=Color3.fromRGB(22,58,92)
local SHAPES={ship={pieces={{4,2}}},
 plane={pieces={{5,1},{1,5},{3,3}}},
 fighter={pieces={{7,1},{1,7},{5,3},{3,5}},mark={{3,1},{1,3}},scale=.85},
 missile={pieces={{3,1},{1,3}}},
 hydrogen={pieces={{5,1},{1,5},{3,3}},mark={{1,1}},scale=.9},
 bomber={turn=true,scale=.75,pieces={{9,2,0,0},{3,13,.5,0},{2,6,-4,0},{1,1,5,0}},
  mark={{2,2,3,0},{2,1,.5,-4},{2,1,.5,4}}},
 torpedo={turn=true,scale=.8,fill=SEA,mix=.45,rim=Color3.fromRGB(10,26,44),pieces={{8,2,0,0},{1,1,4.5,0},{1,4,-3.5,0}},
  mark={{1,2,-4.5,0}},light={{1,1,-7,-1},{1,1,-9,.5}}},
 cluster={turn=true,scale=.85,pieces={{6,3,0,0},{1,1,3.5,0},{2,1,-2,-2},{2,1,-2,2}},
  mark={{1,1,-1.5,0},{1,1,.5,0},{1,1,2.5,0}}},
 mirv={turn=true,scale=.8,pieces={{10,5,0,0},{2,3,6,0},{1,1,7.5,0},{3,2,-4.5,-3.5},{3,2,-4.5,3.5}},
  light={{4,3,0,-.5},{2,1,0,1.5}},mark={{1,1,-1,-.5},{1,1,1,-.5},{1,1,0,1.5}}},
 shell={pieces={{1,1}},fill=Color3.fromRGB(255,236,160),mix=1,rim=Color3.fromRGB(255,150,60)}}
-- The shape of each missile (the rest are the small diamond).
local WEAPON_SHAPE={hydrogen='hydrogen',bomb='bomber',torpedo='torpedo',cluster='cluster',mirv='mirv',shell='shell'}
return {list=SHAPES,weapon=WEAPON_SHAPE,sea=SEA}
