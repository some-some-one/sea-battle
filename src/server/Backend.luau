--!nonstrict
-- Optional outside service: server statistics, a lobby list across
-- servers and match events. OFF by default — nothing leaves the server until `Config.Enabled` is set.
--
-- To turn it on:
--   1. Run a small HTTPS service that accepts JSON POSTs (any language): /v1/stats, /v1/lobby, /v1/event,
--      and answers /v1/lobbies with {lobbies = {...}}.
--   2. Creator Dashboard → the experience → Secrets: add a secret named Config.SecretName (a long random
--      token) with the service's domain allowed; the service checks `Authorization: Bearer <token>`.
--   3. Game Settings → Security: allow HTTP requests.
--   4. Set Enabled = true and BaseUrl below, rebuild, publish.
-- Every request carries the server's JobId and PlaceVersion. Failures are counted and never stop the game;
-- after FailLimit failures in a row the service is left alone for RetryAfter seconds.
local HttpService=game:GetService("HttpService")
local RunService=game:GetService("RunService")

local Config={
 Enabled=false,
 BaseUrl="https://example.invalid", -- the service, e.g. "https://lobbies.your-domain.com"
 SecretName="sea_battle_backend",
 StatsEvery=60,   -- seconds between server statistics
 LobbyEvery=5,    -- seconds between lobby updates (players, phase, countdown)
 FailLimit=5,
 RetryAfter=120,
}

local B={Config=Config}
local fails,pausedUntil=0,0
local queue={}

local function ready()
 return Config.Enabled and not RunService:IsStudio()and os.clock()>=pausedUntil
end
local function post(path,body)
 if not ready()then return nil end
 local headers={["Content-Type"]="application/json"}
 local okSecret,secret=pcall(HttpService.GetSecret,HttpService,Config.SecretName)
 if okSecret then headers.Authorization=secret:AddPrefix("Bearer ")end
 body.jobId=game.JobId;body.placeVersion=game.PlaceVersion;body.time=os.time()
 local ok,res=pcall(HttpService.RequestAsync,HttpService,{Url=Config.BaseUrl..path,Method="POST",Headers=headers,Body=HttpService:JSONEncode(body)})
 if ok and res.Success then fails=0
  local okJson,decoded=pcall(HttpService.JSONDecode,HttpService,res.Body)
  return okJson and decoded or {}
 end
 fails+=1
 if fails>=Config.FailLimit then fails=0;pausedUntil=os.clock()+Config.RetryAfter;warn("[Backend] service unreachable, paused")end
 return nil
end
-- A match event (start, end, ...); sent in the background, dropped when the service is off.
function B.event(name,fields)
 if not Config.Enabled then return end
 table.insert(queue,{name=name,fields=fields or {}})
end
-- Lobbies of all servers, as the service lists them (nil when the service is off or unreachable).
function B.listLobbies()
 local reply=post("/v1/lobbies",{})
 return reply and reply.lobbies
end
-- providers = {stats = fn() -> table, lobby = fn() -> table}: what this server reports.
function B.start(providers)
 if not Config.Enabled then return end
 -- Frame rate of the server itself (slow frames are what players feel as lag).
 local frames,frameTime,slow=0,0,0
 RunService.Heartbeat:Connect(function(dt)frames+=1;frameTime+=dt;if dt>=.1 then slow+=1 end end)
 task.spawn(function()
  local sinceStats,sinceLobby=0,0
  while true do
   task.wait(1);sinceStats+=1;sinceLobby+=1
   while #queue>0 do local e=table.remove(queue,1);post("/v1/event",{event=e.name,fields=e.fields})end
   if sinceLobby>=Config.LobbyEvery and providers.lobby then sinceLobby=0;post("/v1/lobby",providers.lobby())end
   if sinceStats>=Config.StatsEvery and providers.stats then
    local s=providers.stats();s.seconds=sinceStats;s.fps=frameTime>0 and frames/frameTime or 0;s.slowFrames=slow
    frames,frameTime,slow=0,0,0;sinceStats=0
    post("/v1/stats",s)
   end
  end
 end)
end
return B
