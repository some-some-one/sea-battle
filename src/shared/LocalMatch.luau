--!nonstrict
-- A match the client runs itself, with the same simulation as the server (SeaBattle.Sim):
-- nothing goes over the network, so a server takes any number of solo players. One Game is kept
-- (building it takes a second and a lot of memory) and used in one of two roles:
--  * "demo" — the lobby's background: bots only (R.Demo: fewer bots, early first ports, few buildings
--    per bot), from the first second, fast while the countries grow and slower later (R.demoSpeed);
--    a new random match every R.DemoSeconds; the lobby camera follows `progress()`.
--  * "solo" — the player's own match against the bots, in real time, with the chosen difficulty.
-- Its messages go through the same view as a server match, so everything looks and behaves the same.
-- Each step is a Coop job resumed within a small time budget per frame (less on phones): a heavy step
-- (a big battle, a route search) is spread over frames instead of stalling one, a slow device slows the
-- match down instead of freezing, and units are drawn on `clock()`, the match time actually reached.
-- Messages, snapshots and the player's commands only happen between steps, never in the middle of one.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local shared=script.Parent
local R=require(shared.NavalRules)
local Coop=require(shared.Coop)
local Catalog=require(shared.Catalog)

local M={};M.__index=M
local STEP=.1

function M.new(view)
 local self=setmetatable({view=view,epoch=0,ready=false,failed=false,accumulator=0,sinceSync=0,kind='demo',step=0},M)
 local mobile=UIS.TouchEnabled and not UIS.KeyboardEnabled
 self.speedScale=1
 -- Frame time a step may take: a solo match (10 steps a second, rarely behind) gets more; the lobby's demo,
 -- always running behind at its fast speed, would otherwise take its whole share every frame and the
 -- lobby would stutter — it runs a little slower instead.
 self.soloBudget=mobile and .005 or .007
 -- A solo step that does not fit (several big attacks at once: hundreds of cells a step) may take a
 -- little more of the frame while it lasts, up to soloBudgetMax, instead of the match slowing down: a
 -- slowed match moved planes and ships in jerks (2026-11-16, iPhone 7). Back to soloBudget once it keeps up.
 self.soloBudgetMax=mobile and .008 or .010
 -- (a phone gets the same 4 ms as a computer since 2026-11-13: the demo plays at the same speed; before
 -- it had 2.5 ms and 60% of the speed)
 self.demoBudget=.004
 self.budget=self.demoBudget
 self.user=Players.LocalPlayer.UserId
 task.spawn(function()
  local ok,err=pcall(function()
   local Game=require(shared:WaitForChild("Sim"):WaitForChild("PixelConquest"))
   self.game=Game.new(view.grid)
   self:demo()
  end)
  if not ok then warn("[LocalMatch] "..tostring(err));self.failed=true end
 end)
 return self
end
-- The lobby's background: a fresh bots-only match from its first second.
function M:demo()
 self.job=nil;self.budget=self.demoBudget
 self.kind='demo';self.game:startDemo(math.random(1,1000000000),R.Demo)
 self:restartClock();self.ready=true
 if self.shown then task.spawn(self.push,self)end
end
-- The player's own match: the full map of bots, waiting for the player's coast.
function M:solo(difficulty)
 if not self.game then return false end
 self.job=nil
 local g=self.game
 g:reset(math.random(1,1000000000))
 g.settings.mode='solo';g.settings.difficulty=difficulty or 'normal'
 for _,f in ipairs(g.factions)do if f.bot then f.fleet=R.difficulty(g.settings.difficulty).start end end
 g.playerNames={[self.user]=Players.LocalPlayer.DisplayName}
 self.kind='solo';self.budget=self.soloBudget;self:restartClock();self.ready=true
 if self.shown then task.spawn(self.push,self)end
 return true
end
function M:restartClock()self.accumulator=0;self.sinceSync=0;self.rate=nil;self.step=0 end
-- Share of the demo played (0..1); the lobby camera pans with it.
function M:progress()return self.game and self.kind=='demo'and math.clamp(self.game.time/R.DemoSeconds,0,1)or 0 end
-- Match seconds per real second now.
function M:speed()
 if self.kind~='demo'then return 1 end
 return R.demoSpeed(self.game and self.game.time or 0)*self.speedScale
end
-- The match time being shown: the last step plus the part of the next one already due.
function M:clock()return self.game and self.game.time+self.accumulator or 0 end
function M:phase()
 -- The demo is shown as a lobby (no match interface); a solo match shows its real phase.
 return self.kind=='demo'and 'choosing'or self.game.phase
end
-- Wait until no step is half done (the job runs over frames).
function M:betweenSteps()while self.job do task.wait()end end
-- The whole state into the view (on show, after a new match, and when the view asks again).
function M:push()
 self:betweenSteps()
 local g=self.game
 self.epoch+=1;self.net=g:newNet();g.dirty={}
 local s=g:snapshot();s.epoch=self.epoch;s.phase=self:phase()
 self.view:receive({snapshot=s})
 self:sendPrivate(true)
end
function M:show()
 self.shown=true
 if self.ready then task.spawn(self.push,self)end
end
function M:hide()self.shown=false end
function M:sendPrivate(full)
 local g=self.game;local owner=self.kind=='solo'and g.clients[self.user]
 if owner then self.view:receive({epoch=self.epoch,private=g:privateState(owner,full)})end
end
-- A command of the solo player, answered at once like the server would ({ok, reason}).
function M:command(action,value)
 if self.kind~='solo'or not self.game then return {ok=false,reason='invalid'}end
 local g=self.game
 -- Never in the middle of a step: the step waits for the command, the command for the step.
 self.commandPending=(self.commandPending or 0)+1
 self:betweenSteps()
 local success,ok,reason=pcall(g.command,g,self.user,action,value)
 self.commandPending-=1
 if not success then warn("[LocalMatch command] "..tostring(ok));return {ok=false,reason='invalid'}end
 -- The player's country wears their flag and water pattern (the other countries of a solo match have none).
 if ok and action=='start'then
  local f=g.factions[g.clients[self.user]];local profile=self.view.profile
  if f and profile then
   f.flag=Catalog.worn(profile,'flag');f.pattern=Catalog.worn(profile,'pattern')
   -- (and has the arsenal they have opened)
   f.arsenal=Catalog.mask(profile.unlocks)
  end
 end
 if ok then
  local packet=g:changes();packet.shared=g:sharedState();packet.epoch=self.epoch;packet.phase=self:phase()
  self.view:receive(packet);self.net.force=true
 end
 return {ok=ok,reason=reason}
end
-- Solo: the player takes command of the country that defeated them (Game:takeover); the view gets the new
-- owner with the next message.
function M:takeover()
 if self.kind~='solo'or not self.game then return false end
 self:betweenSteps()
 local ok=self.game:takeover(self.user)
 if ok then self.net.force=true;task.spawn(self.push,self)end
 return ok==true
end
-- Called every frame while shown: a few match steps within the budget, then one message.
function M:update(dt)
 if not self.shown or not self.ready then return end
 local g=self.game
 if self.kind=='demo'and g.time>=R.DemoSeconds then
  local ok,err=pcall(self.demo,self)
  if not ok then warn("[LocalMatch] "..tostring(err));self.failed=true end
  return
 end
 -- An arsenal item opened during a solo match (the in-match shop): the country has it at once.
 if self.kind=='solo'and self.user then
  local id=g.clients[self.user];local f=id and g.factions[id];local profile=self.view.profile
  if f and profile then local mask=Catalog.mask(profile.unlocks);if f.arsenal~=mask then f.arsenal=mask end end
 end
 local before=self:clock()
 -- Paused (the pause menu of a solo match): the step in progress finishes, no new one starts.
 local paused=self.paused==true and self.kind=='solo'
 self.accumulator=math.min(self.accumulator+(paused and 0 or dt*self:speed()),STEP*3)
 self.sinceSync+=dt
 local began=os.clock()
 while true do
  if self.job then
   local left=self.budget-(os.clock()-began)
   if left<=0 or not self.job:step(left)then break end
   if not self.job.ok then warn("[LocalMatch] step: "..tostring(self.job.err))end
   self.job=nil
   -- A message right after a finished step: when the match runs behind, the next step starts at once
   -- and there is no other moment between steps — messages then came rarely and in bursts.
   self:sync()
  end
  if paused or self.accumulator<STEP or(self.commandPending or 0)>0 or os.clock()-began>=self.budget then break end
  self.accumulator-=STEP
  self.job=Coop.job(g.tick,g,STEP)
 end
 if not self.job then self:sync()end
 -- A device that cannot keep up drops the time it is behind instead of piling it up.
 if self.job and self.accumulator>STEP then self.accumulator=STEP*.99 end
 if self.kind=='solo'and not paused then
  local behind=self.job~=nil and self.accumulator>=STEP*.5
  self.budget=math.clamp(self.budget+(behind and .0005 or -.00025),self.soloBudget,self.soloBudgetMax)
 end
 if g.phase~='playing'then self.accumulator=0 end
 -- The speed actually reached: units are drawn this much match time behind the clock.
 local rate=math.max(0,self:clock()-before)/math.max(dt,1e-3)
 self.rate=(self.rate or rate)+(rate-(self.rate or rate))*math.min(1,dt*2)
 self.view.timeScale=math.max(1,self.rate)
end
-- One message to the view, ten a second at most, only between steps.
function M:sync()
 if self.sinceSync<.1 then return end
 self.sinceSync=0
 local g=self.game
 local packet,step,force=g:syncPacket(self.net)
 -- Unit positions in every message: nothing to save here, and the drawing stays smooth at any speed.
 packet.units=packet.units or g:packedUnits()
 packet.epoch=self.epoch;packet.phase=self:phase()
 self.view:receive(packet)
 if step%2==0 or force then self:sendPrivate(step%5==0 or force)end
end
return M
