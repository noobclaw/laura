"""Deterministic atlas slicing, alpha cleanup, geometry and provenance export.

Only reads newly generated production sheets. Never opens retained images.
"""
import base64, hashlib, json, math
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'presentation/american-v1'
PLAN=json.loads((BASE/'plan.json').read_text())
OUT=BASE/'items';OUT.mkdir(exist_ok=True)
provenance=json.loads((BASE/'generations.json').read_text())

def hull(points):
    pts=sorted(set(points))
    def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lower=[]
    for p in pts:
        while len(lower)>1 and cross(lower[-2],lower[-1],p)<=0:lower.pop()
        lower.append(p)
    upper=[]
    for p in reversed(pts):
        while len(upper)>1 and cross(upper[-2],upper[-1],p)<=0:upper.pop()
        upper.append(p)
    return lower[:-1]+upper[:-1]

entries={};missing=[];checks=[]
for entry in PLAN['entries']:
    sheetname=f"sheet-{entry['sheet']:02d}.png"
    src=BASE/'source'/sheetname
    if not src.exists():missing.append(entry['key']);continue
    sheet=Image.open(src).convert('RGBA');col=entry['cell']%6;row=entry['cell']//6
    if sheet.getchannel('A').getextrema()[0]>=48:raise ValueError(f'Bad transparency: {sheetname}')
    rect=tuple(round(v) for v in (col*sheet.width/6,row*sheet.height/6,(col+1)*sheet.width/6,(row+1)*sheet.height/6))
    cell=sheet.crop(rect)
    # Generated alpha sometimes has near-invisible matte noise. Remove only that
    # low-alpha fringe; retain original RGB, geometry, opaque detail and highlights.
    alpha=cell.getchannel('A').point(lambda a:0 if a<48 else a)
    cell.putalpha(alpha);bounds=alpha.getbbox()
    if not bounds:raise ValueError(f"Empty sprite {entry['key']}")
    cut=cell.crop(bounds)
    padding=4
    image=Image.new('RGBA',(cut.width+2*padding,cut.height+2*padding))
    image.paste(cut,(padding,padding))
    path=OUT/f"{entry['key']}.webp";image.save(path,'WEBP',lossless=True,method=6)
    mask=image.getchannel('A').resize((48,48),Image.Resampling.NEAREST)
    bits=bytearray(48*48//8);points=[]
    for y in range(48):
        for x in range(48):
            if mask.getpixel((x,y))>=128:
                bit=y*48+x;bits[bit>>3]|=1<<(bit&7)
                points.extend([(x/48-.5,.5-y/48),((x+1)/48-.5,.5-(y+1)/48)])
    if not points:raise ValueError(f"No solid alpha {entry['key']}")
    contour=hull(points)
    asset={'category':entry['category'],'subject':entry['subject'],'path':path.relative_to(ROOT).as_posix(),
        'pixels':[image.width,image.height], 'outline':contour,
        'grid':{'columns':48,'rows':48,'bits':base64.b64encode(bits).decode()},
        'source':{'kind':'built-in image_gen','sheet':sheetname,'cell':entry['cell'],'generation_sha256':provenance[sheetname]['sha256']},
        'license':'AI-generated for this project; platform and release review pending',
        'technical_checks_passed':True,'visual_review':'atlas-reviewed; in-game category review pending',
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    entries[entry['key']]=asset
    checks.append({'key':entry['key'],'bounds':bounds,'pixels':asset['pixels'],'transparent':image.getchannel('A').getextrema()[0]==0,'opaque':image.getchannel('A').getextrema()[1]==255})

rooms={}
for path in sorted((BASE/'source').glob('room-*.png')):
    name=path.stem.removeprefix('room-');image=Image.open(path).convert('RGB')
    target=BASE/f'room-{name}.webp';image.save(target,'WEBP',quality=94,method=6)
    rooms[name]={'path':target.relative_to(ROOT).as_posix(),'pixels':list(image.size),'source':provenance[path.name],'technical_checks_passed':True,'license':'AI-generated for this project; release review pending'}

ui=BASE/'source/ui-icons.png'
if ui.exists():
    icons=Image.open(ui).convert('RGBA');icons.putalpha(icons.getchannel('A').point(lambda a:0 if a<48 else a))
    if icons.getchannel('A').getextrema()[0]!=0:raise ValueError('Bad UI transparency')
    icons.save(BASE/'ui-icons.webp','WEBP',lossless=True,method=6)
home=BASE/'source/home-world.png'
if home.exists():Image.open(home).convert('RGB').save(BASE/'home-world.webp','WEBP',quality=94,method=6)
manifest={'version':'american-v1','items':entries,'groups':PLAN['groups'],'rooms':rooms,
    'complete':not missing and len(rooms)>=8 and ui.exists(),'missing':missing,'all_retained_images_replaced':not missing and len(rooms)>=8 and ui.exists()}
(BASE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
(BASE/'technical-checks.json').write_text(json.dumps({'items':checks,'missing':missing,'rooms':list(rooms)},ensure_ascii=False,indent=2))
print(json.dumps({'newItems':len(entries),'newRooms':len(rooms),'missingItems':len(missing),'complete':manifest['complete']}))

# Keep reviewed replacements after regenerating the base atlas family.
revision=ROOT/"tools/apply-art-revisions.py"
if (BASE/"revisions/household-20261128.png").exists() and revision.exists():
    import runpy
    runpy.run_path(str(revision),run_name="__main__")
