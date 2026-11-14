--!nonstrict
-- Match authority, diplomacy and OpenFront-derived fleet assistance / victory rules.
local R=require(game.ReplicatedStorage.SeaBattle.NavalRules)
local Config=require(game.ReplicatedStorage.SeaBattle.ConquestConfig)
local compact=require(game.ReplicatedStorage.SeaBattle.NumberFormat).compact
local Names=require(game.ReplicatedStorage.SeaBattle.PersonaNames)
local Catalog=require(game.ReplicatedStorage.SeaBattle.Catalog)
local M={}
local function pair(a,b)if a>b then a,b=b,a end;return a..':'..b end
function M.install(Game)
 function Game:allied(a,b)
  if a==b then return true end
  local fa,fb=self.factions[a],self.factions[b]
  if not fa or not fb then return false end
  return self.settings.teams and fa.team==fb.team or(self.alliances[pair(a,b)]or 0)>self.time
 end
 function Game:diplomacy(owner,action,target)
  if not R.cell(target,#self.factions)or target==owner or not self.factions[target].alive then return false,'invalid'end
  local f=self.factions[owner];local key=pair(owner,target)
  if action=='donate'then
   if not self:allied(owner,target)then return false,'alliance_required'end
   -- No pause between donations (removed by the author's request); each refusal says its own reason.
   local recipient=self.factions[target];local third=math.floor(f.fleet/3)
   local room=math.max(0,self:cap(target)-recipient.fleet);local amount=math.min(third,room)
   if third<1 then return false,'fleet'end
   if amount<1 then return false,'ally_full'end
   f.fleet-=amount;recipient.fleet+=amount
   self:notice(target,'Received '..compact(amount)..' fleet from '..f.name)
   -- The giver hears how much went, and why less than a third when the ally's fleet was near its cap.
   self:notice(owner,'Sent '..compact(amount)..' fleet to '..recipient.name..(amount<third and' (no more fits: the ally\'s fleet is at its limit)'or''))
   return true,'donated'
  elseif action=='alliance'then
   -- Asking someone who already asked us is accepting their offer.
   local q=self.requests[key]
   if q and q.from==target and q.expires>self.time then return self:diplomacy(owner,'accept',target)end
   if self:allied(owner,target)then return false,'already_allied'end
   f.requestAt=f.requestAt or {};if(f.requestAt[target]or 0)>self.time then return false,'request_cooldown'end
   f.requestAt[target]=self.time+30;self.requests[key]={from=owner,to=target,expires=self.time+30}
   self:notice(target,'Alliance offer: '..f.name);return true,'requested'
  elseif action=='accept'or action=='reject'then
   local q=self.requests[key];if not q or q.to~=owner or q.expires<=self.time then return false,'invalid'end
   self.requests[key]=nil
   if action=='accept'then self.alliances[key]=self.time+R.AllianceSeconds;self:notice(target,'Alliance formed: '..f.name)end
   return true,action=='accept'and 'allied'or 'rejected'
  elseif action=='break_alliance'then
   if not self:allied(owner,target)or(self.settings.teams and f.team==self.factions[target].team)then return false,'invalid'end
   self.alliances[key]=nil;f.traitorUntil=self.time+30;self:notice(target,'Alliance broken: '..f.name);return true,'betrayed'
  end
  return false,'invalid'
 end
 function Game:allianceCount(id)
  local n=0
  for key,untilTime in pairs(self.alliances)do if untilTime>self.time then
   local a,b=string.match(key,'^(%d+):(%d+)$');if tonumber(a)==id or tonumber(b)==id then n+=1 end
  end end
  return n
 end
 -- Bots weigh a proposal instead of accepting every request.
 -- offering: the bot is the one proposing; it does not hold a weaker neighbour's size against it.
 function Game:botAcceptsAlliance(to,from,offering)
  local policy=R.difficulty(self.settings.difficulty)
  if to.traitorUntil>self.time or(from.traitorUntil or 0)>self.time then return false end
  if Game.ordersOf(from)[to.id]then return false end
  if(to.retaliation and to.retaliation[from.id]or 0)>self.time then return false end
  -- Nobody helps a runaway leader.
  if from.count>self.grid.data.stats.waterCells*.2 then return false end
  -- Bots keep few partners and will not join an already large bloc.
  if self:allianceCount(to.id)>=policy.allianceMax or self:allianceCount(from.id)>=policy.allianceMax+2 then return false end
  -- A comparable or stronger partner is worth having; a weak one rarely is.
  local strength=from.fleet/math.max(1,to.fleet)
  local chance=offering and policy.allianceChance or policy.allianceChance*math.clamp(strength,.25,1.5)
  chance=math.min(.95,chance*R.botKind(to).alliance)
  return self.random:NextNumber()<chance
 end
 -- A departing human's country is handed to the AI (its name stays as it was, with no AI mark and no notice,
 -- by the author's request); control passes to a remaining player.
 function Game:playerLeft(user,remaining)
  local id=self.clients[user]
  if id then
   self.clients[user]=nil
   local f=self.factions[id]
   if f and f.alive then
    f.bot=true;f.kind='nation';f.nextAction=self.time+2;f.nextBuild=self.time+5;f.graceJitter=f.graceJitter or 0
   end
  end
  if self.controller==user then
   self.controller=nil
   for _,other in ipairs(remaining or {})do if self.clients[other]then self.controller=other;break end end
   if not self.controller then self.controller=(remaining or {})[1]end
  end
 end
 -- A bot looks over its neighbours and may propose an alliance to one it would itself accept.
 -- Human neighbours come first, so a player actually receives offers to decide on.
 function Game:botOfferTarget(f)
  local seen,humans,bots={},{},{};local checked=0
  for cell in pairs(f.frontier)do
   checked+=1;if checked>400 then break end
   local id=self:owner(cell);local e=id>0 and id~=f.id and not seen[id]and self.factions[id]
   if e then seen[id]=true
    local pending=self.requests[pair(f.id,id)]
    local hostile=Game.ordersOf(f)[id]~=nil or Game.ordersOf(e)[f.id]~=nil
    -- A player hears at most one bot offer per HumanOfferGap seconds.
    local resting=not e.bot and(e.offeredAt or -math.huge)>self.time-R.HumanOfferGap
    if e.alive and not pending and not hostile and not resting and not self:allied(f.id,id)then
     table.insert(e.bot and bots or humans,e)
    end
   end
  end
  for _,list in ipairs({humans,bots})do
   while #list>0 do
    local e=table.remove(list,self.random:NextInteger(1,#list))
    if self:botAcceptsAlliance(f,e,true)then return e end
   end
  end
 end
 function Game:botOffers()
  for _,f in ipairs(self.factions)do
   if f.bot and f.alive then
    if not f.nextOffer then f.nextOffer=self.time+self.random:NextNumber(60,R.BotOfferMax)
    elseif self.time>=f.nextOffer then
     f.nextOffer=self.time+self.random:NextNumber(R.BotOfferMin,R.BotOfferMax)
     local partner=self:botOfferTarget(f)
     if partner then if not partner.bot then partner.offeredAt=self.time end;self:diplomacy(f.id,'alliance',partner.id)end
    end
   end
  end
 end
 function Game:diplomacyTick()
  self:botOffers()
  for key,q in pairs(self.requests)do
   if q.expires<=self.time then self.requests[key]=nil
   elseif self.factions[q.to].bot and self.time>q.expires-27 and not q.decided then
    local to,from=self.factions[q.to],self.factions[q.from];q.decided=true
    if to.alive and from.alive and self:botAcceptsAlliance(to,from)then self:diplomacy(to.id,'accept',from.id)
    elseif to.alive and from.alive then self:diplomacy(to.id,'reject',from.id);self:notice(from.id,to.name..' declines the alliance.')end
   end
  end
  for key,untilTime in pairs(self.alliances)do if untilTime<=self.time then self.alliances[key]=nil end end
 end
 function Game:matchTick(dt)
  self.statsClock=(self.statsClock or 0)+dt
  if self.statsClock<2 then return end;self.statsClock=0
  local groups={};local leading,score=nil,0
  local frame={time=self.time,counts={}}
  for _,f in ipairs(self.factions)do
   local key=self.settings.teams and f.team or f.id;groups[key]=(groups[key]or 0)+f.count;frame.counts[f.id]=f.count
   if groups[key]>score then leading,score=key,groups[key]end
  end
  table.insert(self.recordFrames,frame);if #self.recordFrames>900 then table.remove(self.recordFrames,1)end
  -- The demo behind the lobby never ends in a victory; it starts over instead (shared/LocalMatch).
  if self.demo then return end
  -- One rule for every match: 65% of the world's water wins, or the largest country after 30 minutes.
  if score>=self.grid.data.stats.waterCells*R.WinShare then
   self.winner=leading;self.phase='finished';self:notice(0,'Match over. Winner: '..(self.settings.teams and 'team '..leading or self.factions[leading].name))
  -- Or R.MatchSeconds of match time, whichever comes first: then the largest country wins.
  elseif self.time>=R.MatchSeconds and leading then
   self.winner=leading;self.phase='finished'
   self:notice(0,'Time is up ('..math.floor(R.MatchSeconds/60)..' minutes). The largest country wins: '..(self.settings.teams and 'team '..leading or self.factions[leading].name))
  end
 end
 function Game:recordHostility(owner,target)
  local f,enemy=self.factions[owner],self.factions[target]
  if not f or not enemy then return end
  -- A bot remembers who attacked it: any human, and for a tribe (which never strikes first) anyone at
  -- all, so a tribe can hit back at a nation that is eating it.
  if enemy.bot and(not f.bot or not R.botKind(enemy).strikesFirst)then
   enemy.retaliation=enemy.retaliation or {};enemy.retaliation[owner]=self.time+60
  end
  if f.bot and not enemy.bot then self.wars=self.wars or {};self.wars[owner..':'..target]=self.time+15 end
 end
 function Game:mayBotAttack(owner,target)
  local f,enemy=self.factions[owner],self.factions[target]
  if not f or not enemy or not enemy.alive or self:allied(owner,target)or self.time<(enemy.protectedUntil or 0)then return false end
  local retaliating=(f.retaliation and f.retaliation[target]or 0)>self.time
  -- A tribe never strikes first: it only hits back at whoever attacked it.
  if f.bot and not R.botKind(f).strikesFirst and not retaliating then return false end
  if enemy.bot then return true end
  local extra=0;if f.startCell and enemy.startCell then extra=math.clamp((self:distance(f.startCell,enemy.startCell)/(self.grid.width/1024)-40)*.3,0,120)end
  if not retaliating and self.time<(enemy.humanGraceUntil or 0)+(f.graceJitter or 0)+extra then return false end
  local attackers={}
  for _,other in ipairs(self.factions)do if other.bot and other.alive then
   if Game.ordersOf(other)[target]or((self.wars or {})[other.id..':'..target]or 0)>self.time then attackers[other.id]=true end
  end end
  for _,u in pairs(self.units or {})do if u.attackOwner==target or(u.kind=='missile'and self:owner(u.target)==target)then attackers[u.owner]=true end end
  if attackers[owner]then return true end
  local n=0;for _ in pairs(attackers)do n+=1 end
  return n<R.difficulty(self.settings.difficulty).wars
 end
 function Game:attackAssessment(owner,target,borders)
  local f,enemy=self.factions[owner],self.factions[target]
  local amount=f and math.floor(f.fleet*(f.ratio or R.AttackShare))or 0
  local out={allowed=false,reason='start_required',amount=amount,defensePosts=enemy and self:levels(target,'defense',true)or 0}
  if not f or not f.alive or self.phase~='playing'then return out end
  if not enemy or not enemy.alive or target==owner then out.reason='invalid';return out end
  if self:allied(owner,target)then out.reason='alliance_required';return out end
  if self.time<(enemy.protectedUntil or 0)then out.reason='protected';return out end
  local adjacent=borders and borders[target]
  if not borders then for cell in pairs(f.frontier)do if self:owner(cell)==target and self:adjacent(cell,owner)then adjacent=true;break end end end
  if not adjacent then
   if not next(f.shore or {})then out.reason='own_coast_required';return out end
   if not next(enemy.shore or {})then out.reason='landing_coast_required';return out end
   if amount<100 then out.reason='fleet';return out end
   local n=0;for _,u in pairs(self.units)do if u.kind=='transport'and u.owner==owner and u.hp>0 then n+=1 end end
   if n>=R.TransportLimit then out.reason='transport_limit';return out end
   out.allowed=true;out.reason='transport_required';out.mode='air'
   return out
  end
  if amount<20 then out.reason='fleet';return out end
  out.allowed=true;out.reason='available'
  local reserve=enemy.fleet
  out.risk=amount<reserve*.5 and 'high'or amount<reserve and 'contested'or 'advantage'
  return out
 end
 -- Behind the lobby every client plays its own fast bots-only match (shared/LocalMatch); it is never a real one.
 -- Lighter than a real match, since a phone runs it. `rules`: bots (how many of the 80 stay; the rest
 -- are removed before the first frame), startGold and firstBuild (seconds: the first ports come early),
 -- buildPace (later buildings that many times less often), maxBuildings (per bot) and maxTotal (the whole
 -- map, captured buildings included): the late game stays small.
 function Game:startDemo(seed,rules)
  rules=rules or {}
  self:reset(seed);self.demo=true;self.phase='playing';self.buildPace=rules.buildPace or 1;self.maxBuildings=rules.maxBuildings;self.maxTotal=rules.maxTotal
  if rules.bots then self:dropBots(self:botCount()-rules.bots)end
  for _,f in ipairs(self.factions)do if f.bot and f.alive then
   -- No saving margin above the price: the first port goes up as soon as it is affordable.
   f.gold=rules.startGold or f.gold;if rules.startGold then f.thrift=0 end
   if rules.firstBuild then f.nextBuild=self.random:NextNumber(rules.firstBuild[1],rules.firstBuild[2])end
  end end
 end
 function Game:botCount()local n=0;for _,f in ipairs(self.factions)do if f.bot and f.alive then n+=1 end end;return n end
 -- Removes `n` random living bots with all their water (before a match starts: a person takes the
 -- place of a bot, so an online match keeps 80 countries; the lobby demo keeps R.Demo.bots).
 function Game:dropBots(n)
  -- Personas look like people and stay: a person takes the place of a country bot.
  local ids={};for _,f in ipairs(self.factions)do if f.bot and f.alive and not f.persona then table.insert(ids,f.id)end end
  for i=#ids,2,-1 do local j=self.random:NextInteger(1,i);ids[i],ids[j]=ids[j],ids[i]end
  for i=1,math.min(n,#ids)do
   local f=self.factions[ids[i]];local cells={}
   for id in pairs(f.owned)do table.insert(cells,id)end
   for _,id in ipairs(cells)do self:_assign(id,0)end
  end
 end
 -- Turns `n` living nations into bots that play as people: a nickname instead of
 -- a country's name, a default avatar on the client (f.persona), and the novice AI for all but
 -- R.PersonaSmart of them. Tribes stay tribes. A separate generator keeps the match's own draws as they were.
 function Game:assignPersonas(n)
  if self.personasAssigned or n<=0 then return 0 end
  self.personasAssigned=true
  local pick=Random.new(math.floor((self.noiseSeed or 0)*1000)+13)
  -- (never a guaranteed island or polar start: those coasts stay with their countries)
  local ids={};for _,f in ipairs(self.factions)do if f.bot and f.alive and f.kind~='tribe'and not f.persona and not f.spawnSite then table.insert(ids,f.id)end end
  for i=#ids,2,-1 do local j=pick:NextInteger(1,i);ids[i],ids[j]=ids[j],ids[i]end
  local names=table.clone(Names);for i=#names,2,-1 do local j=pick:NextInteger(1,i);names[i],names[j]=names[j],names[i]end
  local taken={};for _,f in ipairs(self.factions)do taken[f.name]=true end
  local made=0
  for _,id in ipairs(ids)do
   if made>=n then break end
   local name;repeat name=table.remove(names)until not name or not taken[name]
   if not name then break end
   local f=self.factions[id];made+=1
   -- `look`: the number its generated Roblox avatar is built from (server/PersonaHeads).
   f.persona=true;f.name=name;taken[name]=true;f.look=pick:NextInteger(1,999999)
   f.kind=made<=R.PersonaSmart and 'nation'or 'novice'
  end
  return made
 end
 -- Online persona bots wear cosmetics like people do (2026-11-12, by the author's request): in every match
 -- a random 1..3 of them wear a flag and, drawn apart, a random 1..3 a water pattern, so some wear both,
 -- some one, most none, and the count changes from match to match. Rarer things are drawn less often
 -- (weights by rarity); the flags of real countries are among them. -> flags, patterns given.
 local WEAR_WEIGHT={common=4,rare=3,epic=2,legendary=1}
 function Game:dressPersonas()
  local pick=Random.new(math.floor((self.noiseSeed or 0)*1000)+29)
  local personas={};for _,f in ipairs(self.factions)do if f.persona then table.insert(personas,f)end end
  if #personas==0 then return 0,0 end
  local function draw(kind)
   local pool,total={},0
   for _,id in ipairs(Catalog.CosmeticOrder)do
    local item=Catalog.Cosmetics[id]
    if item.kind==kind then local w=WEAR_WEIGHT[item.rarity]or 1;total+=w;table.insert(pool,{id,w})end
   end
   local r=pick:NextNumber()*total
   for _,e in ipairs(pool)do r-=e[2];if r<=0 then return e[1]end end
   return pool[#pool][1]
  end
  local function wear(slot)
   local order=table.clone(personas)
   for i=#order,2,-1 do local j=pick:NextInteger(1,i);order[i],order[j]=order[j],order[i]end
   local count=math.min(#order,pick:NextInteger(1,3))
   for i=1,count do order[i][slot]=draw(slot)end
   return count
  end
  return wear('flag'),wear('pattern')
 end
 -- Online: the persona bots join during the countdown like people do. Their countries' starts are cleared
 -- now, and each one picks a random free coast at its own random moment between `from` and `to` (server
 -- time); Game:personaTick places them, the last ones at the latest when the countdown ends.
 function Game:preparePersonas(n,from,to)
  local made=self:assignPersonas(n);if made==0 then return 0 end
  self:dressPersonas()
  for _,f in ipairs(self.factions)do if f.persona then
   local cells={};for id in pairs(f.owned)do table.insert(cells,id)end
   for _,id in ipairs(cells)do self:_assign(id,0)end
   f.startCell=nil;f.placed=false
  end end
  self:schedulePersonas(from,to)
  return made
 end
 -- Spreads the arrivals of the personas still waiting over `from`..`to` (also when the countdown is cut short).
 function Game:schedulePersonas(from,to)
  local pick=Random.new(math.floor((self.noiseSeed or 0)*1000)+17+math.floor(from))
  for _,f in ipairs(self.factions)do if f.persona and not f.placed then
   f.spawnAt=from+(to-from)*pick:NextNumber(.05,.95)
  end end
 end
 -- Places every waiting persona whose moment has come (all of them with `force`) on a random free coast.
 function Game:personaTick(now,force)
  local placed=0
  for _,f in ipairs(self.factions)do
   if f.persona and not f.placed and(force or now>=(f.spawnAt or math.huge))then
    local free={}
    for _,id in ipairs(self.coastCells)do if self:owner(id)==0 and not(self.reservedCoast and self.reservedCoast[id])then table.insert(free,id)end end
    if #free==0 then break end
    local cell=free[self.random:NextInteger(1,#free)]
    f.color=self:colorFor(cell);f.startCell=cell;self:_seed(cell,f.id)
    f.placed=true;f.spawnAt=nil;placed+=1
   end
  end
  return placed
 end
 -- How one country did, for the silver payout (shared/Economy): minutes alive, the largest share of the
 -- world's water it held, countries it finished off, its place, whether it won. Countries count as
 -- participants once they are in the running match (alive, or fallen during it).
 function Game:matchResult(owner)
  local f=self.factions[owner];if not f then return nil end
  local participants,ahead=0,0
  for _,o in ipairs(self.factions)do
   if o.alive or o.diedAt then
    participants+=1
    if o.id~=owner then
     if f.alive then if o.alive and o.count>f.count then ahead+=1 end
     elseif o.alive or(o.diedAt or 0)>(f.diedAt or 0)then ahead+=1 end
    end
   end
  end
  local ended=f.alive and self.time or(f.diedAt or self.time)
  local won=self.phase=='finished'and(self.winner==owner or(self.settings.teams and self.winner==f.team))
  return {minutes=math.max(0,ended-(f.joinedAt or 0))/60,peakShare=math.max(0,math.max(f.peak or 0,f.count or 0)-(f.peakBase or 0))/self.grid.data.stats.waterCells,
   participants=math.max(2,participants),kills=f.kills or 0,place=ahead+1,won=won==true,alive=f.alive==true}
 end
 -- Solo: the player whose country fell takes command of the country that finished it off (a purchase,
 -- shared/Lobby): that country stops being a bot and becomes theirs, with its water, fleet, gold and
 -- buildings as they are. For the results a new life begins: minutes, finished countries and water
 -- gained are counted from this moment.
 function Game:takeover(user)
  local old=self.clients[user];local mine=old and self.factions[old]
  if not mine or mine.alive or self.phase~='playing'then return false,'invalid'end
  local target=mine.killedBy and self.factions[mine.killedBy]
  if not target or not target.alive or not target.bot then return false,'gone'end
  self.clients[user]=target.id
  target.bot=false;target.kind=nil;target.persona=nil;target.look=nil
  local nick=self.playerNames and self.playerNames[user]
  if type(nick)=='string'and nick~=''then target.name=nick end
  target.kills=0;target.diedAt=nil;target.killedBy=nil;target.joinedAt=self.time;target.peak=target.count;target.peakBase=target.count
  target.ratio=R.AttackShare;target.humanGraceUntil=self.time+R.difficulty(self.settings.difficulty).grace
  target.flag=mine.flag;target.pattern=mine.pattern;target.arsenal=mine.arsenal
  self:notice(target.id,'You took command: '..target.name)
  return true,'takeover',target.id
 end
 function Game:humanCount()local n=0;for _ in pairs(self.clients)do n+=1 end;return n end
 function Game:command(user,action,value)
  if type(action)~='string'or not R.finite(user)then return false,'invalid'end
  if action=='settings'then
   -- Only the match type and the bots' difficulty are chosen; everything else is the same for everyone.
   if self.phase~='choosing'or(self.controller and self.controller~=user)or type(value)~='table'then return false,'spectator'end
   local s=self.settings
   if value.difficulty and(value.difficulty=='easy'or value.difficulty=='normal'or value.difficulty=='hard')then s.difficulty=value.difficulty end
   if value.mode and(value.mode=='solo'or value.mode=='online')then s.mode=value.mode end
   for _,f in ipairs(self.factions)do if f.bot then f.fleet=R.difficulty(s.difficulty).start end end
   return true,'configured'
  end
  if action=='start'then
   if self.phase=='finished'or self.clients[user]then return false,'already_started'end
   if self.phase=='playing'and self.settings.mode~='online'then return false,'spectator'end
   -- The lobby's "random" start: any free, unreserved coast.
   if value=='random'then
    local free={}
    for _,id in ipairs(self.coastCells)do if self:owner(id)==0 and not(self.reservedCoast and self.reservedCoast[id])then table.insert(free,id)end end
    if #free==0 then return false,'coast_required'end
    value=free[self.random:NextInteger(1,#free)]
   end
   if not R.cell(value,self.grid.count)or not self.coast[value]then return false,'coast_required'end
   if self:owner(value)~=0 then return false,'occupied'end
   -- Island and Antarctic coasts stay reserved for their guaranteed bot starts.
   if self.reservedCoast and self.reservedCoast[value]then return false,'reserved_coast'end
   local id=Config.PlayerId
   if self.controller then id=#self.factions+1 end
   if id>R.MaxParticipants or self:humanCount()>=R.MaxHumans then return false,'full'end
   local f=self.factions[id]
   if not f then f={id=id,name='Player '..(id-Config.BotCount),owned={},frontier={},count=0,alive=false,bot=false,credit=0};self.factions[id]=f end
   local nick=self.playerNames and self.playerNames[user]
   if type(nick)=='string'and nick~=''then f.name=nick end
   f.color=self:colorFor(value);f.startCell=value;self:_seed(value,id);self:initHuman(f,user)
   -- During an online countdown everyone picks a coast; the match itself starts when it ends.
   if self.phase~='countdown'then self.phase='playing'end
   return true,'started'
  end
  local owner=self.clients[user];local f=owner and self.factions[owner]
  if not f or self.phase~='playing'then return false,'start_required'end
  if not f.alive then return false,'defeated'end
  if action=='ratio'then
   if not R.finite(value)or value<.01 or value>1 then return false,'invalid'end
   f.ratio=value;return true,'configured'
  elseif action=='mobilize'then return self:mobilize(owner)
  elseif action=='retreat'then self:stop(owner,true);return true,'retreated'
  elseif action=='capture'then
   if not R.cell(value,self.grid.count)or not self.grid:isWater(value)then return false,'water_required'end
   local enemy=self:owner(value)
   if enemy==owner then self:stop(owner,true);return true,'stopped'end
   if enemy>0 and self:allied(owner,enemy)then return false,'alliance_required'end
   if enemy>0 and self.time<self.factions[enemy].protectedUntil then return false,'protected'end
   local ok,reason=self:order(owner,value)
   if not ok and reason=='not_adjacent'and enemy>0 then return self:autoTransport(owner,value)end
   return ok,reason
  elseif action=='build'then
   if type(value)~='table'or type(value.kind)~='string'then return false,'invalid'end
   return self:build(owner,value.kind,value.cell,type(value.reach)=='number'and value.reach or nil)
  elseif action=='fighter'or action=='missile'then
   -- The player names only the spot; the nearest ready airport or silo of theirs takes the order.
   if type(value)~='table'or not R.cell(value.cell,self.grid.count)then return false,'invalid'end
   if action=='fighter'then return self:launchFighterAt(owner,value.cell)end
   if type(value.kind)~='string'then return false,'invalid'end
   return self:launchMissileAt(owner,value.cell,value.kind)
  elseif action=='move_fighter'then
   if type(value)~='table'or type(value.unit)~='number'or not R.cell(value.cell,self.grid.count)then return false,'invalid'end
   return self:moveFighter(owner,value.unit,value.cell)
  elseif action=='break_attack'then
   -- Break an alliance and attack the former ally at the tapped water in one step.
   if type(value)~='table'or not R.cell(value.cell,self.grid.count)then return false,'invalid'end
   local enemy=self:owner(value.cell)
   if enemy==0 or enemy==owner then return false,'invalid'end
   local ok,reason=self:diplomacy(owner,'break_alliance',enemy)
   if not ok then return ok,reason end
   return self:command(user,'capture',value.cell)
  end
  return self:diplomacy(owner,action,value)
 end
end
return M
