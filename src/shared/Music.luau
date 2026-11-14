--!nonstrict
-- Background music (2026-11-12, by the author's request): moods, a shuffled
-- playlist without repeats, crossfades; the tracks are in shared/Soundtrack.
--  * The client says which mood fits now (M:setMood): title, wait, calm, war, victory, defeat.
--  * Within a mood the tracks are shuffled, never one of the last few again (at most half the mood). The
--    title's first track plays first, once per session.
--  * A track plays whole; the next one fades in over its last OVERLAP seconds. A new mood crossfades over
--    MOOD_FADE (WAR_FADE into a battle); from war back to calm the battle track is let finish.
--  * Victory and defeat wait for the result sting (shared/Sfx win / lose) and play once; then the lobby's
--    or the match's mood takes over again.
--  * Switched off (M:setEnabled false): faded out and paused, so it goes on where it stopped.
local SoundService=game:GetService("SoundService")
local Soundtrack=require(script.Parent.Soundtrack)

local M={};M.__index=M
local OVERLAP=2
local MOOD_FADE=3
local WAR_FADE=2
local TOGGLE_FADE=.6
local HISTORY=6
local STING_WAIT=6      -- seconds the win / lose sting has before the result music starts
local LEVEL=.32         -- the music group's volume: under the sound effects
local ONCE={victory=true,defeat=true}

function M.new()
 local self=setmetatable({mood=nil,want='title',enabled=true,level=1,history={},firstDone=false,players={},clock=0},M)
 self.group=Instance.new("SoundGroup");self.group.Name="Music";self.group.Volume=LEVEL;self.group.Parent=SoundService
 for i=1,2 do
  local s=Instance.new("Sound");s.Name="Music"..i;s.Looped=false;s.Volume=0;s.SoundGroup=self.group;s.Parent=self.group
  local p={sound=s,target=0,speed=1,key=nil,ended=false}
  s.Ended:Connect(function()p.ended=true end)
  self.players[i]=p
 end
 return self
end
-- The next track of a mood: shuffled, none of the recent ones (the title's first track comes first).
function M:pick(mood)
 local list=Soundtrack.moods[mood]or Soundtrack.moods.calm
 if mood=='title'and not self.firstDone then self.firstDone=true;return list[1]end
 local recent=self.history[mood]or {};self.history[mood]=recent
 local keep=math.min(HISTORY,math.floor(#list/2))
 local choices={}
 for _,t in ipairs(list)do if not table.find(recent,t[1])then table.insert(choices,t)end end
 if #choices==0 then choices=list end
 local t=choices[math.random(1,#choices)]
 table.insert(recent,t[1]);while #recent>keep do table.remove(recent,1)end
 return t
end
-- Start a track on the free player, fading in over `fade`; the other one fades out over the same time.
function M:play(track,fade,mood)
 local cur=self.current
 local nxt=self.players[1]==cur and self.players[2]or self.players[1]
 if cur then cur.target=0;cur.speed=1/math.max(.05,fade)end
 nxt.sound:Stop();nxt.sound.SoundId="rbxassetid://"..track[1];nxt.sound.TimePosition=0;nxt.sound.Volume=0
 nxt.key=track[1];nxt.mood=mood;nxt.target=1;nxt.ended=false;nxt.speed=1/math.max(.05,fade)
 if self.enabled then nxt.sound:Play()end
 self.current=nxt;self.mood=mood
end
-- What fits now. (A once-only mood, once finished, is not asked for again until the mood changes.)
function M:setMood(mood)
 if mood==self.want then return end
 self.want=mood;self.onceDone=nil
 if ONCE[mood]then self.wantAt=self.clock+STING_WAIT end
end
function M:setEnabled(on)
 on=on~=false
 if on==self.enabled then return end
 self.enabled=on
 if on then
  for _,p in ipairs(self.players)do if p.target>0 then p.sound:Resume()end end
 end
end
function M:toggle()self:setEnabled(not self.enabled);return self.enabled end
-- Every frame.
function M:update(dt)
 self.clock+=dt
 -- the whole group fades for the on / off switch
 self.level=math.clamp(self.level+(self.enabled and 1 or -1)*dt/TOGGLE_FADE,0,1)
 self.group.Volume=LEVEL*self.level
 if not self.enabled then
  if self.level<=0 then for _,p in ipairs(self.players)do if p.sound.IsPlaying then p.sound:Pause()end end end
  return
 end
 for _,p in ipairs(self.players)do
  local v=p.sound.Volume
  if v~=p.target then
   v=p.target>v and math.min(p.target,v+p.speed*dt)or math.max(p.target,v-p.speed*dt)
   p.sound.Volume=v
   if v<=0 and p.target<=0 then p.sound:Stop()end
  end
 end
 local want=self.want
 if ONCE[want]and self.onceDone then want=self.after or 'calm'end
 if ONCE[want]and self.clock<(self.wantAt or 0)then
  -- the result sting first: the music steps aside
  if self.current and self.current.target>0 then self.current.target=0;self.current.speed=1/MOOD_FADE end
  return
 end
 local cur=self.current
 if not cur or not cur.key or(cur.target<=0 and not ONCE[want])then
  self:play(self:pick(want),cur and MOOD_FADE or 1.5,want)
  return
 end
 if cur.target<=0 then self:play(self:pick(want),1,want);return end
 if want~=self.mood then
  -- from a battle back to peace the battle track is let finish; any other change crossfades now
  if not(self.mood=='war'and want=='calm')then
   self:play(self:pick(want),want=='war'and WAR_FADE or MOOD_FADE,want)
   return
  end
 end
 local s=cur.sound
 if cur.ended or(s.TimeLength>0 and s.TimePosition>=s.TimeLength-OVERLAP)then
  if ONCE[self.mood]then
   -- played once: back to what the screen shows
   self.onceDone=true
   self:play(self:pick(self.after or 'calm'),OVERLAP,self.after or 'calm')
  else
   self:play(self:pick(want),OVERLAP,want)
  end
 end
end
-- The mood a once-only track gives way to (the lobby's title, or calm).
function M:setAfter(mood)self.after=mood end
return M
