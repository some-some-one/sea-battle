--!nonstrict
-- Online matchmaking across all servers of the game, without an outside service (public matches, with
-- Roblox's MemoryStoreService in place of a lobby service):
--
--  * A hub (any public server: lobby, solo) puts a player who pressed "Online" into one queue shared by
--    every server (sorted map QUEUE, key = UserId, sorted by the time they joined it).
--  * One hub at a time is the leader (a short lease in LOCK). Every LEADER_EVERY seconds it looks at the
--    queue: R.MaxHumans people waiting, or the first one waiting R.QueueWait seconds, make a match. It
--    reserves a server (TeleportService:ReserveServer), writes the match (MATCHES, by private server id:
--    who is in it, when it starts) and an assignment for every player (ASSIGN), and takes them off the queue.
--  * Each hub watches the assignments of its own queued players and teleports them, in one group per
--    match, to the reserved server. The match starts there for everyone at once (SeaBattle.server).
-- Queue entries expire unless their hub refreshes them, so a crashed hub leaves no ghosts.
-- A party (server/Party, 2026-11-14) is one entry: key = its leader, `users` = everyone in it. A match takes
-- whole entries only, so a party always lands in one match; the party rides along in the teleport data.
--
-- In Studio there are no teleports: the queue is local to this server, and the match starts here
-- (`onLocalMatch`) — enough to test the whole flow with one client.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TeleportService=game:GetService("TeleportService")
local MemoryStoreService=game:GetService("MemoryStoreService")
local R=require(game:GetService("ReplicatedStorage").SeaBattle.NavalRules)

local MM={}
local QUEUE,LOCK,MATCHES,ASSIGN="SB_Queue_v1","SB_Lock_v1","SB_Matches_v1","SB_Assign_v1"
local ENTRY_TTL=30     -- a queue entry lives this long without a refresh
local REFRESH_EVERY=10
local LEADER_EVERY=2
local LEASE=8
MM.STUDIO_WAIT=5       -- Studio: seconds in the queue before the local match starts

local queued={}        -- [player] = the group's entry {key, players, since, refreshed}: shared by a party
local teleporting={}   -- [player] = true
local status           -- RemoteEvent: per-player queue status
local store={}
local function now()return os.time()end
local function key(player)return tostring(player.UserId)end
local function size(e)return type(e.users)=='table'and #e.users or 1 end

-- A plan for the leader: which waiting entries make a match now. Entries are sorted by `since`; an entry
-- is one player or one party (`users`). Pure, for tests: matches of at most `max` people, whole entries
-- only (in order; one that does not fit waits for the next match); a match forms when full, or when its
-- first entry has waited `wait` seconds (then everyone who fits goes).
function MM.plan(entries,t,max,wait)
 local groups={};local rest=entries
 while #rest>0 do
  local g,n,left={},0,{}
  for _,e in ipairs(rest)do
   local k=size(e)
   if n+k<=max then table.insert(g,e);n+=k else table.insert(left,e)end
  end
  if n>=max or t-rest[1].since>=wait then table.insert(groups,g);rest=left else break end
 end
 return groups
end

local function send(player,s)if status and player.Parent then status:FireClient(player,s)end end
function MM.isQueued(player)return queued[player]~=nil end

-- ---------------------------------------------------------------- live (MemoryStore + teleports)
local function maps()
 store.queue=store.queue or MemoryStoreService:GetSortedMap(QUEUE)
 store.lock=store.lock or MemoryStoreService:GetSortedMap(LOCK)
 store.matches=store.matches or MemoryStoreService:GetSortedMap(MATCHES)
 store.assign=store.assign or MemoryStoreService:GetSortedMap(ASSIGN)
 return store
end
local function writeEntry(q)
 local s=maps()
 local users={};for _,p in ipairs(q.players)do table.insert(users,p.UserId)end
 return pcall(s.queue.SetAsync,s.queue,q.key,{u=q.players[1].UserId,users=users,job=game.JobId,since=q.since},ENTRY_TTL,q.since)
end
-- The leader's turn: claim or renew the lease, then form matches.
local function lead()
 local s=maps();local t=now()
 local ok,lease=pcall(s.lock.UpdateAsync,s.lock,"leader",function(old)
  if old==nil or old.job==game.JobId or (old.untilTime or 0)<t then return {job=game.JobId,untilTime=t+LEASE}end
  return nil
 end,LEASE*2)
 if not ok or not lease or lease.job~=game.JobId then return end
 local okRange,items=pcall(s.queue.GetRangeAsync,s.queue,Enum.SortDirection.Ascending,200)
 if not okRange then return end
 local entries={};for _,item in ipairs(items)do if type(item.value)=='table'then table.insert(entries,item.value)end end
 table.sort(entries,function(a,b)return a.since<b.since end)
 local people=0;for _,e in ipairs(entries)do people+=size(e)end
 pcall(s.lock.SetAsync,s.lock,"stats",{queued=people,time=t},30)
 for _,group in ipairs(MM.plan(entries,t,R.MaxHumans,R.QueueWait))do
  local okReserve,code,psid=pcall(TeleportService.ReserveServer,TeleportService,game.PlaceId)
  if not okReserve then warn("[Matchmaker] ReserveServer: "..tostring(code));return end
  local users={};for _,e in ipairs(group)do for _,u in ipairs(e.users or {e.u})do table.insert(users,u)end end
  local startsAt=t+R.TeleportLead
  pcall(s.matches.SetAsync,s.matches,psid,{users=users,startsAt=startsAt},3600)
  for _,e in ipairs(group)do
   for _,u in ipairs(e.users or {e.u})do
    pcall(s.assign.SetAsync,s.assign,tostring(u),{code=code,psid=psid,startsAt=startsAt},120)
   end
   pcall(s.queue.RemoveAsync,s.queue,tostring(e.u))
  end
 end
end
-- This hub's own players: refresh their entries, pick up assignments, teleport.
local function serve()
 local s=maps();local t=now()
 local groups={}
 for player,q in pairs(queued)do
  if not player.Parent then queued[player]=nil;continue end
  -- (one refresh per entry: a party's members share theirs)
  if t-q.refreshed>=REFRESH_EVERY then q.refreshed=t;writeEntry(q)end
  local ok,a=pcall(s.assign.GetAsync,s.assign,key(player))
  if ok and a then
   groups[a.code]=groups[a.code]or {info=a,players={}}
   table.insert(groups[a.code].players,player)
  else
   send(player,{state='queued',waited=t-q.since,queued=q.count})
  end
 end
 for _,g in pairs(groups)do
  local options=Instance.new("TeleportOptions")
  options.ReservedServerAccessCode=g.info.code
  options:SetTeleportData({psid=g.info.psid,startsAt=g.info.startsAt,parties=MM.hooks.parties and MM.hooks.parties(g.players)or nil})
  for _,p in ipairs(g.players)do queued[p]=nil;teleporting[p]=true;send(p,{state='teleporting'})
   pcall(s.assign.RemoveAsync,s.assign,key(p))end
  local ok,err=pcall(TeleportService.TeleportAsync,TeleportService,game.PlaceId,g.players,options)
  if not ok then
   warn("[Matchmaker] teleport: "..tostring(err))
   for _,p in ipairs(g.players)do teleporting[p]=nil;send(p,{state='failed',reason='teleport'})end
  end
 end
 local okStats,st=pcall(s.lock.GetAsync,s.lock,"stats")
 if okStats and st then for _,q in pairs(queued)do q.count=st.queued end end
end

-- ---------------------------------------------------------------- public
-- hooks = {onLocalMatch = function(players)}: Studio only, the match starts on this server;
--         {parties = function(players)}: the parties of these players, for the teleport data.
function MM.start(remote,hooks)
 status=remote
 MM.hooks=hooks or {}
 if RunService:IsStudio()then
  task.spawn(function()
   while true do
    task.wait(1)
    local ready,list=false,{}
    for player,q in pairs(queued)do
     if not player.Parent then queued[player]=nil;continue end
     table.insert(list,player)
     send(player,{state='queued',waited=now()-q.since,queued=#list,studio=true})
     if now()-q.since>=MM.STUDIO_WAIT then ready=true end
    end
    if ready and #list>0 then
     for _,p in ipairs(list)do queued[p]=nil;send(p,{state='teleporting'})end
     if MM.hooks.onLocalMatch then MM.hooks.onLocalMatch(list)end
    end
   end
  end)
  return
 end
 task.spawn(function()
  local sinceLead=0
  while true do
   task.wait(1);sinceLead+=1
   if sinceLead>=LEADER_EVERY then sinceLead=0;pcall(lead)end
   if next(queued)then pcall(serve)end
  end
 end)
 TeleportService.TeleportInitFailed:Connect(function(player,result,message)
  if teleporting[player]then teleporting[player]=nil;send(player,{state='failed',reason='teleport',message=tostring(message)})end
 end)
end
-- `players`: one player, or a party with its leader first (server/Party.members): one entry for all.
function MM.join(players)
 if typeof(players)=='Instance'then players={players}end
 for _,p in ipairs(players)do if queued[p]or teleporting[p]then return true end end
 local t=now()
 local q={key=key(players[1]),players=players,since=t,refreshed=t}
 for _,p in ipairs(players)do queued[p]=q end
 if not RunService:IsStudio()then
  -- An assignment found now is from an earlier search (the leader formed that group just as the player
  -- cancelled): it would send them into a match already under way.
  local s=maps()
  for _,p in ipairs(players)do pcall(s.assign.RemoveAsync,s.assign,key(p))end
  local ok,err=writeEntry(q)
  if not ok then for _,p in ipairs(players)do queued[p]=nil end;warn("[Matchmaker] queue: "..tostring(err));return false,'queue_unavailable'end
 end
 for _,p in ipairs(players)do send(p,{state='queued',waited=0})end
 return true
end
-- Cancels the search of the player's whole entry (a party searches and stops together).
function MM.leave(player)
 local q=queued[player]
 if not q then return end
 for _,p in ipairs(q.players)do
  if queued[p]==q then queued[p]=nil;send(p,{state='idle'})end
 end
 if not RunService:IsStudio()then
  local s=maps();pcall(s.queue.RemoveAsync,s.queue,q.key)
  for _,p in ipairs(q.players)do pcall(s.assign.RemoveAsync,s.assign,key(p))end
 end
end
Players.PlayerRemoving:Connect(function(player)
 -- (someone leaving the game ends their entry's search; a party's others can search again)
 if queued[player]then MM.leave(player)end
 queued[player]=nil;teleporting[player]=nil
end)
-- On a match server: who is expected and when the match starts (os.time()), from the leader's record.
function MM.matchInfo()
 local s=maps()
 for attempt=1,10 do
  local ok,info=pcall(s.matches.GetAsync,s.matches,game.PrivateServerId)
  if ok and info then return info end
  task.wait(math.min(attempt,3))
 end
 return nil
end
-- Back to a public hub server (after the results, or when a player leaves the match). `again`: the player
-- asked for another match, so the hub's lobby searches at once (Lobby reads it from the join data).
function MM.toHub(players,again)
 if RunService:IsStudio()or #players==0 then return false end
 local options=Instance.new("TeleportOptions")
 options:SetTeleportData({again=again==true or nil,parties=MM.hooks and MM.hooks.parties and MM.hooks.parties(players)or nil})
 local ok,err=pcall(TeleportService.TeleportAsync,TeleportService,game.PlaceId,players,options)
 if not ok then warn("[Matchmaker] to hub: "..tostring(err))end
 return ok
end
function MM.isMatchServer()return game.PrivateServerId~=""and game.PrivateServerOwnerId==0 end
return MM
