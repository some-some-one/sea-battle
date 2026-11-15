--!native
--!nonstrict
-- Compact network rows shared by the server sync loop and the client view.
-- Rows are positional arrays; nil is sent as false because remotes drop array holes.
local P={}
-- flag, pattern: cosmetics a person's country wears (shared/Catalog ids; bots have none).
P.RosterFields={'id','name','color','startCell','region','spawnSite','bot','kind','persona','look','flag','pattern'}
P.FactionFields={'count','gold','fleet','cap','fleetPerSecond','ratio','team','traitorUntil','protectedUntil','humanGraceUntil',
 'lastOrderEnd','committed','transportFleet','transportCount','alive','advancing','attackOwner','expanding'}
-- reload: server time when a missile defence or platform can fire again (false when ready).
P.StructureFields={'id','owner','kind','cell','level','ready','land','water','reload'}
-- rail: corner cells of a train's whole ride over the network (trains only);
-- the track itself arrives separately as `railways` rows {edge id, corner cells}.
-- along/steps: how far along its route a unit is (route cells, to a tenth) and the route's length, so the
-- client can place it between cells: a unit moving 0.6 or 1.2 cells a step would otherwise stop and jump.
P.UnitFields={'id','owner','kind','cell','hp','level','weapon','fleet','origin','destination','rail','shot','returning','hitBy','along','steps','patrol','captured'}
P.AttackFields={'allowed','reason','mode','risk','defensePosts'}
-- mine/theirs: attack force vs defender reserve (attack) or own reserve vs attacking force (defense);
-- loss: fleet the attacker spends per pixel; cells: pixels the defender holds; counter: enemy counterattack.
P.FrontFields={'enemy','mode','mine','theirs','loss','cells','counter'}
local booleans={alive=true,advancing=true,expanding=true,bot=true,allowed=true,returning=true}
function P.pack(t,fields)
 local row=table.create(#fields)
 for i,key in ipairs(fields)do local v=t[key];if v==nil then v=false end;row[i]=v end
 return row
end
function P.unpack(row,fields,into)
 into=into or {}
 for i,key in ipairs(fields)do
  local v=row[i];if v==false and not booleans[key]then v=nil end;into[key]=v
 end
 return into
end
function P.signature(row)
 local parts=table.create(#row)
 for i,v in ipairs(row)do parts[i]=type(v)=='table'and table.concat(v,',')or tostring(v)end
 return table.concat(parts,'|')
end
-- Ownership changes: u32 cell id + u8 owner per entry.
P.CellBytes=5
function P.decodeCells(cells)
 local out={}
 if type(cells)=='table'then return cells end
 if typeof(cells)~='buffer'then return out end
 for i=0,buffer.len(cells)//P.CellBytes-1 do
  out[i+1]={buffer.readu32(cells,i*P.CellBytes),buffer.readu8(cells,i*P.CellBytes+4)}
 end
 return out
end
return P
