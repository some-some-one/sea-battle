--!nonstrict
-- Parties (2026-11-14, by the author's request): friends play online together. No separate game for
-- them: the party's leader searches as usual and the whole party goes into the same match.
--  * A party lives on one lobby server: up to R.PartySize people, one of them the leader.
--  * Getting there: Roblox friends on this server, and those in the game on another lobby server (the
--    client's GetFriendsOnline list), are called from the party panel: the invite goes over
--    MessagingService to whatever server they are on, and accepting it moves them to the inviter's server.
--    Roblox's own invite (it lands in the Roblox notifications, not in the game) carries
--    "party:<inviter's UserId>" as launch data; the friend who arrives joins that party by itself, moved
--    to the inviter's lobby server if Roblox put them on another.
--  * After a match the members come back to the lobby one by one, maybe on different servers: whoever
--    finds no party mate on theirs moves to the lobby server a mate is on (the larger UserId first); a
--    mate still in the match is waited for (only servers in the lobby registry are teleported to).
--  * Only the leader searches (Matchmaker.join with the whole party: one queue entry, one teleport).
--    Anyone joining or leaving cancels a search under way; the leader just searches again.
--  * The party travels in the teleport data: the match server keeps it and hands it back on the way to
--    the lobby, where the party forms again as its members arrive.
-- The client gets its view of it (members, the invite waiting for it, friends to call) on the "Party"
-- remote after every change.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TeleportService=game:GetService("TeleportService")
local MessagingService=game:GetService("MessagingService")
local MemoryStoreService=game:GetService("MemoryStoreService")
local R=require(game:GetService("ReplicatedStorage").SeaBattle.NavalRules)

local P={}
local MAX=R.PartySize
local INVITE_TTL=60       -- seconds an invite waits for an answer
local INVITE_GAP=4        -- seconds between two invites to the same person
local parties={}          -- [id] = {id = string, leader = Player, members = {Player}}
local of={}               -- [Player] = party
local tags={}             -- [Player] = {id, leader = UserId, users = {UserId}} from the teleport data
local invites={}          -- [Player target] = {u = UserId, name, at = os.clock(), job = JobId (from another server)}
local away={}             -- [Player] = {{u, name}} friends in the game on other servers (the client's list)
local TOPIC="SeaBattleParty"
local lastInvite={}       -- ["from:to"] = os.clock()
local friends={}          -- ["a:b"] = bool (Roblox friendship, asked once)
local event,hooks
local counter=0

local function lobbyServer()return game.PrivateServerId==""end
-- Lobby servers note themselves in MemoryStore (refreshed every 45 s, gone 2 min after the server):
-- a teleport by JobId goes only to one of them, never to a match's reserved server (Roblox error 773).
local LOBBY_TTL=120
local lobbyMap
local function lobbies()
 if not lobbyMap then local ok,m=pcall(MemoryStoreService.GetSortedMap,MemoryStoreService,"SeaBattleLobbies");if ok then lobbyMap=m end end
 return lobbyMap
end
local function isLobby(jobId)
 local m=lobbies()
 if not m or type(jobId)~='string'then return false end
 local ok,v=pcall(m.GetAsync,m,jobId)
 return ok and v~=nil
end
local function noteLobby()
 local m=lobbies()
 while m do
  pcall(m.SetAsync,m,game.JobId,1,LOBBY_TTL)
  task.wait(45)
 end
end
local function newId()counter+=1;return string.sub(game.JobId,1,8)..":"..counter..":"..os.time()end
-- Pure, for tests: the members once `leaving` has gone; the leader stays unless it is them (then the next).
function P.without(members,leader,leaving)
 local rest={};for _,m in ipairs(members)do if m~=leaving then table.insert(rest,m)end end
 local nextLeader=leader
 if leader==leaving then nextLeader=rest[1]end
 return rest,nextLeader
end
function P.isFriendsId(a,userId)
 if a.UserId==userId then return false end
 -- (Studio's test players are nobody's friends: there everyone counts as one)
 if RunService:IsStudio()then return true end
 local k=math.min(a.UserId,userId)..":"..math.max(a.UserId,userId)
 if friends[k]==nil then
  local ok,yes=pcall(a.IsFriendsWith,a,userId)
  if not ok then return false end
  friends[k]=yes==true
 end
 return friends[k]
end
function P.isFriends(a,b)return P.isFriendsId(a,b.UserId)end
-- The party's people (just the player when there is none), the leader first.
function P.members(player)
 local party=of[player]
 if not party then return {player}end
 local list={party.leader}
 for _,m in ipairs(party.members)do if m~=party.leader then table.insert(list,m)end end
 return list
end
function P.isLeader(player)local party=of[player];return party==nil or party.leader==player end
function P.partyOf(player)return of[player]end

-- ---------------------------------------------------------------- views
local function live(inv)return inv and os.clock()-inv.at<INVITE_TTL and(inv.job~=nil or Players:GetPlayerByUserId(inv.u)~=nil)end
local function view(player)
 local party=of[player]
 local v={max=MAX,members={},friends={},leader=P.isLeader(player)}
 for _,m in ipairs(P.members(player))do
  table.insert(v.members,{u=m.UserId,name=m.DisplayName,leader=party~=nil and m==party.leader,me=m==player})
 end
 local inv=invites[player]
 if live(inv)then v.invite={u=inv.u,name=inv.name}end
 -- Friends on this server who are not in the party (Roblox friends only, so nobody gets called by strangers).
 for _,other in ipairs(Players:GetPlayers())do
  if other~=player and(party==nil or of[other]~=party)and P.isFriends(player,other)then
   local pending=invites[other]and invites[other].u==player.UserId and os.clock()-invites[other].at<INVITE_TTL
   table.insert(v.friends,{u=other.UserId,name=other.DisplayName,invited=pending==true,busy=of[other]~=nil})
  end
 end
 table.sort(v.friends,function(a,b)return a.name<b.name end)
 -- Friends in the game on other lobby servers (not when they are here or already in the party).
 v.away={}
 for _,f in ipairs(away[player]or {})do
  if not Players:GetPlayerByUserId(f.u)then
   local k=player.UserId..":"..f.u
   table.insert(v.away,{u=f.u,name=f.name,invited=lastInvite[k]~=nil and os.clock()-lastInvite[k]<INVITE_TTL})
  end
 end
 return v
end
function P.pushAll()
 if not event then return end
 for _,p in ipairs(Players:GetPlayers())do
  local ok,v=pcall(view,p)
  if ok then event:FireClient(p,v)end
 end
end
local function cancelSearch(party)
 if party and hooks and hooks.cancel then hooks.cancel(party.leader)end
end

-- ---------------------------------------------------------------- changes
local function join(player,party)
 if of[player]==party then return true end
 if #party.members>=MAX then return false,'party_full'end
 if of[player]then P.leave(player,true)end
 -- (a search under way is for the people it was made for)
 if hooks and hooks.cancel then hooks.cancel(player)end
 cancelSearch(party)
 table.insert(party.members,player);of[player]=party
 return true
end
local function create(leader)
 local party={id=newId(),leader=leader,members={leader}}
 parties[party.id]=party;of[leader]=party
 return party
end
function P.leave(player,quiet)
 local party=of[player]
 if not party then return end
 cancelSearch(party)
 local rest,leader=P.without(party.members,party.leader,player)
 of[player]=nil
 party.members=rest;party.leader=leader
 -- One person left is no party.
 if #rest<=1 then
  for _,m in ipairs(rest)do of[m]=nil end
  parties[party.id]=nil
 end
 if not quiet then P.pushAll()end
end
-- One player calls another (a Roblox friend on this server) into their party.
-- A friend on another server gets it over MessagingService (the server they are on shows it).
function P.invite(from,userId)
 userId=tonumber(userId)or 0
 local target=Players:GetPlayerByUserId(userId)
 if userId<=0 or userId==from.UserId then return false,'invalid'end
 if not target and not lobbyServer()then return false,'invalid'end
 if not P.isFriendsId(from,userId)then return false,'not_friends'end
 local party=of[from]
 if party and target and of[target]==party then return false,'already'end
 if party and #party.members>=MAX then return false,'party_full'end
 local k=from.UserId..":"..userId
 if lastInvite[k]and os.clock()-lastInvite[k]<INVITE_GAP then return false,'slow_down'end
 if target then
  lastInvite[k]=os.clock()
  invites[target]={u=from.UserId,name=from.DisplayName,at=os.clock()}
 else
  -- (sent in the background: the reply does not wait on MessagingService; a failed send shows "Invite" again)
  lastInvite[k]=os.clock()
  task.spawn(function()
   local ok=pcall(MessagingService.PublishAsync,MessagingService,TOPIC,{kind='invite',to=userId,from=from.UserId,name=from.DisplayName,job=game.JobId})
   if not ok then lastInvite[k]=nil;P.pushAll()end
  end)
 end
 P.pushAll()
 return true
end
local function onMessage(msg)
 local d=type(msg)=='table'and msg.Data
 if type(d)~='table'or d.kind~='invite'or d.job==game.JobId or not lobbyServer()then return end
 local target=Players:GetPlayerByUserId(tonumber(d.to)or 0)
 if not target or type(d.job)~='string'or not tonumber(d.from)then return end
 invites[target]={u=tonumber(d.from),name=tostring(d.name or'Friend'):sub(1,40),at=os.clock(),job=d.job}
 P.pushAll()
end
function P.accept(player,userId)
 local inv=invites[player]
 invites[player]=nil
 if not live(inv)or inv.u~=tonumber(userId)then P.pushAll();return false,'expired'end
 local from=Players:GetPlayerByUserId(inv.u)
 if not from then
  -- The inviter is on another lobby server: over there, into their party (followInvite on arrival).
  if of[player]then P.leave(player)end
  if hooks and hooks.cancel then hooks.cancel(player)end
  local options=Instance.new("TeleportOptions");options.ServerInstanceId=inv.job
  options:SetTeleportData({partyWith=inv.u})
  local ok=pcall(TeleportService.TeleportAsync,TeleportService,game.PlaceId,{player},options)
  P.pushAll()
  return ok,ok and 'moving'or'expired'
 end
 inv.from=from
 local party=of[inv.from]or create(inv.from)
 local ok,reason=join(player,party)
 if not ok and #party.members<=1 then of[inv.from]=nil;parties[party.id]=nil end
 P.pushAll()
 return ok,reason
end
function P.decline(player)invites[player]=nil;P.pushAll();return true end
function P.kick(leader,userId)
 local party=of[leader]
 local target=Players:GetPlayerByUserId(tonumber(userId)or 0)
 if not party or party.leader~=leader or not target or of[target]~=party or target==leader then return false,'invalid'end
 P.leave(target)
 return true
end

-- ---------------------------------------------------------------- arrivals
-- From the teleport data: back from a match, the party forms again once two of its people are here.
local function mateHere(player,tag)
 for _,u in ipairs(tag.users)do
  local other=Players:GetPlayerByUserId(u)
  if other and other~=player then return true end
 end
 return false
end
-- No mate on this server: go to the lobby server one of them is on. The larger UserId moves at once,
-- the smaller waits a little (so two who come back together do not swap servers), and both look again
-- later for a mate still in the match. A mate's server that is a match (reserved) refuses the teleport.
local function regroup(player,tag)
 local mates={}
 for _,u in ipairs(tag.users)do if u~=player.UserId then table.insert(mates,u)end end
 local larger=true
 for _,u in ipairs(mates)do if u>player.UserId then larger=false end end
 for _,delay in ipairs(larger and {2,15,40} or {10,25,50})do
  task.wait(delay)
  if not player.Parent or tags[player]~=tag or of[player]or mateHere(player,tag)then return end
  for _,u in ipairs(mates)do
   local ok,_,_,placeId,jobId=pcall(TeleportService.GetPlayerPlaceInstanceAsync,TeleportService,u)
   if ok and placeId==game.PlaceId and type(jobId)=='string'and jobId~=game.JobId and isLobby(jobId)then
    local options=Instance.new("TeleportOptions");options.ServerInstanceId=jobId
    options:SetTeleportData({parties={tag}})
    pcall(TeleportService.TeleportAsync,TeleportService,game.PlaceId,{player},options)
    break
   end
  end
 end
end
local function restore(player,tag)
 tags[player]=tag
 if RunService:IsStudio()or not lobbyServer()then return end
 for other,t in pairs(tags)do
  if other~=player and other.Parent and t.id==tag.id then
   local party=of[other]
   if not party then party=create(other);party.id=tag.id end
   join(player,party)
   if tag.leader==player.UserId then party.leader=player end
   return
  end
 end
 task.spawn(regroup,player,tag)
end
-- From an invite's launch data: join the inviter's party, or go to the server they are on.
local function followInvite(player,inviterId)
 local inviter=Players:GetPlayerByUserId(inviterId)
 if inviter then
  if not P.isFriends(player,inviter)then return end
  local party=of[inviter]or create(inviter)
  local ok=join(player,party)
  if not ok and #party.members<=1 then of[inviter]=nil;parties[party.id]=nil end
  return
 end
 if RunService:IsStudio()or game.PrivateServerId~=""then return end
 -- Roblox put them on another lobby server: over to the inviter's, if it is one of ours.
 local ok,_,err,placeId,jobId=pcall(TeleportService.GetPlayerPlaceInstanceAsync,TeleportService,inviterId)
 if ok and placeId==game.PlaceId and jobId and jobId~=game.JobId and isLobby(jobId)then
  local options=Instance.new("TeleportOptions");options.ServerInstanceId=jobId
  options:SetTeleportData({partyWith=inviterId})
  pcall(TeleportService.TeleportAsync,TeleportService,game.PlaceId,{player},options)
 end
end
local function arrived(player)
 local okJoin,join=pcall(function()return player:GetJoinData()end)
 if not okJoin or type(join)~='table'then return end
 local td=type(join.TeleportData)=='table'and join.TeleportData or nil
 if td and type(td.parties)=='table'then
  for _,tag in ipairs(td.parties)do
   if type(tag)=='table'and type(tag.users)=='table'and table.find(tag.users,player.UserId)then restore(player,tag);break end
  end
 end
 local inviter=td and tonumber(td.partyWith)
 if not inviter and type(join.LaunchData)=='string'then inviter=tonumber(string.match(join.LaunchData,"^party:(%d+)$"))end
 if inviter and inviter~=player.UserId and game.PrivateServerId==""then followInvite(player,inviter)end
end
-- For the teleport data: the parties of these players (live on a lobby server, as they came on a match server).
function P.tagsFor(players)
 local list,seen={},{}
 for _,p in ipairs(players)do
  local party=of[p]
  if party and not seen[party.id]then
   seen[party.id]=true
   local users={};for _,m in ipairs(party.members)do table.insert(users,m.UserId)end
   table.insert(list,{id=party.id,leader=party.leader.UserId,users=users})
  elseif not party and tags[p]and not seen[tags[p].id]then
   seen[tags[p].id]=true;table.insert(list,tags[p])
  end
 end
 return list
end

-- ---------------------------------------------------------------- the client's commands
-- The client's GetFriendsOnline list (friends in this game, on other servers): kept for the view.
local function setAway(player,list)
 local clean={}
 if type(list)=='table'then
  for _,f in ipairs(list)do
   if #clean>=30 then break end
   local u=type(f)=='table'and tonumber(f.u)
   if u and u>0 and u~=player.UserId then table.insert(clean,{u=u,name=tostring(f.name or u):sub(1,40)})end
  end
 end
 table.sort(clean,function(a,b)return a.name<b.name end)
 away[player]=clean
end
function P.command(player,value)
 if type(value)~='table'then return {ok=false,reason='invalid'}end
 local op=value.op
 local ok,reason
 if op=='view'then P.pushAll();return {ok=true}
 elseif op=='online'then setAway(player,value.list);P.pushAll();return {ok=true}
 elseif op=='invite'then ok,reason=P.invite(player,value.user)
 elseif op=='accept'then ok,reason=P.accept(player,value.user)
 elseif op=='decline'then ok,reason=P.decline(player)
 elseif op=='leave'then P.leave(player);ok=true
 elseif op=='kick'then ok,reason=P.kick(player,value.user)
 else return {ok=false,reason='invalid'}end
 return {ok=ok==true,reason=reason or 'party'}
end
-- hooks = {cancel = function(player)}: cancels the search of the player's party (Matchmaker.leave).
function P.start(remote,h)
 event=remote;hooks=h or {}
 if lobbyServer()then
  task.spawn(function()pcall(MessagingService.SubscribeAsync,MessagingService,TOPIC,onMessage)end)
  if not RunService:IsStudio()then task.spawn(noteLobby)end
 end
 Players.PlayerAdded:Connect(function(p)task.spawn(function()arrived(p);P.pushAll()end)end)
 for _,p in ipairs(Players:GetPlayers())do task.spawn(function()arrived(p);P.pushAll()end)end
 Players.PlayerRemoving:Connect(function(p)
  P.leave(p,true)
  invites[p]=nil;tags[p]=nil;away[p]=nil
  for target,inv in pairs(invites)do if inv.u==p.UserId and not inv.job then invites[target]=nil end end
  task.defer(P.pushAll)
 end)
end
return P
