"""Author-requested game rivers; coordinates are (latitude, longitude), bounded map."""
import hashlib
from simplify_earth import components

CONNECTIONS=[
    dict(id='user-river-1',requested=[(8.38,-61.88),(9.88,-60.12)]),
    dict(id='user-river-2',requested=[(8.88,-67.62),(10.88,-67.38)]),
    # The two screenshots identify the short break north of the numerical points.
    # Join the actual river tips, rather than carving a dead-end branch in land.
    dict(id='user-river-3',requested=[(.88,-76.63),(.12,-76.63)],
         route=[(1.875,-76.625),(1.125,-76.625)],reference='Two author screenshots, 2026-11-01 21:20:47/50'),
    dict(id='user-river-4',requested=[(6.12,-79.12),(10.38,-79.12)]),
    # Complete the two-cell shoreline join at the northern end, within the right edge.
    dict(id='user-river-5',requested=[(63.12,179.62),(68.88,179.62)],
         route=[(63.12,179.62),(68.88,179.62),(69.38,179.62)]),
    # The screenshot HUD latitude is displaced from the visible cursor by the
    # screen inset. Routes use the actual river tips / coast shown in each pair.
    dict(id='user-river-6',requested=[(-17.88,-71.62),(-20.13,-73.38)],
         route=[(-15.375,-71.625),(-17.875,-73.375)],
         reference='Author screenshots 2026-11-01 21:56:19/24'),
    dict(id='user-river-7',requested=[(-11.88,-76.63),(-14.63,-78.12)],
         route=[(-9.875,-76.625),(-12.375,-78.125)],
         reference='Author screenshots 2026-11-01 21:56:30/36'),
    dict(id='user-river-8',requested=[(-5.38,-49.62),(-1.88,-46.62)],
         route=[(-2.625,-49.625),(.625,-46.625)],
         reference='Author screenshots 2026-11-01 21:56:44/50'),
    dict(id='user-river-9',requested=[(58.62,-138.62),(55.88,-138.38)],
         route=[(61.125,-138.625),(58.375,-138.375)],
         reference='Author screenshots 2026-11-01 21:57:36/43'),
    dict(id='user-river-10',requested=[(58.12,-161.88),(56.38,-162.88)],
         route=[(60.625,-161.875),(58.875,-162.875)],
         reference='Author screenshots 2026-11-01 21:57:48/53'),
]

def path_cells(points,w,h):
    result=[];seen=set()
    def add(x,y):
        assert 0<=x<w and 0<=y<h,'River leaves map boundaries'
        i=y*w+x
        if i not in seen: result.append(i);seen.add(i)
    for (alat,alon),(blat,blon) in zip(points,points[1:]):
        ax,ay=(alon+180)*w/360,(90-alat)*h/180
        bx,by=(blon+180)*w/360,(90-blat)*h/180
        steps=max(1,int(max(abs(bx-ax),abs(by-ay))*4)+1);previous=None
        for k in range(steps+1):
            x,y=int(ax+(bx-ax)*k/steps),int(ay+(by-ay)*k/steps)
            if previous and previous[0]!=x and previous[1]!=y: add(x,previous[1])
            add(x,y);previous=x,y
    return result

def connect_user_rivers(atlas):
    w,h=atlas['width'],atlas['height'];pixels=atlas['pixels'];palette=atlas['palette']
    river=next(i for i,p in enumerate(palette,1) if p['kind']=='river')
    sea=next(i for i,p in enumerate(palette,1) if p['kind']=='sea')
    land=next(i for i,p in enumerate(palette,1) if p.get('biome')=='land')
    coast=next(i for i,p in enumerate(palette,1) if p.get('biome')=='coast')
    connections=[]
    for source in CONNECTIONS:
        route=source.get('route',source['requested']);cells=path_cells(route,w,h)
        for i in cells:
            if not palette[pixels[i]-1]['water']: pixels[i]=river
        record=dict(id=source['id'],requestedEndpoints=source['requested'],route=route,cells=cells,widthPixels=1)
        if source.get('reference'): record['reference']=source['reference']
        connections.append(record)
    water=bytearray(palette[p-1]['water'] for p in pixels)
    # Keep the existing minimum island size after waterways split land components.
    for cells in components(water,w,h,0,atlas.get('wrapX',False)):
        if len(cells)<10:
            for i in cells: pixels[i]=sea;water[i]=1
    for i,p in enumerate(pixels):
        if p not in (land,coast): continue
        x=i%w;ns=(i-1 if x else -1,i+1 if x<w-1 else -1,i-w,i+w)
        pixels[i]=coast if any(0<=j<w*h and water[j] for j in ns) else land
    atlas['riverConnections']=connections
    atlas['sha256']=hashlib.sha256(bytes(pixels)).hexdigest()
    return atlas
