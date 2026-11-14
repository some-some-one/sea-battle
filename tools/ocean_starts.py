"""Ten author-requested gameplay islands and two Antarctic coastal starts.

These artificial islands are an explicit game overlay, separate from Natural
Earth source data. All cell indices in saved metadata are zero based.
"""
import hashlib

ISLANDS = [
    ('pacific-hawaii', 'Hawaii', -150, 28, 5, 4),
    ('pacific-kiribati', 'Kiribati', -165, 0, 5, 3),
    ('pacific-polynesia', 'French Polynesia', -140, -32, 5, 4),
    ('pacific-easter', 'Easter Island', -108, -25, 4, 4),
    ('pacific-marshall', 'Marshall Islands', 164, 22, 4, 3),
    ('atlantic-azores', 'Azores', -38, 30, 5, 4),
    ('atlantic-helena', 'Saint Helena', -20, -26, 4, 4),
    ('indian-seychelles', 'Seychelles', 64, -8, 5, 3),
    ('indian-amsterdam', 'Amsterdam Island', 86, -34, 5, 4),
    ('arctic-franz', 'Franz Josef Land', 75, 84, 4, 3),
]
POLAR = [
    ('antarctica-west', 'West Antarctica', -58, -66),
    ('antarctica-east', 'Antarctica', 93, -67),
]

def add_ocean_starts(atlas):
    w,h=atlas['width'],atlas['height'];pixels=atlas['pixels'];palette=atlas['palette']
    land=next(i for i,p in enumerate(palette,1) if p.get('biome')=='land')
    coast=next(i for i,p in enumerate(palette,1) if p.get('biome')=='coast')
    def neighbors(i):
        x,y=i%w,i//w
        return [j for j,ok in ((i-1,x>0),(i+1,x<w-1),(i-w,y>0),(i+w,y<h-1)) if ok]
    def sea(i): return palette[pixels[i]-1]['kind'] in ('sea','ocean')
    def cell(lon,lat): return int((lon+180)*w/360),int((90-lat)*h/180)
    previous={i for site in atlas.get('spawnSites',[]) if site['kind']=='island' for i in site['landCells']}
    sites=[]
    for sid,name,lon,lat,rx,ry in ISLANDS:
        cx,cy=cell(lon,lat);cells=[]
        for dy in range(-ry,ry+1):
            for dx in range(-rx,rx+1):
                # Broad asymmetric shore; deterministic, without single-cell specks.
                if ((dx+.15*dy)/rx)**2+(dy/ry)**2>1: continue
                x,y=cx+dx,cy+dy
                assert 2<=x<w-2 and 2<=y<h-2, 'Island crosses map edge'
                i=y*w+x
                assert sea(i) or i in previous, 'Island overlaps existing land/river'
                cells.append(i)
        assert len(cells)>=10
        for i in cells: pixels[i]=land
        sites.append(dict(id=sid,name=name,kind='island',longitude=lon,latitude=lat,
                          artificial=True,landCells=sorted(cells)))
    # Rebuild decorative logical banks after the new land has been drawn.
    for i,p in enumerate(pixels):
        if p in (land,coast):
            pixels[i]=coast if any(palette[pixels[j]-1]['water'] for j in neighbors(i)) else land
    for site in sites:
        ports={j for i in site['landCells'] for j in neighbors(i) if sea(j)}
        assert ports, 'Gameplay island lacks a sea coast'
        site['coastCells']=sorted(ports)
    polar_coast=[i for i,p in enumerate(pixels)
                 if i//w>h*5/6 and palette[p-1]['kind'] in ('sea','ocean')
                 and any(not palette[pixels[j]-1]['water'] for j in neighbors(i))]
    for sid,name,lon,lat in POLAR:
        ax,ay=cell(lon,lat)
        nearest=min(polar_coast,key=lambda i:(i%w-ax)**2+(i//w-ay)**2)
        cx,cy=nearest%w,nearest//w
        ports=[i for i in polar_coast if (i%w-cx)**2+(i//w-cy)**2<=64]
        sites.append(dict(id=sid,name=name,kind='antarctica',longitude=lon,latitude=lat,coastCells=ports))
    atlas['spawnSites']=sites
    atlas['gameplayIslands']=dict(count=10,artificial=True,source='Author request, 2026-11-01')
    atlas['sha256']=hashlib.sha256(bytes(pixels)).hexdigest()
    return atlas
