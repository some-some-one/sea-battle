--!nonstrict
-- Nobody can talk in Sea Battle (2026-11-12, the author's decision): no text chat, no voice. The place
-- itself has no default chat channels, chat window, input bar or bubbles and no default voice
-- (tools/build_world.py); this is the server's own guarantee on top of that, whatever the experience's
-- Communication settings say:
--  * every text channel, now or later, delivers no message to anyone;
--  * any voice input (AudioDeviceInput) that appears under a player or anywhere in the game is removed.
-- (The camera only animates an avatar's face; the game shows no avatars, so it has nothing to do.)
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local M={}
local function silence(o)
 if o:IsA("TextChannel")then
  o.ShouldDeliverCallback=function()return false end
 elseif o:IsA("AudioDeviceInput")then
  task.defer(function()if o.Parent then o:Destroy()end end)
 end
end
function M.start()
 pcall(function()game:GetService("VoiceChatService").EnableDefaultVoice=false end)
 for _,o in ipairs(TextChatService:GetDescendants())do silence(o)end
 TextChatService.DescendantAdded:Connect(silence)
 for _,o in ipairs(game:GetDescendants())do if o:IsA("AudioDeviceInput")then silence(o)end end
 game.DescendantAdded:Connect(function(o)if o:IsA("AudioDeviceInput")then silence(o)end end)
end
return M
