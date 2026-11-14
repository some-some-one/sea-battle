--!native
--!nonstrict
-- Wire format between the server and its clients: every message is one
-- `buffer`, encoded once per tick for everyone and zstd-compressed when larger than COMPRESS_OVER.
--
-- Envelope: u8 0 = raw body, 1 = zstd body. Body: one tagged value (the same tables the view already
-- reads), with two kinds of deltas that keep a busy match small:
--  * units — a stream sends only the units that changed since its previous message, and a unit's
--    route (`rail`, a long list of corner cells) only when it changed; `unitsGone` lists removed ids.
--  * structures — only rows that changed, and `structuresGone`.
-- The decoder keeps the full unit and structure lists and hands the view complete `units` /
-- `structures` lists, so nothing above this module knows about deltas. A snapshot resets both sides.
-- Cell changes ({u32 id, u8 owner} buffers) travel sorted, as id deltas: 2-3 bytes per cell before zstd.
--
-- Tagged values: 0 nil, 1 false, 2 true, 3 uint (varint), 4 negative int (varint of -v), 5 f32,
-- 6 f64, 7 string, 8 array, 9 map, 10 buffer, 11 cells, 12 "kept" (unit route unchanged), 13 empty
-- table, 14/15 tenths (+/-, varint of v×10: match times and rates), 16..255 small uint 0..239 in the tag.
-- Numbers: whole → varint; tenths → varint of tenths; other fractions → f32 when within 1e-4, else f64.
local EncodingService=game:GetService("EncodingService")
local P=require(script.Parent.Protocol)

local W={}
W.COMPRESS_OVER=1200
local KEPT={} -- decoded "route unchanged" marker
local RAIL=table.find(P.UnitFields,'rail')
local UNIT_ID=table.find(P.UnitFields,'id')
local STRUCT_ID=table.find(P.StructureFields,'id')

-- ---------------------------------------------------------------- writer / reader
local Writer={};Writer.__index=Writer
local function writer()return setmetatable({b=buffer.create(1024),n=0},Writer)end
function Writer:room(k)
 local need=self.n+k
 if need>buffer.len(self.b)then
  local size=buffer.len(self.b)*2;while size<need do size*=2 end
  local nb=buffer.create(size);buffer.copy(nb,0,self.b,0,self.n);self.b=nb
 end
end
function Writer:u8(v)self:room(1);buffer.writeu8(self.b,self.n,v);self.n+=1 end
function Writer:var(v)
 self:room(10)
 while v>=128 do buffer.writeu8(self.b,self.n,v%128+128);self.n+=1;v=v//128 end
 buffer.writeu8(self.b,self.n,v);self.n+=1
end
function Writer:f32(v)self:room(4);buffer.writef32(self.b,self.n,v);self.n+=4 end
function Writer:f64(v)self:room(8);buffer.writef64(self.b,self.n,v);self.n+=8 end
function Writer:bytes(src,len)self:room(len);buffer.copy(self.b,self.n,src,0,len);self.n+=len end
function Writer:str(s)self:var(#s);self:room(#s);buffer.writestring(self.b,self.n,s);self.n+=#s end
function Writer:done()local out=buffer.create(self.n);buffer.copy(out,0,self.b,0,self.n);return out end

local Reader={};Reader.__index=Reader
local function reader(b,pos)return setmetatable({b=b,p=pos or 0},Reader)end
function Reader:u8()local v=buffer.readu8(self.b,self.p);self.p+=1;return v end
function Reader:var()
 local v,m=0,1
 while true do local x=buffer.readu8(self.b,self.p);self.p+=1;v+=(x%128)*m;if x<128 then return v end;m*=128 end
end

-- ---------------------------------------------------------------- tagged values
local encode
local function isArray(t)
 local n=#t;local count=0
 for _ in pairs(t)do count+=1;if count>n then return false end end
 return count==n
end
-- A non-integer that a float32 keeps to within 1e-4 travels in 4 bytes (times, rates, shares).
local function exactF32(v)
 local b=buffer.create(4);buffer.writef32(b,0,v);local r=buffer.readf32(b,0)
 return math.abs(r-v)<=1e-4
end
encode=function(w,v)
 local t=type(v)
 if v==nil then w:u8(0)
 elseif v==false then w:u8(1)
 elseif v==true then w:u8(2)
 elseif v==KEPT then w:u8(12)
 elseif t=='number'then
  if v==math.floor(v)and math.abs(v)<2^52 then
   if v>=0 and v<240 then w:u8(16+v)
   elseif v>=0 then w:u8(3);w:var(v)
   else w:u8(4);w:var(-v)end
  elseif math.abs(v*10-math.round(v*10))<1e-6 and math.abs(v)<2^40 then
   -- Tenths (match times, rates): a whole number of tenths, usually 2-3 bytes.
   local t=math.round(v*10);if t>=0 then w:u8(14);w:var(t)else w:u8(15);w:var(-t)end
  elseif exactF32(v)then w:u8(5);w:f32(v)
  else w:u8(6);w:f64(v)end
 elseif t=='string'then w:u8(7);w:str(v)
 elseif typeof(v)=='buffer'then w:u8(10);w:var(buffer.len(v));w:bytes(v,buffer.len(v))
 elseif t=='table'then
  if next(v)==nil then w:u8(13)
  elseif isArray(v)then w:u8(8);w:var(#v);for i=1,#v do encode(w,v[i])end
  else
   local n=0;for _ in pairs(v)do n+=1 end
   w:u8(9);w:var(n)
   for k,x in pairs(v)do
    if type(k)=='string'then w:u8(0);w:str(k)else w:u8(1);encode(w,k)end
    encode(w,x)
   end
  end
 else error('Wire: cannot encode '..t)end
end
local decode
decode=function(r)
 local tag=r:u8()
 if tag>=16 then return tag-16
 elseif tag==0 then return nil
 elseif tag==1 then return false
 elseif tag==2 then return true
 elseif tag==3 then return r:var()
 elseif tag==4 then return -r:var()
 elseif tag==5 then local v=buffer.readf32(r.b,r.p);r.p+=4;return v
 elseif tag==6 then local v=buffer.readf64(r.b,r.p);r.p+=8;return v
 elseif tag==7 then local n=r:var();local s=buffer.readstring(r.b,r.p,n);r.p+=n;return s
 elseif tag==8 then local n=r:var();local a=table.create(n);for i=1,n do a[i]=decode(r)end;return a
 elseif tag==9 then
  local n=r:var();local m={}
  for _=1,n do
   local k;if r:u8()==0 then local len=r:var();k=buffer.readstring(r.b,r.p,len);r.p+=len else k=decode(r)end
   m[k]=decode(r)
  end
  return m
 elseif tag==10 then local n=r:var();local b=buffer.create(n);buffer.copy(b,0,r.b,r.p,n);r.p+=n;return b
 elseif tag==11 then
  -- Sorted cell changes back to {u32 id, u8 owner} entries.
  local n=r:var();local b=buffer.create(n*P.CellBytes);local id=0
  for i=0,n-1 do id+=r:var();buffer.writeu32(b,i*P.CellBytes,id);buffer.writeu8(b,i*P.CellBytes+4,r:u8())end
  return b
 elseif tag==12 then return KEPT
 elseif tag==13 then return {}
 elseif tag==14 then return r:var()/10
 elseif tag==15 then return -r:var()/10
 end
 error('Wire: bad tag '..tag)
end
-- Cell changes: sorted by id, each written as the distance from the previous id and the owner byte.
local function encodeCells(w,cells)
 local n=buffer.len(cells)//P.CellBytes
 local order=table.create(n)
 for i=0,n-1 do order[i+1]=i end
 table.sort(order,function(a,b)return buffer.readu32(cells,a*P.CellBytes)<buffer.readu32(cells,b*P.CellBytes)end)
 w:u8(11);w:var(n);local prev=0
 for _,i in ipairs(order)do
  local id=buffer.readu32(cells,i*P.CellBytes);w:var(id-prev);prev=id;w:u8(buffer.readu8(cells,i*P.CellBytes+4))
 end
end

-- ---------------------------------------------------------------- envelope
local function seal(w)
 local body=w:done()
 local out
 if buffer.len(body)>W.COMPRESS_OVER then
  local ok,z=pcall(EncodingService.CompressBuffer,EncodingService,body,Enum.CompressionAlgorithm.Zstd,3)
  if ok and buffer.len(z)<buffer.len(body)then
   out=buffer.create(buffer.len(z)+1);buffer.writeu8(out,0,1);buffer.copy(out,1,z,0,buffer.len(z));return out
  end
 end
 out=buffer.create(buffer.len(body)+1);buffer.writeu8(out,0,0);buffer.copy(out,1,body,0,buffer.len(body))
 return out
end
local function open(msg)
 local kind=buffer.readu8(msg,0)
 local body=buffer.create(buffer.len(msg)-1);buffer.copy(body,0,msg,1,buffer.len(msg)-1)
 if kind==1 then body=EncodingService:DecompressBuffer(body,Enum.CompressionAlgorithm.Zstd)end
 return body
end

-- ---------------------------------------------------------------- unit / structure deltas
local function sameRow(a,b,skip)
 if #a~=#b then return false end
 for i=1,#a do if i~=skip and a[i]~=b[i]then
  local x,y=a[i],b[i]
  if type(x)=='table'and type(y)=='table'then
   if #x~=#y then return false end;for k=1,#x do if x[k]~=y[k]then return false end end
  else return false end
 end end
 return true
end
-- Encoder state of one stream (all clients of the server share one).
function W.newEncoder()return {units={},structures={}}end
-- The rows of `list` that differ from what the stream holds, and the ids it holds that are gone.
local function unitDelta(enc,list)
 local seen,changed,gone={}, {}, {}
 for _,row in ipairs(list)do
  local id=row[UNIT_ID];seen[id]=true
  local old=enc.units[id]
  if not old or not sameRow(old,row,nil)then
   local out=table.clone(row)
   -- The route is the bulk of a unit: kept when it did not change.
   if old and RAIL and sameRow({old[RAIL]},{row[RAIL]},nil)then out[RAIL]=KEPT end
   table.insert(changed,out);enc.units[id]=row
  end
 end
 for id in pairs(enc.units)do if not seen[id]then table.insert(gone,id);enc.units[id]=nil end end
 return changed,gone
end
local function structureDelta(enc,list)
 local seen,changed,gone={}, {}, {}
 for _,row in ipairs(list)do
  local id=row[STRUCT_ID];seen[id]=true
  local old=enc.structures[id]
  if not old or not sameRow(old,row,nil)then table.insert(changed,row);enc.structures[id]=row end
 end
 for id in pairs(enc.structures)do if not seen[id]then table.insert(gone,id);enc.structures[id]=nil end end
 return changed,gone
end
local function writeMap(w,map)
 local n=0;for _ in pairs(map)do n+=1 end
 w:u8(9);w:var(n)
 for k,v in pairs(map)do
  w:u8(0);w:str(k)
  if k=='cells'and typeof(v)=='buffer'then encodeCells(w,v)else encode(w,v)end
 end
end

-- A packet for the stream: `units` and `structures` (full lists, as Game:syncPacket gives them) become
-- deltas against `enc`; a snapshot ({snapshot=...}) is sent whole and resets `enc` to it.
function W.encode(packet,enc)
 local w=writer()
 if packet.snapshot then
  local s=packet.snapshot
  if enc then
   enc.units={};enc.structures={}
   for _,row in ipairs(s.units or {})do enc.units[row[UNIT_ID]]=row end
   for _,row in ipairs(s.structures or {})do enc.structures[row[STRUCT_ID]]=row end
  end
  writeMap(w,{snapshot=s})
  return seal(w)
 end
 local out=table.clone(packet)
 if enc and packet.units then
  out.units=nil;local changed,gone=unitDelta(enc,packet.units)
  out.unitsChanged=changed;if #gone>0 then out.unitsGone=gone end
 end
 if enc and packet.structures then
  out.structures=nil;local changed,gone=structureDelta(enc,packet.structures)
  if #changed>0 then out.structuresChanged=changed end;if #gone>0 then out.structuresGone=gone end
 end
 writeMap(w,out)
 return seal(w)
end
-- Decoder state of one client, mirroring the server's encoder. `history` keeps the unit and structure
-- changes of recent messages: a snapshot asked for on joining can arrive after newer broadcasts, and
-- those are applied again on top of it (else a unit removed meanwhile would stay on the map).
function W.newDecoder()return {units={},structures={},history={}}end
local HISTORY=80
local function applyChanges(dec,h)
 for _,row in ipairs(h.unitsChanged or {})do
  local id=row[UNIT_ID]
  if RAIL and row[RAIL]==KEPT then local old=dec.units[id];row=table.clone(row);row[RAIL]=old and old[RAIL]or false end
  dec.units[id]=row
 end
 for _,id in ipairs(h.unitsGone or {})do dec.units[id]=nil end
 for _,row in ipairs(h.structuresChanged or {})do dec.structures[row[STRUCT_ID]]=row end
 for _,id in ipairs(h.structuresGone or {})do dec.structures[id]=nil end
end
local function listOf(map)
 local ids={};for id in pairs(map)do table.insert(ids,id)end;table.sort(ids)
 local list=table.create(#ids);for i,id in ipairs(ids)do list[i]=map[id]end
 return list
end
-- Back to the tables the view reads: complete `units` and `structures` lists.
function W.decode(msg,dec)
 local value=decode(reader(open(msg)))
 if value.snapshot then
  local s=value.snapshot
  dec.units={};dec.structures={}
  for _,row in ipairs(s.units or {})do dec.units[row[UNIT_ID]]=row end
  for _,row in ipairs(s.structures or {})do dec.structures[row[STRUCT_ID]]=row end
  local newer=false
  for _,h in ipairs(dec.history)do
   -- Same or later match time: rows are absolute, so a message as old as the snapshot changes nothing.
   if h.epoch==s.epoch and h.time>=(s.time or 0)then applyChanges(dec,h);newer=true end
  end
  if newer then s.units=listOf(dec.units);s.structures=listOf(dec.structures)end
  return value
 end
 local hasUnits=value.unitsChanged~=nil or value.unitsGone~=nil
 local hasStructures=value.structuresChanged~=nil or value.structuresGone~=nil
 if hasUnits or hasStructures then
  local h={epoch=value.epoch,time=value.time or 0,unitsChanged=value.unitsChanged,unitsGone=value.unitsGone,
   structuresChanged=value.structuresChanged,structuresGone=value.structuresGone}
  applyChanges(dec,h)
  table.insert(dec.history,h);if #dec.history>HISTORY then table.remove(dec.history,1)end
  value.unitsChanged=nil;value.unitsGone=nil;value.structuresChanged=nil;value.structuresGone=nil
  if hasUnits then value.units=listOf(dec.units)end
  if hasStructures then value.structures=listOf(dec.structures)end
 end
 return value
end
-- One-off values (a command reply, private state): no deltas.
function W.pack(value)local w=writer();encode(w,value);return seal(w)end
function W.unpack(msg)return decode(reader(open(msg)))end
W.KEPT=KEPT
return W
