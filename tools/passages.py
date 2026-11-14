"""Keep author-requested narrow sea passages navigable at every display LOD."""
import hashlib
from simplify_earth import components

def connect_turkish_straits(atlas):
    w,h=atlas['width'],atlas['height'];pixels=atlas['pixels'];palette=atlas['palette']
    sea=next(i for i,p in enumerate(palette,1) if p['kind']=='sea')
    land=next(i for i,p in enumerate(palette,1) if p.get('biome')=='land')
    coast=next(i for i,p in enumerate(palette,1) if p.get('biome')=='coast')
    # Approximate geographic centre line; a minimum one-cell game passage.
    route=[(29.3,41.5),(29.1,41.25),(29.0,41.0),(28.8,40.9),
           (28.0,40.8),(27.3,40.65),(26.7,40.45),(26.4,40.2),
           (26.15,40.0),(25.7,39.8),(25.5,39.3)]
    cells=set()
    for (al,at),(bl,bt) in zip(route,route[1:]):
        ax,ay=(al+180)*w/360,(90-at)*h/180
        bx,by=(bl+180)*w/360,(90-bt)*h/180
        steps=max(1,int(max(abs(bx-ax),abs(by-ay))*4)+1);previous=None
        for k in range(steps+1):
            x,y=int(ax+(bx-ax)*k/steps),int(ay+(by-ay)*k/steps)
            cells.add(y*w+x)
            if previous and previous[0]!=x and previous[1]!=y: cells.add(previous[1]*w+x)
            previous=x,y
    for i in cells: pixels[i]=sea
    water=bytearray(palette[p-1]['water'] for p in pixels)
    wrap=atlas.get('wrapX',False)
    for group in components(water,w,h,0,wrap):
        if len(group)<10:
            for i in group: pixels[i]=sea;water[i]=1
    for i,p in enumerate(pixels):
        if p not in (land,coast): continue
        x=i%w
        ns=((i-1 if x else i+w-1 if wrap else -1),(i+1 if x<w-1 else i-w+1 if wrap else -1),i-w,i+w)
        pixels[i]=coast if any(0<=j<w*h and water[j] for j in ns) else land
    atlas['visiblePassages']=[dict(id='turkish-straits',name='Bosporus — Sea of Marmara — Dardanelles',cells=sorted(cells))]
    atlas['sha256']=hashlib.sha256(bytes(pixels)).hexdigest()
    return atlas
