--!nonstrict
-- The lobby logo, built on the device in an EditableImage from LogoPixels (tools/make_logo.py): an
-- uploaded image can stay unavailable to players, as the icons showed (see Icons). Logo.content()
-- returns the picture's Content, or nil when no EditableImage can be made (the lobby then keeps its
-- text title).
local AssetService=game:GetService("AssetService")
local Pixels=require(script.Parent.LogoPixels)
local Logo={width=Pixels.width,height=Pixels.height}
local built,content=false,nil
-- base64 -> bytes (a buffer), without string building.
local function decode(s)
 local map={}
 local abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
 for i=1,64 do map[string.byte(abc,i)]=i-1 end
 local n=#s;local pad=(string.sub(s,-2)=="==" and 2)or(string.sub(s,-1)=="=" and 1)or 0
 local out=buffer.create(n//4*3-pad);local o=0;local size=buffer.len(out)
 for i=1,n,4 do
  local a,b,c,d=string.byte(s,i,i+3)
  local v=map[a]*262144+map[b]*4096+(map[c]or 0)*64+(map[d]or 0)
  buffer.writeu8(out,o,v//65536);o+=1
  if o<size then buffer.writeu8(out,o,(v//256)%256);o+=1 end
  if o<size then buffer.writeu8(out,o,v%256);o+=1 end
 end
 return out
end
local function build()
 built=true
 local w,h=Pixels.width,Pixels.height
 local ok,img=pcall(function()return AssetService:CreateEditableImage({Size=Vector2.new(w,h)})end)
 if not ok or not img then warn("[Logo] EditableImage unavailable: the lobby keeps its text title");return end
 -- The palette as little-endian RGBA words (byte order in the buffer: R, G, B, A).
 local pal={};local p=Pixels.palette
 for i=0,#p//8-1 do
  local r,g,b,a=tonumber(string.sub(p,i*8+1,i*8+2),16),tonumber(string.sub(p,i*8+3,i*8+4),16),tonumber(string.sub(p,i*8+5,i*8+6),16),tonumber(string.sub(p,i*8+7,i*8+8),16)
  pal[i]=r+g*256+b*65536+a*16777216
 end
 local runs=decode(Pixels.data);local buf=buffer.create(w*h*4);local pos=0
 for k=0,buffer.len(runs)-2,2 do
  local word=pal[buffer.readu8(runs,k)];local run=buffer.readu8(runs,k+1)+1
  if word~=0 then for q=pos,pos+run-1 do buffer.writeu32(buf,q*4,word)end end
  pos+=run
 end
 local wrote=pcall(function()img:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),buf)end)
 if wrote then content=Content.fromObject(img)end
end
function Logo.content()
 if not built then build()end
 return content
end
return Logo
