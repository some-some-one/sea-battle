--!nonstrict
-- Pixel art of the cosmetics, all drawn here (nothing copied from another game, no brands or logos):
--  * flags — 40 real countries' national flags (state symbols, free to depict), 14 x 10 pixels each,
--    simplified by our own hand, and four picture flags of our own (anchor, skull, star, trident). The
--    signal-code flags were removed on 2026-11-12 by the author's decision.
--  * water patterns — a small 1-bit tile repeated over a country's water ('#' takes the second tint).
local A={}
A.FlagWidth,A.FlagHeight=14,10
A.Palette={W={245,245,240},B={44,92,196},R={212,52,62},Y={248,206,62},K={20,24,32},N={24,42,84},T={36,150,150},
 G={255,198,84},D={16,58,96},E={12,70,74},
 -- (for the country flags)
 g={0,140,70},o={255,136,40},l={116,178,230},m={150,36,52},y={255,210,0},u={140,92,44}}
local function rows(fn)
 local out={}
 for y=0,A.FlagHeight-1 do
  local line={}
  for x=0,A.FlagWidth-1 do line[x+1]=fn(x,y)end
  out[y+1]=table.concat(line)
 end
 return out
end
-- A picture on one background colour: '.' is the background.
local function picture(background,lines)
 local out={}
 for i,line in ipairs(lines)do out[i]=string.gsub(line,'%.',background)end
 return out
end
-- Four picture flags of our own (skull, anchor, star, trident), kept on 2026-11-12 by the author's
-- decision beside the real flags; sold for Products.PictureFlagRobux.
A.Flags={
 flag_anchor=picture('N',{
  '..............',
  '......WW......',
  '.....WWWW.....',
  '......WW......',
  '....WWWWWW....',
  '......WW......',
  '..W...WW...W..',
  '..WW..WW..WW..',
  '...WWWWWWWW...',
  '.....WWWW.....'}),
 flag_jolly=picture('K',{
  '..............',
  '....WWWWWW....',
  '...WWWWWWWW...',
  '...WKKWWKKW...',
  '...WKKWWKKW...',
  '...WWWKKWWW...',
  '....WWWWWW....',
  '....WKWWKW....',
  '.....WWWW.....',
  '..............'}),
 flag_star=picture('D',{
  '..............',
  '......GG......',
  '......GG......',
  '..GGGGGGGGGG..',
  '...GGGGGGGG...',
  '....GGGGGG....',
  '....GGGGGG....',
  '...GGG..GGG...',
  '...GG....GG...',
  '..............'}),
 flag_trident=picture('E',{
  '..............',
  '..G...GG...G..',
  '..G...GG...G..',
  '..G...GG...G..',
  '..GG..GG..GG..',
  '...GGGGGGGG...',
  '......GG......',
  '......GG......',
  '......GG......',
  '..............'}),
}
-- Country flags.
local function hs(list)return rows(function(_,y)return list[y*#list//A.FlagHeight+1]end)end
local function vs(list)return rows(function(x)return list[x*#list//A.FlagWidth+1]end)end
local function disc(bg,fg,cx,cy,r)return rows(function(x,y)return(x-cx)^2+(y-cy)^2<=r*r and fg or bg end)end
-- A Nordic cross (two pixels wide; with `inner`, four wide with an inner cross of that colour).
local function nordic(bg,cross,inner)
 return rows(function(x,y)
  if inner and((x>=4 and x<=5)or(y>=4 and y<=5))then return inner end
  if(x>=(inner and 3 or 4)and x<=(inner and 6 or 5))or(y>=(inner and 3 or 4)and y<=(inner and 6 or 5))then return cross end
  return bg
 end)
end
-- Change some pixels of a flag: {x, y, letter} (from 0).
local function dots(flag,list)
 for _,d in ipairs(list)do local line=flag[d[2]+1];flag[d[2]+1]=string.sub(line,1,d[1])..d[3]..string.sub(line,d[1]+2)end
 return flag
end
local C={}
C.ru=hs({'W','B','R'});C.ua=hs({'B','y'});C.fr=vs({'B','W','R'});C.it=vs({'g','W','R'});C.de=hs({'K','R','y'})
C.nl=hs({'R','W','B'});C.be=vs({'K','y','R'});C.ie=vs({'g','W','o'});C.at=hs({'R','W','R'});C.pl=hs({'W','R'})
C.id=hs({'R','W'});C.hu=hs({'R','W','g'});C.bg=hs({'W','g','R'});C.lt=hs({'y','g','R'});C.ee=hs({'B','K','W'})
C.lv=rows(function(_,y)return(y==4 or y==5)and 'W'or 'm'end);C.ro=vs({'B','y','R'});C.am=hs({'R','B','o'})
C.es=rows(function(_,y)return(y<=1 or y>=8)and 'R'or 'y'end)
C.co=rows(function(_,y)return y<=4 and 'y'or y<=6 and 'B'or 'R'end)
C.jp=disc('W','R',6.5,4.5,3);C.bd=disc('g','R',5.8,4.5,3)
C.se=nordic('B','y');C.fi=nordic('W','B');C.dk=nordic('R','W');C.no=nordic('R','W','B');C.is=nordic('B','W','R')
C.ch=rows(function(x,y)return((x>=6 and x<=7 and y>=2 and y<=7)or(y>=4 and y<=5 and x>=4 and x<=9))and 'W'or 'R'end)
C.gr=rows(function(x,y)
 if x<5 and y<5 then return(x==2 or y==2)and 'W'or 'B'end
 return y%2==0 and 'B'or 'W'
end)
C.us=rows(function(x,y)
 if x<6 and y<5 then return(x%2==1 and y%2==1)and 'W'or 'N'end
 return y%2==0 and 'R'or 'W'
end)
C.gb=rows(function(x,y)
 if x>=6 and x<=7 or y>=4 and y<=5 then return 'R'end
 if x>=5 and x<=8 or y>=3 and y<=6 then return 'W'end
 local u,v=math.abs((x-6.5)/7),math.abs((y-4.5)/5)
 local d=math.abs(u-v)
 if d<.09 then return 'R'end
 if d<.2 then return 'W'end
 return 'N'
end)
C.ca=dots(rows(function(x)return(x<=2 or x>=11)and 'R'or 'W'end),
 {{6,1,'R'},{7,1,'R'},{4,2,'R'},{6,2,'R'},{7,2,'R'},{9,2,'R'},{4,3,'R'},{5,3,'R'},{6,3,'R'},{7,3,'R'},{8,3,'R'},{9,3,'R'},
  {5,4,'R'},{6,4,'R'},{7,4,'R'},{8,4,'R'},{4,5,'R'},{5,5,'R'},{6,5,'R'},{7,5,'R'},{8,5,'R'},{9,5,'R'},{6,6,'R'},{7,6,'R'},{6,7,'R'},{7,7,'R'}})
C.br=rows(function(x,y)
 local u,v=(x-6.5)/5.6,(y-4.5)/4
 if u*u+v*v*1.6<=.22 then return 'N'end
 if math.abs(u)+math.abs(v)<=1 then return 'y'end
 return 'g'
end)
C.ar=dots(rows(function(_,y)return(y<=2 or y>=7)and 'l'or 'W'end),{{6,4,'y'},{7,4,'y'},{6,5,'y'},{7,5,'y'}})
C.tr=dots(rows(function(x,y)
 local inA=(x-5)^2+(y-4.5)^2<=9;local inB=(x-6)^2+(y-4.5)^2<=5.3
 return(inA and not inB)and 'W'or 'R'
end),{{9,4,'W'},{9,5,'W'},{8,4,'W'},{10,5,'W'}})
C.cn=dots(rows(function()return 'R'end),{{2,1,'y'},{1,2,'y'},{2,2,'y'},{3,2,'y'},{2,3,'y'},{1,4,'y'},{3,4,'y'},{5,1,'y'},{6,2,'y'},{6,4,'y'},{5,5,'y'}})
C.kr=dots(rows(function(x,y)
 if(x-6.5)^2+(y-4.5)^2<=7 then return y<5 and 'R'or 'B'end
 return 'W'
end),{{1,1,'K'},{2,1,'K'},{11,1,'K'},{12,1,'K'},{1,8,'K'},{2,8,'K'},{11,8,'K'},{12,8,'K'}})
C['in']=dots(hs({'o','W','g'}),{{6,5,'N'},{7,5,'N'},{6,4,'N'},{7,4,'N'}})
C.mx=dots(vs({'g','W','R'}),{{6,4,'u'},{7,4,'u'},{6,5,'u'},{7,5,'u'},{5,6,'g'},{8,6,'g'}})
C.kz=dots(rows(function(x,y)
 if(x-7)^2+(y-3.6)^2<=4.4 then return 'y'end
 if x==1 and y%2==0 then return 'y'end
 return 'l'
end),{{5,7,'y'},{6,6,'y'},{7,6,'y'},{8,6,'y'},{9,7,'y'}})
for code,flag in pairs(C)do A.Flags['flag_cc_'..code]=flag end
local function tile(w,h,fn)
 local out={}
 for y=0,h-1 do
  local line={}
  for x=0,w-1 do line[x+1]=fn(x,y)and '#'or '.'end
  out[y+1]=table.concat(line)
 end
 return out
end
local TAU=math.pi*2
-- A small picture ('#' lit) copied into a w x h tile at the given top-left corners; `dots` are single cells.
local function place(w,h,picture,at,dots)
 local lit={}
 for _,c in ipairs(at)do
  for py,line in ipairs(picture)do
   for px=1,#line do if string.sub(line,px,px)=='#'then lit[((c[2]+py-1)%h)*w+(c[1]+px-1)%w]=true end end
  end
 end
 for _,d in ipairs(dots or {})do lit[d[2]*w+d[1]]=true end
 return tile(w,h,function(x,y)return lit[y*w+x]==true end)
end
A.Patterns={
 pat_ripple={'#.....','......','...#..','......'},
 pat_stripes=tile(6,6,function(x,y)return(x+y)%6<2 end),
 pat_wave={'..##....','.#..#...','#....#.#','......#.'},
 pat_grid=tile(6,6,function(x,y)return x==0 or y==0 end),
 pat_chevron={'#...#...','.#.#.#.#','..#...#.','........'},
 -- (whole periods of sines on 16 cells, so the tile repeats without a seam)
 pat_camo=tile(16,16,function(x,y)
  return math.sin(TAU*(x+2*y)/16)+math.sin(TAU*(3*x-y)/16)+math.sin(TAU*(2*x+3*y)/16)>.9
 end),
 pat_compass=tile(16,16,function(x,y)
  local dx,dy=math.abs(x-8),math.abs(y-8)
  return(dx==0 and dy<=6)or(dy==0 and dx<=6)or(dx==dy and dx>=1 and dx<=3)
 end),
 -- (ten more, 2026-11-12, by the author's request; our own tiles)
 pat_dots=tile(6,6,function(x,y)return(x==1 and y==1)or(x==4 and y==4)end),
 pat_checker=tile(4,4,function(x,y)return(x//2+y//2)%2==0 end),
 pat_zigzag=tile(8,6,function(x,y)local t=x%8;return y==(t<4 and t or 8-t)end),
 pat_bricks=tile(8,6,function(x,y)return y%3==0 or(y<3 and x==0)or(y>=3 and x==4)end),
 pat_scales={
  '#......#',
  '.#....#.',
  '..####..',
  '........',
  '...##...',
  '..#..#..',
  '##....##',
  '........'},
 pat_crosshatch=tile(8,8,function(x,y)return(x+y)%8==0 or(x-y)%8==0 end),
 pat_diamonds=tile(8,8,function(x,y)local d=math.abs(x-4)+math.abs(y-4);return d==3 or d==0 end),
 pat_anchors=place(16,16,{
  '...#...',
  '..###..',
  '...#...',
  '...#...',
  '#..#..#',
  '.#.#.#.',
  '..###..'},{{1,1},{9,9}}),
 pat_stars=place(16,16,{
  '..#..',
  '#####',
  '.###.',
  '.#.#.'},{{2,2},{10,10}},{{11,3},{4,12},{14,7},{7,8}}),
 pat_whirlpool=tile(16,16,function(x,y)
  local dx,dy=x-7.5,y-7.5
  local r=math.sqrt(dx*dx+dy*dy)
  if r>7.6 then return false end
  return(r*1.1-math.atan2(dy,dx)/TAU*3.3)%3.3<1.1
 end),
 -- (ten more, 2026-11-16, by the author's request; our own tiles)
 pat_rain=tile(8,8,function(x,y)return(x==1 and y%8<3)or(x==5 and(y+4)%8<3)end),
 pat_dashes=tile(8,4,function(x,y)return(y==0 and x<4)or(y==2 and x>=4)end),
 pat_triangles=place(8,8,{'.#.','###'},{{0,0},{4,4}}),
 -- basket weave: blocks of short lines, across and along in turn
 pat_weave=tile(8,8,function(x,y)
  local across=(x<4)==(y<4)
  return across and y%2==0 or not across and x%2==0
 end),
 pat_rings=tile(8,8,function(x,y)local d=math.sqrt((x-3.5)^2+(y-3.5)^2);return math.abs(d-2.6)<.55 end),
 pat_fish=place(16,16,{
  '..###..#',
  '.#####.#',
  '#.######',
  '.#####.#',
  '..###..#'},{{1,2},{9,10}}),
 pat_shells=place(16,16,{
  '.#####.',
  '#.#.#.#',
  '#.#.#.#',
  '.#.#.#.',
  '..###..'},{{1,1},{9,9}}),
 -- a ship's wheel: rim, hub, eight spokes running out past the rim to handles
 pat_wheel=tile(16,16,function(x,y)
  local dx,dy=x-8,y-8;local r=math.sqrt(dx*dx+dy*dy)
  if math.abs(r-4.6)<.6 or r<1.6 then return true end
  return(dx==0 or dy==0 or math.abs(dx)==math.abs(dy))and r<=7.1 and r>=1.6
 end),
 -- two tentacles winding across the tile (whole sine periods: no seam), with suckers
 pat_kraken=tile(16,16,function(x,y)
  local a=8+4.5*math.sin(TAU*x/16)
  local b=8+4.5*math.sin(TAU*y/16+2)
  if math.abs(y-a)<.75 or math.abs(x-b)<.75 then return true end
  return(x+y)%8==0 and math.abs(y-a)<2.2 and math.abs(y-a)>1.2
 end),
 pat_lighthouse=place(16,16,{
  '#...#...#',
  '.#.###.#.',
  '...###...',
  '....#....',
  '...###...',
  '...#.#...',
  '...###...',
  '..#####..'},{{3,3}},{{13,1},{1,13},{14,12},{11,14}}),
}
return A
