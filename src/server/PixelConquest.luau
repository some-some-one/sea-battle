--!nonstrict
-- The match simulation lives in ReplicatedStorage.SeaBattle.Sim: the server runs the real match with it,
-- and every client runs its own bots-only match behind the lobby.
return require(game:GetService("ReplicatedStorage"):WaitForChild("SeaBattle"):WaitForChild("Sim"):WaitForChild("PixelConquest"))
