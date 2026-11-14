"""Offline display colours; never edit geography, depth or ownership."""
from collections import deque
from pathlib import Path
import hashlib
import zipfile
from PIL import Image,ImageFilter

WATER=[78,134,212]
LAND=[102,151,98]

def apply_earth_colors(atlas):
    for entry in atlas['palette']:
        if entry['water']: entry['color']=WATER.copy()
        elif entry.get('biome')=='land': entry['color']=LAND.copy()
    atlas['uniformWaterColor']=WATER.copy()
    atlas['limitations']=[
        'Water has one logical depth; decorative coast colours have no gameplay properties.'
        if line.startswith('Water is a single depth and RGB(') else line
        for line in atlas.get('limitations',[])]
    return atlas

# The archive's checksum, fixed: the build works from the cached 1440x720 colours alone (the 41 MB
# archive is needed only to make that cache again).
RELIEF_SHA256='ae930744c0cf3d10e73c292726b74c81a40490a75829f8299dec9069e5d0e934'

def make_display_layers(atlas,overview):
    w,h=atlas['width'],atlas['height'];pixels=atlas['pixels'];logical=atlas['palette'];wrap=atlas.get('wrapX',False)
    archive=Path(__file__).resolve().parents[1]/'data/source/natural-earth/NE1_50M_SR.zip'
    cache=archive.parent/'relief-colors-1440.png'
    if cache.exists(): source=Image.open(cache).convert('RGB')
    else:
        with zipfile.ZipFile(archive) as z:
            path=next(n for n in z.namelist() if n.lower().endswith('.tif'))
            with Image.open(z.open(path)) as im:
                source=im.convert('RGB').resize((w,h),Image.Resampling.BOX)
        source.save(cache)
    # Broad colour regions; no noise, dithering or runtime terrain generation.
    source=source.resize((w//4,h//4),Image.Resampling.BOX).filter(ImageFilter.MedianFilter(3))
    reference=[(162,190,163),(187,207,169),(214,222,178),(226,228,190),
               (242,231,202),(230,213,183),(218,193,170),
               (200,200,187),(219,220,209),(237,241,243)]
    terrain=[(76,132,86),(102,151,98),(133,164,107),(166,179,119),
             (215,191,137),(197,170,119),(174,147,112),
             (145,147,126),(177,177,152),(193,186,157)]
    palette_image=Image.new('P',(1,1))
    # Pad using the final colour; arbitrary black padding must not win sampling.
    palette_image.putpalette([v for c in reference+[reference[-1]]*(256-len(reference)) for v in c])
    classified=source.quantize(palette=palette_image,dither=Image.Dither.NONE)
    terrain_ids=classified.resize((w,h),Image.Resampling.NEAREST).tobytes()
    display_palette=[dict(color=WATER,water=True,name='open-water'),
                     dict(color=[86,144,217],water=True,name='coastal-water'),
                     dict(color=[96,156,222],water=True,name='shore-water')]
    display_palette += [dict(color=list(c),water=False,name='terrain-'+str(i)) for i,c in enumerate(terrain)]
    ice_id=len(display_palette)+1
    display_palette.append(dict(color=[221,233,232],water=False,name='ice'))
    island_cells={i for site in atlas.get('spawnSites',[]) if site['kind']=='island' for i in site['landCells']}
    # Distance to continental land, treating hidden river channels as land.
    # Two discrete light bands decorate sea water; no depth data is generated.
    distance=bytearray([255])*(w*h);q=deque()
    for i,p in enumerate(pixels):
        if not logical[p-1]['water'] or logical[p-1]['kind']=='river': distance[i]=0
    for i,d in enumerate(distance):
        if d!=255: continue
        x=i%w
        if any(0<=j<w*h and distance[j]==0 for j in ((i-1 if x else i+w-1 if wrap else -1),(i+1 if x<w-1 else i-w+1 if wrap else -1),i-w,i+w)):
            distance[i]=1;q.append(i)
    while q:
        i=q.popleft()
        if distance[i]>=5: continue
        x=i%w
        for j in ((i-1 if x else i+w-1 if wrap else -1),(i+1 if x<w-1 else i-w+1 if wrap else -1),i-w,i+w):
            if 0<=j<w*h and distance[j]==255: distance[j]=distance[i]+1;q.append(j)
    def layer(mask):
        out=bytearray(w*h)
        for i,p in enumerate(mask):
            entry=logical[p-1]
            if entry['water']:
                d=distance[i]
                out[i]=3 if entry['kind'] in ('ocean','sea') and 0<d<=2 else 2 if entry['kind'] in ('ocean','sea') and d<=5 else 1
            else:
                if i in island_cells:
                    # Real relief data contains ocean here. Give the new gameplay
                    # islands sandy shores and green centres (polar island is ice).
                    out[i]=ice_id if i//w<h*.1 else 8 if entry.get('biome')=='coast' else 5
                else:
                    out[i]=ice_id if entry.get('biome')=='ice' else 4+min(terrain_ids[i],len(terrain)-1)
        return list(out)
    detailed=layer(pixels);distant=layer(overview)
    assert all(display_palette[p-1]['water']==logical[pixels[i]-1]['water'] for i,p in enumerate(detailed))
    return display_palette,detailed,distant,dict(
        name='Natural Earth I with Shaded Relief, 1:50m',version='3.2.0',
        url='https://naturalearth.s3.amazonaws.com/50m_raster/NE1_50M_SR.zip',
        sha256=RELIEF_SHA256,decorativeOnly=True)
