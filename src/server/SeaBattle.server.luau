--!nonstrict
-- Two kinds of server run this place (attribute SeaBattle.ServerRole):
--  * "hub" — a public server: the lobby, solo matches (they run on each client, shared/LocalMatch) and
--    the online queue (Matchmaker). It runs no match of its own.
--  * "match" — a reserved server the matchmaker made for one group: everyone arrives together, picks a
--    coast during the countdown (until the start time the leader set, or sooner once all have picked),
--    then the match starts for all at once; one bot gives way for each person (80 countries in all).
--    Nobody joins a running match. After the results everyone goes back to a hub.
-- In Studio (no teleports) a hub turns into a match server for its queued players, and back afterwards.
-- Everything goes out through shared/Wire: one encoded (and compressed) message per step for all.
local Players=game:GetService("Players")
Players.CharacterAutoLoads=false
-- No text chat and no voice for anyone (server/NoTalk).
require(script.Parent.NoTalk).start()

local shared=game:GetService("ReplicatedStorage"):WaitForChild("SeaBattle")
local R=require(shared.NavalRules)
local Wire=require(shared.Wire)
local session=require(script.Parent.WorldSession)
local Backend=require(script.Parent.Backend)
local Matchmaker=require(script.Parent.Matchmaker)
local PersonaHeads=require(script.Parent.PersonaHeads)
local Account=require(script.Parent.Account)
local Party=require(script.Parent.Party)
local data,grid=session.data,session.grid
local gameState=session.conquest
local api=Instance.new("Folder");api.Name="ConquestAPI";api.Parent=shared
local command=Instance.new("RemoteFunction");command.Name="Command";command.Parent=api
local changed=Instance.new("RemoteEvent");changed.Name="Changed";changed.Parent=api
local queueStatus=Instance.new("RemoteEvent");queueStatus.Name="Queue";queueStatus.Parent=api
-- The player's own saved profile (silver, daily bonus, purchases): server/Account sends it after every change.
local profileEvent=Instance.new("RemoteEvent");profileEvent.Name="Profile";profileEvent.Parent=api
Account.start(profileEvent)
-- Parties (server/Party): the client's view of its party after every change.
local partyEvent=Instance.new("RemoteEvent");partyEvent.Name="Party";partyEvent.Parent=api
Party.start(partyEvent,{cancel=function(player)Matchmaker.leave(player)end})
-- An arsenal item opened during a match (for silver or Robux): the player's country gets it at once.
Account.unlocksChanged=function(userId)
 local id=gameState and gameState.clients[userId]
 local faction=id and gameState.factions[id]
 if faction and faction.alive then Account.dress(userId,faction)end
end
local last={};local busy={};local lastSnapshot={};local pending={}
local COMMAND_GAP,COMMAND_QUEUE=.16,8
local stats={steps=0,stepTime=0,stepMax=0,bytes=0,messages=0}
local role=Matchmaker.isMatchServer()and "match"or "hub"
local expected={}          -- match server: UserIds the matchmaker sent here
local endMatch
-- What every client already holds; only differences are sent again (Sim/NetSync + Wire deltas).
local net,wire
local function resetNet()net=gameState:newNet();wire=Wire.newEncoder()end
local function now()return workspace:GetServerTimeNow()end
local function send(msg)stats.bytes+=buffer.len(msg)*#Players:GetPlayers();stats.messages+=1;changed:FireAllClients(msg)end
-- After a reset every client gets the whole new map at once.
local function broadcast()resetNet();send(Wire.encode({snapshot=gameState:snapshot()},wire))end
local function setRole(r)role=r;shared:SetAttribute("ServerRole",r)end
-- The whole map for one client, encoded once for as long as nothing changed (a hub's map never does;
-- during a countdown everyone arrives at once).
local snapCache
local function snapshotMessage()
 local g=gameState
 local key=table.concat({tostring(g.epoch),tostring(g.revision),tostring(g.time),tostring(g.phase),tostring(g.structureRevision),tostring(g.countdownEnds),g:humanCount()},':')
 if not snapCache or snapCache.key~=key then snapCache={key=key,msg=Wire.encode({snapshot=g:snapshot()},nil)}end
 return snapCache.msg
end
local function freshMap()
 gameState:reset();gameState.settings.mode='online';gameState.settings.difficulty='normal'
 gameState.finishedAt=nil;gameState.idleSince=nil;gameState.leftAt=nil
end
-- Start a match for `users` (UserIds) at `startsAt` (os.time()): the countdown runs until then.
local function openMatch(users,startsAt)
 freshMap();expected={}
 for _,u in ipairs(users)do expected[u]=true end
 gameState.phase="countdown";gameState.countdownEnds=now()+math.max(5,startsAt-os.time())
 -- Persona bots fill every seat the matchmaker did not give a person; they arrive during the countdown.
 gameState:preparePersonas(math.max(0,R.Personas.online-#users),now(),gameState.countdownEnds)
 -- Their avatars: generated Roblox avatars built from the looks while the countdown runs.
 PersonaHeads.build(gameState)
 broadcast()
end
local payOut
command.OnServerInvoke=function(player,action,value)
 local clock=os.clock()
 if action=="snapshot" then
  -- The whole map (compressed): clients ask on joining and when they switch to the server's map.
  if lastSnapshot[player] and clock-lastSnapshot[player]<R.SnapshotCooldown then return {ok=false,reason="slow_down"}end
  lastSnapshot[player]=clock
  return {ok=true,snapshot=snapshotMessage()}
 end
 -- At most one command per COMMAND_GAP seconds: each call takes the next free slot of its player (calls
 -- sent together run one after another, not all at once), and no more than COMMAND_QUEUE of them wait.
 if(pending[player]or 0)>=COMMAND_QUEUE then return {ok=false,reason="slow_down"}end
 pending[player]=(pending[player]or 0)+1
 local slot=math.max(clock,(last[player]or 0)+COMMAND_GAP);last[player]=slot
 if slot>clock then task.wait(slot-clock)end
 -- A command that searches routes can take a moment; the next one waits for it instead of being refused.
 local waited=0
 while busy[player]and waited<3 do waited+=task.wait()end
 if pending[player]then pending[player]-=1 end
 if not player.Parent then return {ok=false,reason="invalid"}end
 if busy[player]then return {ok=false,reason="slow_down"}end
 -- The account (silver, daily bonus, shop): the same on a hub and on a match server.
 local account=Account.command(player,action,value)
 if account then return account end
 if role=="hub"then
  -- A hub only queues players for an online match.
  -- (a party searches as one: only its leader starts or stops the search)
  if action=="party"then return Party.command(player,value)end
  if(action=="queue"or action=="unqueue")and not Party.isLeader(player)then return {ok=false,reason="party_leader"}end
  if action=="queue"then local ok,reason=Matchmaker.join(Party.members(player));return {ok=ok,reason=reason or "queued"}end
  if action=="unqueue"then Matchmaker.leave(player);return {ok=true,reason="unqueued"}end
  return {ok=false,reason="invalid"}
 end
 if action=="leave"then
  -- Leaving the match for the lobby: the country plays on under the AI (Studio: the match just ends).
  if game:GetService("RunService"):IsStudio()then
   if gameState.phase=="playing"then payOut(player.UserId,true)end
   task.defer(endMatch);return {ok=true,reason="leaving"}
  end
  -- ("Play again" on the end card: the lobby server starts a new search for this player by itself.)
  if not Matchmaker.toHub({player},type(value)=="table"and value.again==true)then return {ok=false,reason="invalid"}end
  return {ok=true,reason="leaving"}
 end
 if action=="queue"or action=="unqueue"then return {ok=true,reason="queued"}end
 -- Nobody joins a running match: a coast is picked only during the countdown (the simulation itself
 -- allows a late start, for tests). Match settings are not a player's to change here either.
 if action=="start"and gameState.phase~="countdown"then return {ok=false,reason="match_running"}end
 if action=="settings"then return {ok=false,reason="invalid"}end
 busy[player]=true
 -- A player's country is named after their Roblox display name.
 gameState.playerNames=gameState.playerNames or {};gameState.playerNames[player.UserId]=player.DisplayName
 local success,ok,reason=pcall(gameState.command,gameState,player.UserId,action,value)
 busy[player]=nil
 if not success then warn("[SeaBattle command] "..tostring(ok));return {ok=false,reason="invalid"}end
 -- A new country wears its player's flag and water pattern (from the profile, never from the client).
 if ok and action=="start"then Account.dress(player.UserId,gameState.factions[gameState.clients[player.UserId]])end
 -- Ownership and the shared state together: a new country and the phase arrive in one message.
 if ok then local packet=gameState:changes();packet.shared=gameState:sharedState();send(Wire.encode(packet,wire));net.force=true end
 return {ok=ok,reason=reason}
end
-- Silver for the match (shared/Economy), once for each person: when their country falls, when the match
-- ends, or when they leave early (then without the lines for taking part and for the place).
local paid={}
payOut=function(userId,quit)
 local owner=gameState.clients[userId]
 local key=gameState.epoch..":"..userId
 if not owner or paid[key]then return end
 paid[key]=true
 local result=gameState:matchResult(owner);if not result then return end
 result.quit=quit==true
 task.spawn(Account.payOnline,userId,result,game.JobId..":"..key)
end
local function payOuts()
 if gameState.phase~="playing"and gameState.phase~="finished"then return end
 for userId,owner in pairs(gameState.clients)do
  local f=gameState.factions[owner]
  if f and(not f.alive or gameState.phase=="finished")then payOut(userId,false)end
 end
end
Players.PlayerRemoving:Connect(function(player)
 last[player]=nil;busy[player]=nil;lastSnapshot[player]=nil;pending[player]=nil
 -- Leaving a running match with a living country: paid now, as one who quit.
 if role=="match"and gameState.phase=="playing"then payOut(player.UserId,true)end
 local remaining={}
 for _,other in ipairs(Players:GetPlayers())do if other~=player then table.insert(remaining,other.UserId)end end
 gameState:playerLeft(player.UserId,remaining);net.force=true
end)
local function sync()
 local packet,step,force=gameState:syncPacket(net)
 send(Wire.encode(packet,wire))
 if step%2==0 or force then
  local full=step%5==0 or force
  for _,player in ipairs(Players:GetPlayers())do
   local owner=gameState.clients[player.UserId]
   if owner then
    local msg=Wire.pack({epoch=gameState.epoch,private=gameState:privateState(owner,full)})
    stats.bytes+=buffer.len(msg);changed:FireClient(player,msg)
   end
  end
 end
end
-- Back to being a hub (Studio) or sending everyone to one (a reserved match server).
endMatch=function()
 Backend.event("match_end",{winner=gameState.winner})
 if game:GetService("RunService"):IsStudio()then setRole("hub");freshMap();broadcast()
 else Matchmaker.toHub(Players:GetPlayers())end
end
-- Phase changes the clock drives on a match server: the start, the results.
local function lifecycle()
 local t=now()
 if gameState.phase=="countdown"then
  -- Everyone the matchmaker sent is here and has a coast: no need to wait for the full countdown.
  local all=next(expected)~=nil
  for u in pairs(expected)do if not gameState.clients[u]then all=false;break end end
  if all and(gameState.countdownEnds or 0)-t>3 then gameState.countdownEnds=t+3;gameState:schedulePersonas(t,t+2.7);net.force=true end
  -- Persona bots pick their coasts one by one, like people arriving.
  if gameState:personaTick(t)>0 then net.force=true end
  if t<(gameState.countdownEnds or 0)then return end
  gameState:personaTick(t,true)
  -- Players here without a coast get a random one; then a bot gives way for each person.
  for _,player in ipairs(Players:GetPlayers())do
   if not gameState.clients[player.UserId]then
    gameState.playerNames=gameState.playerNames or {};gameState.playerNames[player.UserId]=player.DisplayName
    gameState:command(player.UserId,'start','random')
    Account.dress(player.UserId,gameState.factions[gameState.clients[player.UserId]])
   end
  end
  if gameState:humanCount()==0 then endMatch();return end
  gameState:dropBots(gameState:humanCount())
  gameState.phase="playing";gameState.countdownEnds=nil;net.force=true
  Backend.event("match_start",{humans=gameState:humanCount()})
 elseif gameState.phase=="finished"then
  gameState.finishedAt=gameState.finishedAt or t
  -- After the results everyone goes back to a hub; a teleport that fails is tried again every 10 s.
  if t-gameState.finishedAt>=R.ResultsSeconds and t-(gameState.leftAt or -1e9)>=10 then gameState.leftAt=t;endMatch()end
 end
end
assert(workspace:FindFirstChild("SeaBattleWorld"),"Open the built SeaBattle.rbxlx place")
freshMap();resetNet();setRole(role)
Matchmaker.start(queueStatus,{parties=Party.tagsFor,onLocalMatch=function(players)
 -- Studio: this server becomes the match server for its queued players.
 local users={};for _,p in ipairs(players)do table.insert(users,p.UserId)end
 setRole("match");openMatch(users,os.time()+10)
end})
if role=="match"then
 task.spawn(function()
  local info=Matchmaker.matchInfo()
  if info then openMatch(info.users or {},info.startsAt or os.time()+10)
  else openMatch({},os.time()+10)end
 end)
end
task.spawn(function()
 local previous=os.clock();local accumulator=0;local lastStepWarning=-math.huge
 while true do
  task.wait(.1)
  local clock=os.clock()
  accumulator+=math.min(clock-previous,.5);previous=clock
  if role~="match"then accumulator=0;continue end
  -- An error in a step must not end the match for everyone: it is reported (at most once in 5 s), the
  -- time owed is dropped and the next message carries the whole shared state again.
  local ok,err=xpcall(function()
   -- Include time spent simulating/sending the previous update. Fixed steps
   -- preserve the shared pixel budget when a server frame takes slightly longer.
   while accumulator>=.1 do
    local a=os.clock();gameState:tick(.1);local d=os.clock()-a
    stats.steps+=1;stats.stepTime+=d;stats.stepMax=math.max(stats.stepMax,d)
    accumulator-=.1
   end
   lifecycle()
   if role=="match"then payOuts();sync()end
  end,debug.traceback)
  if not ok then
   accumulator=0;net.force=true;stats.errors=(stats.errors or 0)+1
   if clock-lastStepWarning>=5 then lastStepWarning=clock;warn("[SeaBattle step] "..tostring(err))end
  end
 end
end)
-- Statistics for an outside service (off unless configured, see Backend).
Backend.start({stats=function()
 local s={role=role,steps=stats.steps,stepMs=stats.steps>0 and stats.stepTime/stats.steps*1000 or 0,stepMaxMs=stats.stepMax*1000,
  bytes=stats.bytes,players=#Players:GetPlayers(),humans=gameState:humanCount(),phase=gameState.phase}
 stats={steps=0,stepTime=0,stepMax=0,bytes=0,messages=0}
 return s
end,lobby=function()
 return {role=role,phase=gameState.phase,humans=gameState:humanCount(),maxHumans=R.MaxHumans,players=#Players:GetPlayers(),jobId=game.JobId}
end})
shared:SetAttribute("WorldVersion",data.version)
shared:SetAttribute("WaterCells",data.stats.waterCells)
shared:SetAttribute("Sectors",#grid.regions)
shared:SetAttribute("Ready",true)
print(string.format("[SeaBattle] Atlas ready: %dx%d, %d water sectors, %d basins (%s server)",
	grid.width,grid.height,#grid.regions,#grid.basins,role))
