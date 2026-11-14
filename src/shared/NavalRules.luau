--!nonstrict
-- Adapted from OpenFront Config.ts / EngineConfig.ts, revision 103bba550d3a39ceb623179a04687719cf8a051b.
-- © OpenFront and Contributors. AGPL-3.0 with upstream Section 7 terms; see LICENSE.
-- Modified 2026-11-02: water conquest, fleet naming, airports, gas/oil stations, equal participant rules.
local R={Upstream="103bba550d3a39ceb623179a04687719cf8a051b",StartFleet=25000,StartGold=0,
 Tick=.1,GoldPerSecond=2500,TradeIncome=1.5,AttackShare=.25,AttackShares={.25,.4,.5,.6,.75},TransportLimit=3,StartingProtection=5,AllianceSeconds=300,
 BotBuildEdgeMargin=16,BuildSpacing=5,SameKindSpacing=12,BuildSnap=12,TrainSpeed=20,TrainInterval=8,FlightInterval=30,AnnexBelow=30,ThinSweepLimit=4000,FrontWaves=4,FrontNoise=2,ExpansionNoise=.6,FrontCellsPerSecond=2,MaxCaptureRate=2000,StationRange=80,DefenseRange=22,DefenseLoss=5,DefenseSlow=3,CombatAreaPerSecond=.1,AirportRepairRange=108,AircraftSpeed=12,
 FighterSpeed=14.4,FighterRange=26,FighterHunt=32,CaptureRange=2,HuntBoost=1.43,BotSiteChecks=300,BotOfferMin=150,InterceptShow=.5,BotOfferMax=300,HumanOfferGap=150,PocketLimit=100,PatrolRadius=55,FighterDamage=200,MaxParticipants=130,MaxHumans=50,CountdownSeconds=15,QueueWait=20,TeleportLead=25,ResultsSeconds=20,IdleResetSeconds=30,WinShare=.65,MatchSeconds=1800,PartySize=5,DemoSeconds=720,SnapshotCooldown=3}
R.Buildings={
 port={name="Port",symbol="P",seconds=2,base=125000,land=true},
 airport={name="Airport",symbol="A",seconds=5,base=125000,land=true},
 oil={name="Oil Rig",symbol="O",seconds=2,base=125000,income=1},
 gas={name="Gas Rig",symbol="G",seconds=2,base=75000,income=.5},
 defense={name="Sea Defense Post",symbol="D",seconds=5,base=50000},
 sam={name="Missile Defense",symbol="S",seconds=30,base=1500000},
 silo={name="Missile Platform",symbol="M",seconds=10,base=1000000},
 -- Arsenal (shared/Catalog: opened for silver; `arsenal` names the unlock a country needs to build it).
 -- A coastal battery shells the fleet of the nearest foreign country with water in range; it stands
 -- anywhere on the owner's water (2026-11-11, by the author's request: it was a land building).
 battery={name="Coastal Battery",symbol="B",seconds=8,base=400000,arsenal="battery"},
}
-- Coastal battery: every Interval seconds it takes Share of the target's fleet (at least Min) from one
-- country whose water lies within Range cells; never from an ally or a protected start.
R.Battery={Range=45,Interval=4,Share=.004,Min=200,Step=5}
-- Mobilisation: for gold, Share of the fleet cap at once (as much as there is room for), then a pause.
R.Mobilize={Share=.2,GoldPerFleet=1,Cooldown=30}
-- Hydrogen bomb: 15 / 45 cells (was 22 / 72: too much of the map at once, by the author's request).
-- MIRV: the carrier flies to the aim and splits there into up to Mirv.warheads
-- warheads, each aimed at a random cell of the target country's water within Mirv.spread cells of the
-- aim and at least Mirv.gap cells from the others; each warhead is a small blast of its own and can be
-- shot down by a missile defence (the carrier cannot). Neutral water under the aim: one warhead.
-- `internal` weapons are never launched by a player (the warhead comes only off a MIRV).
R.Weapons={atom={name="Atomic Missile",cost=750000,inner=9,outer=22},
 hydrogen={name="Hydrogen Missile",cost=5000000,inner=15,outer=45},
 mirv={name="MIRV",cost=25000000,inner=0,outer=0},
 warhead={name="MIRV Warhead",cost=0,inner=4,outer=10,internal=true},
 -- Arsenal weapons (`arsenal`: the unlock a country needs to launch it).
 -- A torpedo (2026-11-11: in place of the depth bomb, by the author's request; it keeps the unlock
 -- "depthbomb" so profiles and the Robux product stay valid): it runs under water, so missile
 -- defences never see it, but only along a straight line of water from a ready platform to the aim
 -- (no land in between: Game:waterLine). Slower than a missile (`speed` cells a second).
 torpedo={name="Torpedo",cost=2000000,inner=11,outer=30,arsenal="depthbomb",torpedo=true,speed=18},
 -- A cluster missile: an atom blast at the aim and `bomblets` small warheads around it (within `spread`
 -- cells, `gap` apart); a missile defence downs them one at a time, so one cannot stop them all.
 cluster={name="Cluster Missile",cost=1500000,inner=9,outer=22,arsenal="cluster",bomblets=5,spread=28,gap=9},
 bomblet={name="Cluster Bomblet",cost=0,inner=3,outer=9,internal=true},
 -- Bombers: leave from an airport (not a platform), reach `range` cells from it, and get past each
 -- missile defence on their way with the chance `evade` (they are not invulnerable).
 bomb={name="Bombers",cost=600000,inner=6,outer=16,arsenal="bombers",airport=true,range=150,evade=.5,reload=20},
 -- A coastal battery's shell: only drawn (the battery takes the fleet when it fires, sim/NavalArsenal);
 -- missile defences ignore it.
 shell={name="Battery Shell",cost=0,inner=0,outer=2,internal=true,shell=true}}
R.Mirv={warheads=80,spread=120,gap=12}
-- Difficulty: nation resources, decision cadence and human grace.
-- defense: how many defence posts a bot plans. threat = {at least, one more per N pixels, at most} while it
-- is attacked; calm = {from N pixels, one more per M pixels (0 = never), at most} otherwise. Easy keeps the
-- old tight cap, normal allows about twice as many, hard almost none.
-- speed scales bot fronts; botWarAt delays bot-vs-bot wars; edge is the fleet ratio a bot wants before attacking;
-- allianceChance / allianceMax control how readily a bot accepts a proposed alliance.
R.Difficulties={easy={start=10000,cap=.45,growth=.85,grace=600,wars=1,skip=.85,thinkMin=8,thinkMax=12,share=.15,speed=.35,botWarAt=240,edge=1.5,allianceChance=.75,allianceMax=4,
  defense={threat={2,5000,6},calm={6000,0,1}}},
 normal={start=15000,cap=.65,growth=.92,grace=360,wars=2,skip=.4,thinkMin=6,thinkMax=8,share=.22,speed=.55,botWarAt=150,edge=1.25,allianceChance=.5,allianceMax=3,
  defense={threat={3,2500,10},calm={3000,8000,3}}},
 hard={start=25000,cap=1,growth=1,grace=150,wars=3,skip=.05,thinkMin=4.5,thinkMax=6,share=.35,speed=.8,botWarAt=60,edge=1.05,allianceChance=.3,allianceMax=2,
  defense={threat={4,1200,24},calm={1500,3000,8}}}}
function R.difficulty(name)return R.Difficulties[name]or R.Difficulties.normal end
-- Kinds of bots (tribes and nations). The economy is the same for all of them: income,
-- fleet growth, prices and caps come from the difficulty alone. A kind only changes decisions: whom and
-- when to attack, what to build first, how readily to ally.
--  * tribe   — muted brown, many per match: grows into free water, never strikes first (only hits back
--              at whoever attacked it), builds only ports, stations and defence posts. Filler that the
--              nations and players eat as the match goes on.
--  * trader  — a nation that builds its economy first (ports, stations, airports), waits for a larger
--              fleet edge before attacking and allies readily.
--  * warlord — a nation that attacks with a smaller edge and a larger share, thinks faster, builds
--              defence, silos and fighters, and rarely allies.
--  * nation  — the plain balanced nation (the old behaviour).
-- Multipliers apply to the difficulty's values (edge, skip, botWarAt, think time, alliance chance);
-- share is added to the difficulty's attack share; build weights multiply the build goals (0 = never).
R.TribeShare=.25
R.TribeColor={150,95,70}
R.BotKinds={
 tribe={name='Tribe',edge=1,skip=1,warAt=1,think=1.3,share=-.05,alliance=.6,fighters=0,missiles=false,strikesFirst=false,
  build={port=1,oil=1,gas=1,defense=1.5,airport=0,silo=0,sam=0}},
 trader={name='Trading Power',edge=1.3,skip=1.3,warAt=1.3,think=1.1,share=-.04,alliance=1.5,fighters=.5,missiles=true,strikesFirst=true,
  build={port=1.6,oil=2,gas=2,airport=1.6,defense=.8,silo=.5,sam=1}},
 warlord={name='Warlike Power',edge=.8,skip=.5,warAt=.7,think=.8,share=.08,alliance=.5,fighters=2,missiles=true,strikesFirst=true,
  build={port=1,oil=.8,gas=.8,airport=1.3,defense=1.8,silo=1.6,sam=1.2}},
 -- A bot that plays as a person (Game:assignPersonas): most are novices —
 -- slow to attack, long peace with people, few missiles; R.PersonaSmart of them play as full nations.
 novice={name='Newcomer',edge=1.4,skip=1.5,warAt=1.4,think=1.3,share=-.05,alliance=1.2,fighters=.5,missiles=true,strikesFirst=true,
  build={defense=.8,silo=.6,sam=.8}},
 nation={name='Power',edge=1,skip=1,warAt=1,think=1,share=0,alliance=1,fighters=1,missiles=true,strikesFirst=true,build={}},
}
-- Bots that look like people (a nickname and a default avatar) fill an online match: every seat a person
-- did not take, up to R.MaxHumans participants who look human. Never in
-- a solo match (author, 2026-11-07).
R.Personas={online=R.MaxHumans}
R.PersonaSmart=2
function R.botKind(f)return R.BotKinds[f and f.kind or 'nation']or R.BotKinds.nation end
function R.finite(v)return type(v)=="number"and v==v and math.abs(v)<1e15 end
function R.cell(v,max)return R.finite(v)and v%1==0 and v>=1 and v<=max end
function R.cap(area,ports)return 2*(math.max(0,area)^.6*1000+50000)+(ports or 0)*250000 end
function R.growth(fleet,cap)return math.min(fleet+(10+math.max(0,fleet)^.73/4)*(1-fleet/math.max(1,cap)),cap)-fleet end
local function large(n,depth)return 1-depth/(1+math.exp(-2.5*(math.log(math.max(1,n))-math.log(300000))))end
function R.battle(stack,attacker,defender,border,fortified,fallout)
 local mag,cost=80,16.5
 if fortified then mag*=R.DefenseLoss;cost*=R.DefenseSlow end
 if fallout then mag*=3;cost*=3 end
 if not defender then return 16,0,math.clamp(2000*cost/math.max(1,stack),5,100)/math.max(1,border*2)end
 local density=defender.fleet/math.max(1,defender.count);local ratio=defender.fleet/math.max(1,stack)
 local a,d=large(attacker.count,.7),large(defender.count,.3)
 local traitor=defender.traitorActive
 local loss=mag*(traitor and .5 or 1)*math.clamp(ratio,.6,2)*(.463*a*d+.0039*density)
 local speed=math.clamp(ratio,.82,7.5)*math.clamp(ratio/20,1,50)/8.55
 return loss,density,speed*cost*large(attacker.count,.73)*d*(traitor and .8 or 1)/math.max(1,border)
end
function R.cost(kind,count)
 local info=R.Buildings[kind];if not info then return nil end
 if kind=="defense"then return math.min(250000,50000*(count+1))end
 if kind=="sam"then return math.min(3000000,1500000*(count+1))end
 if kind=="silo"then return 1000000 end
 return math.min(info.base*8,info.base*2^math.min(count,4))
end
function R.fighterCost(count)return math.min(1000000,250000*(count+1))end
function R.tradeGold(distance)return math.floor(75000/(1+math.exp(-.03*(distance/.72-300)))+50*distance/.72)end
function R.localGold(ally,own)return own and 10000 or ally and 35000 or 25000 end
-- Seconds between shots: missile defence and missile platforms (shown as a bar under the icon).
-- (`fast`: the owner has the arsenal's fast reload — half the time)
function R.reload(kind,level,fast)level=math.max(1,level or 1);return(kind=='sam'and 4/level or kind=='silo'and 90/level or 0)*(fast and .5 or 1)end
function R.samRange(level)return (150-480/(level+5))*.72 end
-- The lobby's demo match (shared/LocalMatch, Game:startDemo): a fast start that slows down, early first
-- ports, and a small late game so a phone can run it.
R.Demo={bots=50,startGold=110000,firstBuild={2,7},buildPace=3,maxBuildings=2,maxTotal=75,
 -- Speed (match seconds per real second) by match time: fast while countries grow from nothing.
 -- (phones run it at the same speed as a computer: 2026-11-13, the author's request)
 speed={{0,8},{45,8},{120,3},{240,2}}}
function R.demoSpeed(t)
 local k=R.Demo.speed
 for i=2,#k do if t<k[i][1]then local a,b=k[i-1],k[i];return a[2]+(b[2]-a[2])*(t-a[1])/(b[1]-a[1])end end
 return k[#k][2]
end
return R
