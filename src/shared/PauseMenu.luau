--!nonstrict
-- The pause menu: one round button near the status panel opens a card with
--   Resume · Restart (solo) · Sounds on/off · Music on/off · Exit to lobby. (The help is the round "?" beside it.)
-- In a solo match the match itself stops while the card is open (LocalMatch.paused); an online match
-- goes on for everyone, so the card only says so. The sound switch is kept as the ScreenGui attribute
-- "SoundOn" (shared/Sfx); the music switch is the Atlas's (view.musicToggle / view.musicOn), the same as
-- its round note button and the M key.
local Theme=require(script.Parent.Theme)
local Icons=require(script.Parent.Icons)
local Anim=require(script.Parent.Anim)
local C={panel=Theme.colors.panel,button=Theme.colors.button,accent=Theme.colors.accent,text=Theme.colors.text,muted=Theme.colors.muted,
 danger=Color3.fromRGB(255,128,112),dark=Color3.fromRGB(10,30,30)}
local PM={};PM.__index=PM
local function make(class,parent,props)
 local o=Instance.new(class);o:SetAttribute("NoSkin",true)
 for k,v in pairs(props or {})do o[k]=v end
 o.Parent=parent;return o
end
local function corner(o,r)make("UICorner",o,{CornerRadius=UDim.new(0,r)});return o end
local function stroke(o,t)return make("UIStroke",o,{Color=Color3.new(1,1,1),Transparency=t,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
local function text(parent,value,size,weight,color,props)
 local o=make("TextLabel",parent,{BackgroundTransparency=1,Text=value,TextSize=size,FontFace=Theme.font(weight),TextColor3=color,
  TextXAlignment=Enum.TextXAlignment.Left,ZIndex=62})
 for k,v in pairs(props or {})do o[k]=v end
 return o
end
local ROW,GAP,WIDTH=50,8,300
-- A round button for Roblox's top bar line: the pause button, and the Atlas's "?" in the same style.
PM.SIZE=42
function PM.round(gui,name,icon)
 local b=make("TextButton",gui,{Name=name,Text="",AutoButtonColor=false,BackgroundColor3=C.panel,BackgroundTransparency=.12,
  Size=UDim2.fromOffset(PM.SIZE,PM.SIZE),BorderSizePixel=0,Visible=false,ZIndex=13})
 corner(b,PM.SIZE/2);stroke(b,.86)
 Icons.image(b,icon,18,C.text,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),ZIndex=14})
 Anim.button(b)
 return b
end
function PM.new(view)
 local self=setmetatable({v=view,open=false,rows={}},PM)
 local gui=view.gui
 if gui:GetAttribute("SoundOn")==nil then gui:SetAttribute("SoundOn",true)end
 -- The round button.
 self.button=PM.round(gui,"PauseButton","pause")
 self.button.Activated:Connect(function()self:show(true)end)
 -- A dim layer over the whole screen (it also keeps taps off the map) and the card in the middle.
 self.shade=make("TextButton",gui,{Name="PauseShade",Text="",AutoButtonColor=false,BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.45,
  BorderSizePixel=0,Size=UDim2.new(1,0,1,80),Position=UDim2.fromOffset(0,-80),Visible=false,ZIndex=60})
 self.shade.Activated:Connect(function()self:show(false)end)
 self.card=make("Frame",gui,{Name="PauseMenu",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(WIDTH,200),
  BackgroundColor3=C.panel,BackgroundTransparency=.04,BorderSizePixel=0,Visible=false,Active=true,ZIndex=61})
 corner(self.card,18);stroke(self.card,.84)
 self.scale=make("UIScale",self.card,{})
 self.title=text(self.card,"PAUSE",20,Enum.FontWeight.Heavy,C.text,{Position=UDim2.fromOffset(20,16),Size=UDim2.new(1,-40,0,26)})
 self.sub=text(self.card,"",12,Enum.FontWeight.Medium,C.muted,{Position=UDim2.fromOffset(20,42),Size=UDim2.new(1,-40,0,16)})
 self.resume=self:row("Resume","check","Resume",C.accent,C.dark,function()self:show(false)end)
 self.restart=self:row("Restart","restart","Restart",C.button,C.text,function()self:restartSolo()end)
 self.sound=self:row("Sound","sound","Sounds: on",C.button,C.text,function()
  gui:SetAttribute("SoundOn",not gui:GetAttribute("SoundOn"));self:refresh()
 end)
 self.music=self:row("Music","music","Music: on",C.button,C.text,function()
  if self.v.musicToggle then self.v.musicToggle()end;self:refresh()
 end)
 self.exit=self:row("Exit","exit","Exit to lobby",Color3.fromRGB(96,40,38),C.text,function()self:exitMatch()end)
 return self
end
-- One full-width row: an icon and a label.
function PM:row(name,icon,label,bg,fg,fn)
 local b=corner(make("TextButton",self.card,{Name=name,Text="",AutoButtonColor=false,BackgroundColor3=bg,BorderSizePixel=0,
  Size=UDim2.new(1,-40,0,ROW),Position=UDim2.fromOffset(20,0),ZIndex=62}),12)
 local r={button=b}
 r.icon=Icons.image(b,icon,22,fg,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,16,.5,0),ZIndex=63})
 r.label=text(b,label,16,Enum.FontWeight.Bold,fg,{Position=UDim2.fromOffset(50,0),Size=UDim2.new(1,-60,1,0),ZIndex=63})
 Anim.button(b,{grow=1.03});b.Activated:Connect(fn)
 table.insert(self.rows,r);r.order=#self.rows
 return r
end
function PM:solo()return self.v.source=="solo"end
function PM:refresh()
 local solo=self:solo()
 self.title.Text=solo and "PAUSE"or "MENU"
 self.sub.Text=solo and "The match is paused"or "The online match goes on"
 local on=self.v.gui:GetAttribute("SoundOn")~=false
 self.sound.label.Text=on and "Sounds: on"or "Sounds: off";Icons.set(self.sound.icon,on and "sound"or "mute")
 local mon=not self.v.musicOn or self.v.musicOn()
 self.music.label.Text=mon and "Music: on"or "Music: off";Icons.set(self.music.icon,mon and "music"or "music_off")
 self.music.button.Visible=self.v.musicToggle~=nil
 -- Rows top to bottom; restart only in a solo match.
 self.restart.button.Visible=solo
 local y=70
 for _,r in ipairs(self.rows)do
  if r.button.Visible then r.button.Position=UDim2.fromOffset(20,y);y+=ROW+GAP end
 end
 self.card.Size=UDim2.fromOffset(WIDTH,y+12)
 local size=self.v.gui.AbsoluteSize
 self.base=math.clamp(math.min((size.X-24)/WIDTH,(size.Y-24)/(y+12)),.55,1);self.scale.Scale=self.base
end
function PM:show(open)
 open=open==true
 if open then self:refresh()end
 -- (one UIScale fits the card to the screen and also makes the short pop-in)
 if open and not self.card.Visible then self.scale.Scale=(self.base or 1)*.94;Anim.tween(self.scale,Anim.SPRING,{Scale=self.base or 1})end
 self.open=open;self.shade.Visible=open;self.card.Visible=open
 -- A solo match stops while the menu is open.
 local lm=self.v.localMatch;if lm then lm.paused=open and self:solo()end
 if open then self.v.battleUI:clearSelection()end
end
function PM:restartSolo()
 self:show(false)
 local lobby=self.v.lobby;if lobby then lobby:startSolo()end
 -- (the whole world again for choosing a new start, as from the lobby)
 local gui=self.v.gui;gui:SetAttribute('ResetCamera',(gui:GetAttribute('ResetCamera')or 0)+1)
end
function PM:exitMatch()
 self:show(false)
 local lobby=self.v.lobby;if lobby then lobby:exitMatch()end
end
-- Called each frame by BattleView: where the button sits and whether it is shown.
function PM:update(shown,x,y)
 self.button.Visible=shown;self.button.Position=UDim2.fromOffset(x,y)
 if not shown and self.open then self:show(false)end
end
function PM:isUI(obj)
 for _,p in ipairs({self.button,self.shade,self.card})do if p.Visible and(obj==p or obj:IsDescendantOf(p))then return true end end
 return false
end
return PM
