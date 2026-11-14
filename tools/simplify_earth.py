"""User-requested ocean-only map cleanup; 4-neighbour components, periodic X."""
from collections import deque, Counter
import hashlib
import json
from pathlib import Path
from array import array

def components(mask,w,h,value,wrap=True):
    seen=bytearray(w*h)
    for start in range(w*h):
        if seen[start] or mask[start]!=value: continue
        seen[start]=1;q=deque([start]);cells=[]
        while q:
            i=q.popleft();cells.append(i);x=i%w
            for j in ((i-1 if x else i+w-1 if wrap else -1),(i+1 if x<w-1 else i-w+1 if wrap else -1),i-w,i+w):
                if 0<=j<w*h and not seen[j] and mask[j]==value:
                    seen[j]=1;q.append(j)
        yield cells

def simplify(atlas):
    w,h=atlas['width'],atlas['height'];old=atlas['palette'];pixels=atlas['pixels']
    water=bytearray(old[p-1]['water'] for p in pixels)
    # The detailed atlas as build_earth made it, before this pass (its closed watersheds).
    base=bytearray(water)
    # Caspian is naturally endorheic. Coarse raster contacts / artificial canal
    # links must not turn its original closed watershed into an ocean outlet.
    caspian=int((90-42)*h/180)*w+int((51+180)*w/360)
    for cells in components(base,w,h,1):
        if caspian in cells:
            for i in cells: water[i]=0
            break
    groups=list(components(water,w,h,1));ocean=max(groups,key=len)
    keep=bytearray(w*h)
    for i in ocean: keep[i]=1
    removed_water=sum(water)-len(ocean)
    # Use the full source river network to identify outlets, but retain the
    # original map's detail level plus just the channels needed to connect it.
    base_groups=list(components(base,w,h,1));base_ocean=max(base_groups,key=len)
    connected=bytearray(w*h);parents=array('I',[0])*(w*h);q=deque(base_ocean)
    for i in base_ocean: connected[i]=1;parents[i]=i+1
    while q:
        i=q.popleft();x=i%w
        for j in ((i-1 if x else i+w-1),(i+1 if x<w-1 else i-w+1),i-w,i+w):
            if 0<=j<w*h and keep[j] and not parents[j]: parents[j]=i+1;q.append(j)
    for cells in base_groups:
        candidates=[i for i in cells if keep[i]]
        if not candidates: continue
        i=candidates[0]
        while not connected[i]:
            connected[i]=1;i=parents[i]-1
            assert i>=0,'Missing outlet path'
        for i in candidates: connected[i]=1
    water=connected
    removed_land=0;land_components=0
    for cells in components(water,w,h,0):
        if len(cells)<10:
            removed_land+=len(cells);land_components+=1
            for i in cells: water[i]=1
    # Final water pass also enforces the explicit 5-cell threshold.
    for cells in components(water,w,h,1):
        if len(cells)<5:
            for i in cells: water[i]=0
    palette=[dict(kind='ocean',depth=1,color=[90,177,177],water=True,biome='water'),
        dict(kind='sea',depth=1,color=[90,177,177],water=True,biome='water'),
        dict(kind='land',depth=0,color=[136,173,123],water=False,biome='land'),
        dict(kind='land',depth=0,color=[207,195,145],water=False,biome='coast'),
        dict(kind='land',depth=0,color=[206,221,211],water=False,biome='ice'),
        dict(kind='river',depth=1,color=[90,177,177],water=True,biome='water'),
        dict(kind='lake',depth=1,color=[90,177,177],water=True,biome='water')]
    out=bytearray(w*h)
    for i in range(w*h):
        previous=old[pixels[i]-1]
        if water[i]: out[i]={'sea':2,'river':6,'lake':7}.get(previous['kind'],1)
        else:
            x=i%w
            coastal=any(water[j] for j in ((i-1 if x else i+w-1),(i+1 if x<w-1 else i-w+1),max(0,i-w),min(w*h-1,i+w)))
            out[i]=5 if previous.get('biome')=='ice' else 4 if coastal else 3
    atlas['palette']=palette;atlas['pixels']=list(out)
    atlas['sha256']=hashlib.sha256(out).hexdigest()
    atlas['waterStyle']='uniform-ocean';atlas['uniformWaterColor']=[90,177,177]
    atlas['cleanup']=dict(minWaterPixels=5,minLandPixels=10,allRiversRemoved=False,
        oceanConnectedOnly=True,removedInlandWaterCells=removed_water,
        removedRiverCells=sum(old[p-1]['kind']=='river' and not water[i] for i,p in enumerate(pixels)),
        removedSmallLandCells=removed_land,removedSmallLandComponents=land_components)
    removed_names={'Caspian Sea','Lake Baikal','Great Lakes','Lake Victoria','Amazon','Nile','Mississippi','Yangtze','Volga','Ob'}
    atlas['labels']=[l for l in atlas['labels'] if l['text'] not in removed_names or water[min(h-1,max(0,int(l['y']+.5)))*w+min(w-1,max(0,int(l['x']+.5)))]]
    atlas['limitations']=['Simplified 0.25-degree Earth raster.',
        'Only ocean-disconnected rivers and water bodies removed by author request.',
        'Water is a single depth and RGB(90,177,177); bathymetry is not used.',
        'Land components smaller than 10 cells and water components smaller than 5 cells removed.']
    from appearance import apply_earth_colors
    return apply_earth_colors(atlas)
