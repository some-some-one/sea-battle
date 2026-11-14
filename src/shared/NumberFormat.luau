--!nonstrict
-- Compact display only; authoritative balances and costs retain full precision.
local F={}
function F.compact(value)
 if type(value)~='number'or value~=value or math.abs(value)==math.huge then return '0'end
 local n=math.abs(value);local scale,suffix=1,''
 for _,unit in ipairs({{1e12,'T'},{1e9,'B'},{1e6,'M'},{1e3,'k'}})do
  if n>=unit[1]then scale,suffix=unit[1],unit[2];break end
 end
 local result
 if scale==1 then result=tostring(math.floor(n))
 else result=string.format('%.1f',math.floor(n/scale*10)/10):gsub('%.0$','')end
 return(value<0 and '-'or '')..result..suffix
end
function F.perSecond(value)
 if type(value)~='number'or value~=value or value==math.huge or value<=0 then return '0/s'end
 local formatted
 if value>=1000 then formatted=F.compact(value)
 elseif value<.1 then formatted='<0.1'
 else formatted=string.format('%.1f',math.floor(value*10)/10):gsub('%.0$','')end
 return '+'..formatted..'/s'
end
return F
