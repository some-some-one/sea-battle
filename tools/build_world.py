"""Build the canonical atlas, pixel preview and a self-contained Roblox place.

Python 3 + Pillow. Uses cached Natural Earth archives for the Earth variant.
No accounts, asset uploads or network requests are needed during the build.
Run from any directory: python3 sea-battle/tools/build_world.py
"""
from __future__ import annotations

from collections import Counter, deque
import argparse
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
W, H, TILE, SECTOR, SEED = 256, 160, 0.5, 8, 11012026
WRAP = False


def noise(x, y, scale=10):
    def rnd(a, b):
        n = (a * 374761393 + b * 668265263 + SEED) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 65535) / 65535
    a, b = math.floor(x / scale), math.floor(y / scale)
    u, v = x / scale - a, y / scale - b
    u, v = u*u*(3-2*u), v*v*(3-2*v)
    return ((rnd(a,b)*(1-u)+rnd(a+1,b)*u)*(1-v)
            +(rnd(a,b+1)*(1-u)+rnd(a+1,b+1)*u)*v)


def ellipse(x, y, cx, cy, rx, ry):
    return 1 - ((x-cx)/rx)**2 - ((y-cy)/ry)**2


def near_path(x, y, points, width):
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        dx, dy = bx-ax, by-ay
        t = max(0, min(1, ((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy)))
        if (x-ax-t*dx)**2+(y-ay-t*dy)**2 <= width*width:
            return True
    return False


def neighbors(i):
    x, y = i % W, i // W
    if x: yield i-1
    elif WRAP: yield i+W-1
    if x < W-1: yield i+1
    elif WRAP: yield i-W+1
    if y: yield i-W
    if y < H-1: yield i+W


def distance(mask):
    result = [999]*(W*H)
    q = deque(i for i, b in enumerate(mask) if b)
    for i in q: result[i] = 0
    while q:
        i = q.popleft()
        for j in neighbors(i):
            if result[j] > result[i]+1:
                result[j] = result[i]+1
                q.append(j)
    return result


def make_atlas():
    blobs = [(40,35,29,23),(27,60,23,29),(57,56,22,18),
             (204,43,32,30),(224,69,24,39),(204,96,29,18),
             (38,117,21,21),(64,130,34,16),(91,139,23,12),
             (109,91,8,12),(130,77,6,8),(149,64,8,7),
             (131,26,10,5),(151,23,6,4),(167,32,5,4),
             (152,130,10,5),(172,138,7,6),(190,131,5,4),
             (95,45,4,3),(90,29,3,4),(174,107,4,6)]
    land, special, height = [], [], []
    rivers = [([(40,39),(48,46),(46,54),(54,61),(60,68),(72,74)],1.05),
              ([(230,91),(222,92),(215,99),(207,108),(202,116)],1.1),
              ([(51,120),(57,123),(61,128),(70,130),(80,128),(98,124)],0.9)]
    for y in range(H):
        for x in range(W):
            h = max(ellipse(x,y,*b) for b in blobs)
            h += (noise(x,y,8)-0.5)*0.46+(noise(x,y,3)-0.5)*0.16
            is_land, water_kind = h > 0.08, None
            # An inland sea with a deliberately navigable 4-cell strait.
            if ellipse(x,y,211,60,15,18)+(noise(x,y,4)-0.5)*0.3 > 0:
                is_land, water_kind = False, "sea"
            if near_path(x,y,[(177,75),(188,76),(197,73),(203,70)],2.2):
                is_land, water_kind = False, "sea"
            for cx,cy,rx,ry in [(40,37,7,5),(27,66,5,4),(230,91,5,4),(51,120,5,3)]:
                if ellipse(x,y,cx,cy,rx,ry)+(noise(x,y,3)-0.5)*0.2 > 0:
                    is_land, water_kind = False, "lake"
            for path, width in rivers:
                if near_path(x,y,path,width) and (is_land or water_kind is None):
                    is_land, water_kind = False, "river"
            land.append(is_land)
            special.append(water_kind)
            height.append(h)
    coast = distance(land)
    inland = distance([not b for b in land])
    palette, keys = [], {}
    def entry(kind, depth, rgb, biome="water"):
        key = (kind,depth,rgb,biome)
        if key not in keys:
            keys[key] = len(palette)+1
            palette.append(dict(kind=kind,depth=depth,color=list(rgb),
                                water=kind != "land",biome=biome))
        return keys[key]
    pixels = []
    for i, is_land in enumerate(land):
        x, y = i % W, i // W
        n = noise(x,y,4)
        if is_land:
            if inland[i] == 1:
                rgb, biome = (213,199,143), "beach"
            elif y < 24 and height[i] > 0.5:
                rgb, biome = (194,215,202), "tundra"
            elif height[i] > 0.8 and noise(x,y,13) > 0.54:
                rgb, biome = ((111,134,115) if n<0.5 else (129,148,124)), "highland"
            else:
                rgb, biome = ((119,158,113) if n<0.38 else
                              (136,173,123) if n<0.68 else (150,183,131)), "grass"
            pixels.append(entry("land",0,rgb,biome))
            continue
        kind = special[i]
        if kind == "lake":
            depth, rgb = 3, (63,145,162)
        elif kind == "river":
            depth, rgb = 1, (83,166,176)
        else:
            kind = "sea" if kind == "sea" or coast[i] <= 7 else "ocean"
            if coast[i] == 1:
                depth, rgb = 1, (90,177,177)
            elif coast[i] <= 3:
                depth, rgb = 2, (57,148,167)
            elif coast[i] <= 7:
                depth, rgb = 3, (43,113,148)
            elif coast[i] <= 13:
                depth, rgb = 4, (33,89,128)
            else:
                depth, rgb = 5, (26,69,108)
            # Large quiet patches rather than per-cell visual static.
            if depth >= 3 and n > 0.7:
                rgb = tuple(c+3 for c in rgb)
        pixels.append(entry(kind,depth,rgb))
    labels = [
        dict(text="NORTHERN OCEAN",x=112,y=9,major=True),
        dict(text="AZURE OCEAN",x=112,y=111,major=True),
        dict(text="EASTERN OCEAN",x=239,y=133,major=True),
        dict(text="Inner Sea",x=211,y=59),
        dict(text="Wanderers' Strait",x=185,y=79),
        dict(text="Wind Islands",x=143,y=84),
        dict(text="Coral Islands",x=170,y=151),
        dict(text="West Coast",x=41,y=91),
        dict(text="Quiet Lake",x=27,y=66),
        dict(text="Silver River",x=61,y=62),
    ]
    atlas = dict(version=1,seed=SEED,width=W,height=H,tileSize=TILE,
                 sectorSize=SECTOR,palette=palette,pixels=pixels,labels=labels)
    atlas["sha256"] = hashlib.sha256(bytes(pixels)).hexdigest()
    return atlas


def analyze(atlas):
    pixels, pal = atlas["pixels"], atlas["palette"]
    water = [pal[p-1]["water"] for p in pixels]
    basin, region = [0]*len(water), [0]*len(water)
    basin_sizes, regions = [], []
    for start,b in enumerate(water):
        if not b or basin[start]: continue
        bid, q, size = len(basin_sizes)+1, deque([start]), 0
        basin[start] = bid
        while q:
            i = q.popleft(); size += 1
            for j in neighbors(i):
                if water[j] and not basin[j]:
                    basin[j] = bid; q.append(j)
        basin_sizes.append(size)
    for start,b in enumerate(water):
        if not b or region[start]: continue
        rid, cells, q = len(regions)+1, [], deque([start])
        sx,sy = (start%W)//SECTOR,(start//W)//SECTOR
        region[start] = rid
        while q:
            i = q.popleft(); cells.append(i)
            for j in neighbors(i):
                if water[j] and not region[j] and (j%W)//SECTOR==sx and (j//W)//SECTOR==sy:
                    region[j]=rid; q.append(j)
        regions.append(cells)
    kinds = Counter(pal[p-1]["kind"] for p in pixels)
    stats = dict(cells=W*H,waterCells=sum(water),waterPercent=round(sum(water)/len(water)*100,1),
                 kinds=dict(kinds),sectors=len(regions),basins=len(basin_sizes),
                 basinSizes=basin_sizes,sha256=atlas["sha256"])
    return stats,region,basin


def rows(atlas):
    result = []
    for y in range(H):
        row, x = [], 0
        while x < W:
            p, end = atlas["pixels"][y*W+x], x+1
            while end < W and atlas["pixels"][y*W+end] == p: end += 1
            row.extend([end-x,p]); x=end
        result.append(row)
    return result


def lua(value):
    if isinstance(value,bool): return str(value).lower()
    if isinstance(value,str): return json.dumps(value,ensure_ascii=False)
    if isinstance(value,(int,float)): return str(value)
    if isinstance(value,list): return "{"+",".join(lua(v) for v in value)+"}"
    return "{"+",".join(k+"="+lua(v) for k,v in value.items())+"}"


def preview(atlas):
    image = Image.new("RGB",(W,H))
    image.putdata([tuple(atlas["palette"][p-1]["color"]) for p in atlas["pixels"]])
    scale=max(1,min(6,2048//W))
    image.resize((W*scale,H*scale),Image.Resampling.NEAREST).save(ROOT/"world-preview.png")


def hex_rows(values,digits=2):
    """One short string constant per row avoids Luau's constant-count limit."""
    result=[]
    for y in range(H):
        row=[];x=0
        while x<W:
            value=values[y*W+x];end=x+1
            while end<W and values[y*W+end]==value: end+=1
            row.append(f"{end-x:04x}{value:0{digits}x}");x=end
        result.append("".join(row))
    return result


def topology(atlas,region_ids,basin_ids):
    regions=[]
    for i,rid in enumerate(region_ids):
        if not rid: continue
        while len(regions)<rid:
            regions.append(dict(id=len(regions)+1,count=0,centerX=0,centerY=0,coastal=False,basinId=0,neighbors=set()))
        r=regions[rid-1];r["count"]+=1;r["centerX"]+=i%W+1;r["centerY"]+=i//W+1;r["basinId"]=basin_ids[i]
        for j in neighbors(i):
            if not region_ids[j]: r["coastal"]=True
            elif region_ids[j]!=rid: r["neighbors"].add(region_ids[j])
    for r in regions:
        r["centerX"]/=r["count"];r["centerY"]/=r["count"]
        r["neighbors"]=sorted(r["neighbors"])
    return regions


def overview_pixels(atlas):
    """Display-only LOD: fill river channels and remove their sandy banks.

    Geography, navigation and territory ownership always use canonical pixels.
    Oceans, seas and lakes keep their outlines in the overview.
    """
    pixels=atlas["pixels"];palette=atlas["palette"]
    if atlas.get("waterStyle")!="uniform-ocean": return pixels
    land=next(i for i,p in enumerate(palette,1) if p.get("biome")=="land")
    coast=next(i for i,p in enumerate(palette,1) if p.get("biome")=="coast")
    river={i for i,p in enumerate(palette,1) if p["kind"]=="river"}
    # Inherit nearby land/ice so northern channels do not become green stripes.
    fill={};q=deque()
    for i,p in enumerate(pixels):
        if p not in river: continue
        for j in neighbors(i):
            if not palette[pixels[j]-1]["water"]:
                fill[i]=land if pixels[j]==coast else pixels[j];q.append(i);break
    while q:
        i=q.popleft()
        for j in neighbors(i):
            if pixels[j] in river and j not in fill:
                fill[j]=fill[i];q.append(j)
    out=[fill.get(i,land) if p in river else land if p==coast else p for i,p in enumerate(pixels)]
    water=[p["water"] for p in palette]
    # Rebuild banks only along the water that remains visible at this LOD.
    for i,p in enumerate(out):
        if p==land and any(water[out[j]-1] for j in neighbors(i)): out[i]=coast
    return out


def render_rectangles(atlas,stride=1,pixels=None):
    """Greedy rectangle merge, including vertical neighbours of the same colour."""
    pixels=atlas["pixels"] if pixels is None else pixels;active={};result=[]
    canonical={};colors={}
    for i,p in enumerate(atlas["palette"],1):
        key=tuple(p["color"])
        colors[i]=canonical.setdefault(key,i)
    # A single logical strait cell must survive centre sampling of a 2x2 LOD.
    protected={}
    if stride>1:
        for passage in atlas.get('visiblePassages',[]):
            for i in passage['cells']:
                protected[((i%W)//stride,(i//W)//stride)]=pixels[i]
    def sample(x,y):
        p=protected.get((x//stride,y//stride),pixels[min(H-1,y+stride//2)*W+min(W-1,x+stride//2)])
        return colors[p]
    for y in range(0,H,stride):
        current={};x=0
        while x<W:
            p=sample(x,y)
            end=min(W,x+stride)
            while end<W and sample(end,y)==p:
                end=min(W,end+stride)
            key=x,end-x,p
            if key in active:
                rect=active.pop(key);rect[3]+=min(stride,H-y)
            else: rect=[x,y,end-x,min(stride,H-y),p]
            current[key]=rect;x=end
        result.extend(active.values());active=current
    result.extend(active.values())
    return result


def sector_boundaries(region_ids):
    edges=[]
    for y in range(H-1):
        x=0
        while x<W:
            a,b=region_ids[y*W+x],region_ids[(y+1)*W+x]
            if a and b and a!=b:
                start=x;x+=1
                while x<W and region_ids[y*W+x] and region_ids[(y+1)*W+x] and region_ids[y*W+x]!=region_ids[(y+1)*W+x]: x+=1
                edges.append([start,y+1,x-start,0])
            else: x+=1
    for x in range(W-1):
        y=0
        while y<H:
            a,b=region_ids[y*W+x],region_ids[y*W+x+1]
            if a and b and a!=b:
                start=y;y+=1
                while y<H and region_ids[y*W+x] and region_ids[y*W+x+1] and region_ids[y*W+x]!=region_ids[y*W+x+1]: y+=1
                edges.append([x+1,start,y-start,1])
            else: y+=1
    return edges


def build_place(atlas, rectangles, output):
    # Same root as a place saved by Studio; Open Cloud rejected the plain root with an XML declaration.
    root = ET.Element("roblox",{"xmlns:xmime":"http://www.w3.org/2005/05/xmlmime","xmlns:xsi":"http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation":"http://www.roblox.com/roblox.xsd","version":"4"})
    ET.SubElement(root,"External").text="null"
    ET.SubElement(root,"External").text="nil"
    serial = 0
    def item(cls, name, parent):
        nonlocal serial
        serial += 1
        obj = ET.SubElement(parent,"Item",{"class":cls,"referent":f"RBX{serial}"})
        props = ET.SubElement(obj,"Properties")
        ET.SubElement(props,"string",name="Name").text=name
        return obj,props
    def prop(props,tag,name,value):
        ET.SubElement(props,tag,name=name).text=str(value).lower() if isinstance(value,bool) else str(value)
    def vector(props,tag,name,values):
        e = ET.SubElement(props,tag,name=name)
        for k,v in zip(("R","G","B") if tag=="Color3" else ("X","Y","Z"),values):
            ET.SubElement(e,k).text=str(v)
    def cframe(props,name,pos,rotation=(1,0,0,0,1,0,0,0,1)):
        e=ET.SubElement(props,"CoordinateFrame",name=name)
        for k,v in zip(["X","Y","Z","R00","R01","R02","R10","R11","R12","R20","R21","R22"],list(pos)+list(rotation)):
            ET.SubElement(e,k).text=str(v)
    workspace,wp=item("Workspace","Workspace",root)
    prop(wp,"bool","StreamingEnabled",False)
    camera,cp=item("Camera","Camera",workspace)
    prop(cp,"token","CameraType",6)
    prop(cp,"float","FieldOfView",45)
    camera_height=max(H*TILE/2,W*TILE/3.2)*1.08/math.tan(math.radians(22.5))
    cframe(cp,"CFrame",(0,camera_height,0),(1,0,0,0,0,1,0,-1,0))
    prop(wp,"Ref","CurrentCamera",camera.attrib["referent"])
    world,_=item("Model","SeaBattleWorld",workspace)
    _,bp=item("Part","OceanBackdrop",workspace)
    for key,val in {"Anchored":True,"CanCollide":False,"CanTouch":False,"CanQuery":False,"CastShadow":False}.items():
        prop(bp,"bool",key,val)
    # Locked: Studio cannot select or drag it with the mouse (a stray drag once shifted the whole map).
    prop(bp,"bool","Locked",True)
    vector(bp,"Vector3","size",(8000,.2,8000))
    cframe(bp,"CFrame",(0,-.3,0))
    vector(bp,"Color3","Color",[c/255 for c in atlas.get("uniformWaterColor",[26,69,108])])
    prop(bp,"token","Material",256)
    prop(bp,"token","TopSurface",0)
    prop(bp,"token","BottomSurface",0)
    for index,(x,y,n,rows_high,p) in enumerate(rectangles):
            if index%256==0: folder,_=item("Folder",f"Chunk{index//256:04}",world)
            part,pp=item("Part",f"T{x}_{y}",folder)
            prop(pp,"bool","Anchored",True)
            prop(pp,"bool","CanCollide",False)
            prop(pp,"bool","CanTouch",False)
            prop(pp,"bool","CanQuery",True)
            prop(pp,"bool","CastShadow",False)
            prop(pp,"bool","Locked",True)
            prop(pp,"token","Material",256)
            prop(pp,"token","TopSurface",0)
            prop(pp,"token","BottomSurface",0)
            vector(pp,"Vector3","size",(n*TILE,.01,rows_high*TILE))
            cframe(pp,"CFrame",((x+n/2-W/2)*TILE,0,(y+rows_high/2-H/2)*TILE))
            vector(pp,"Color3","Color",[c/255 for c in atlas["palette"][p-1]["color"]])
    lighting,lp=item("Lighting","Lighting",root)
    prop(lp,"float","Brightness",0)
    prop(lp,"bool","GlobalShadows",False)
    vector(lp,"Color3","Ambient",(1,1,1))
    vector(lp,"Color3","OutdoorAmbient",(1,1,1))
    prop(lp,"float","EnvironmentDiffuseScale",0)
    prop(lp,"float","EnvironmentSpecularScale",0)
    prop(lp,"float","FogEnd",100000)
    prop(lp,"float","ExposureCompensation",0)
    players,pp=item("Players","Players",root)
    prop(pp,"bool","CharacterAutoLoads",False)
    # No way to talk in the game (2026-11-12, the author's decision): no text chat (no default channels,
    # commands, window, input bar or bubbles) and no default voice. The server also refuses to deliver any
    # message and removes voice inputs (server/NoTalk); the experience's Communication settings stay as they are.
    tcs,tp=item("TextChatService","TextChatService",root)
    prop(tp,"token","ChatVersion",1)
    prop(tp,"bool","CreateDefaultTextChannels",False)
    prop(tp,"bool","CreateDefaultCommands",False)
    for cls in ("ChatWindowConfiguration","ChatInputBarConfiguration","BubbleChatConfiguration"):
        _,cp=item(cls,cls,tcs)
        prop(cp,"bool","Enabled",False)
    # (and the old chat system off too, in case a server still runs it)
    _,lc=item("Chat","Chat",root)
    prop(lc,"bool","LoadDefaultChat",False)
    prop(lc,"bool","BubbleChatEnabled",False)
    _,vp=item("VoiceChatService","VoiceChatService",root)
    prop(vp,"bool","EnableDefaultVoice",False)
    rs,_=item("ReplicatedStorage","ReplicatedStorage",root)
    shared,_=item("Folder","SeaBattle",rs)
    for path in sorted((ROOT/"src"/"shared").glob("*.luau")):
        _,sp=item("ModuleScript",path.stem,shared)
        prop(sp,"ProtectedString","Source",path.read_text())
    # The match simulation: the server's real match and each client's demo behind the lobby.
    sim,_=item("Folder","Sim",shared)
    for path in sorted((ROOT/"src"/"sim").glob("*.luau")):
        _,sp=item("ModuleScript",path.stem,sim)
        prop(sp,"ProtectedString","Source",path.read_text())
    ss,_=item("ServerScriptService","ServerScriptService",root)
    for path in sorted((ROOT/"src"/"server").glob("*.luau")):
        cls="Script" if path.name.endswith(".server.luau") else "ModuleScript"
        _,sp=item(cls,path.name.replace(".server.luau","").replace(".luau",""),ss)
        prop(sp,"ProtectedString","Source",path.read_text())
    # The splash screen runs first, before the map and the game scripts arrive.
    first,_=item("ReplicatedFirst","ReplicatedFirst",root)
    for path in sorted((ROOT/"src"/"first").glob("*.luau")):
        _,sp=item("LocalScript",path.name.replace(".client.luau",""),first)
        prop(sp,"ProtectedString","Source",path.read_text())
    starter,_=item("StarterPlayer","StarterPlayer",root)
    scripts,_=item("StarterPlayerScripts","StarterPlayerScripts",starter)
    for path in sorted((ROOT/"src"/"client").glob("*.luau")):
        _,sp=item("LocalScript",path.name.replace(".client.luau",""),scripts)
        prop(sp,"ProtectedString","Source",path.read_text())
    tests,_=item("ServerStorage","ServerStorage",root)
    for path in sorted((ROOT/"tests").glob("*.luau")):
        _,sp=item("ModuleScript",path.stem,tests)
        prop(sp,"ProtectedString","Source",path.read_text())
    ET.ElementTree(root).write(output,encoding="utf-8",xml_declaration=False)
    return serial


def main():
    global W,H,TILE,SECTOR,WRAP
    parser=argparse.ArgumentParser()
    parser.add_argument("--map",choices=["earth","first-expedition"],default="earth")
    parser.add_argument("--refresh-geography",action="store_true")
    args=parser.parse_args()
    for folder in ["src/shared","src/sim","src/server","src/client","tests","data"]:
        (ROOT/folder).mkdir(parents=True,exist_ok=True)
    if args.map=="earth":
        cached=ROOT/"maps/earth/world.json"
        if cached.exists() and not args.refresh_geography: atlas=json.loads(cached.read_text())
        else:
            from build_earth import make_atlas as earth_atlas
            atlas=earth_atlas()
            cached.parent.mkdir(parents=True,exist_ok=True)
            cached.write_text(json.dumps(atlas,ensure_ascii=False,separators=(",",":")))
        from passages import connect_turkish_straits
        from appearance import apply_earth_colors
        atlas["wrapX"]=False
        atlas=connect_turkish_straits(atlas)
        from user_rivers import connect_user_rivers
        atlas=connect_user_rivers(atlas)
        from ocean_starts import add_ocean_starts
        atlas=add_ocean_starts(atlas)
        atlas=apply_earth_colors(atlas)
        cached.write_text(json.dumps(atlas,ensure_ascii=False,separators=(",",":")))
        output=ROOT/"SeaBattle_Earth.rbxlx"
    else:
        atlas=json.loads((ROOT/"maps/first-expedition/data/world.json").read_text())
        atlas.update(id="first-expedition",name="First Expedition",version=2,wrapX=False)
        output=ROOT/"SeaBattle_FirstExpedition.rbxlx"
    W,H,TILE,SECTOR,WRAP=atlas["width"],atlas["height"],atlas["tileSize"],atlas["sectorSize"],atlas.get("wrapX",False)
    print(f"Analyzing {W}x{H} cells",flush=True)
    stats,region_ids,basin_ids=analyze(atlas)
    stride=2 if W>512 else 1
    overview=overview_pixels(atlas) if stride>1 else atlas["pixels"]
    display_atlas=atlas
    distant=overview
    if args.map=="earth":
        from appearance import make_display_layers
        display_palette,detailed,distant,appearance_source=make_display_layers(atlas,overview)
        display_atlas={**atlas,"palette":display_palette,"pixels":detailed}
    rectangles=render_rectangles(display_atlas,stride,distant)
    data={k:v for k,v in atlas.items() if k != "pixels"}
    data["rows"]=hex_rows(atlas["pixels"])
    if args.map=="earth":
        data["displayPalette"]=display_palette
        data["displayRows"]=hex_rows(detailed)
        data["appearanceSource"]=appearance_source
    data["regionRows"]=hex_rows(region_ids,4)
    data["basinRows"]=hex_rows(basin_ids,4)
    data["regions"]=topology(atlas,region_ids,basin_ids)
    data["boundaries"]=sector_boundaries(region_ids)
    data["overviewStride"]=stride
    data["detailZoom"]=.38
    data["overviewHidesRivers"]=overview is not atlas["pixels"]
    data["minZoom"]=.02 if W>512 else .08
    data["stats"]=stats
    stats["renderParts"]=len(rectangles)
    stats["overviewStride"]=stride
    runtime=json.dumps(data,ensure_ascii=False,separators=(",",":"))
    (ROOT/"data/world-runtime.json").write_text(runtime)
    for path in (ROOT/"src/shared").glob("WorldDataChunk*.luau"): path.unlink()
    names=[]
    for index,start in enumerate(range(0,len(runtime),60000),1):
        name=f"WorldDataChunk{index:03}";names.append(name)
        (ROOT/"src/shared"/(name+".luau")).write_text("return "+json.dumps(runtime[start:start+60000],ensure_ascii=False)+"\n")
    loader="-- Generated in chunks to support Studio's Source property limit.\nlocal parts={"+",".join("require(script.Parent."+n+")" for n in names)+"}\nreturn game:GetService('HttpService'):JSONDecode(table.concat(parts))\n"
    (ROOT/"src/shared/WorldData.luau").write_text(loader)
    (ROOT/"data/world.json").write_text(json.dumps(atlas,ensure_ascii=False,separators=(",",":")))
    (ROOT/"data/world-stats.json").write_text(json.dumps(stats,ensure_ascii=False,indent=2)+"\n")
    preview(display_atlas)
    # Preview uses the same display-only raster as the place.
    overview_image=Image.new("RGB",(W,H))
    overview_image.putdata([tuple(display_atlas["palette"][p-1]["color"]) for p in distant])
    overview_image.save(ROOT/"world-overview-preview.png")
    stats["instances"]=build_place(display_atlas,rectangles,output)
    stats["place"]=output.name
    if args.map=="earth":
        (ROOT/"maps/earth/world-stats.json").write_text(json.dumps(stats,ensure_ascii=False,indent=2)+"\n")
        (ROOT/"maps/earth/preview.png").write_bytes((ROOT/"world-preview.png").read_bytes())
    print(json.dumps({k:v for k,v in stats.items() if k!="basinSizes"},ensure_ascii=False,indent=2))


if __name__ == "__main__":
    main()
