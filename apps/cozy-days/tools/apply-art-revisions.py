"""Apply reviewed replacement atlas and regenerate the matching alpha geometry."""
import base64, hashlib, json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'presentation/american-v1'
SOURCE=BASE/'revisions/household-20261128.png'
def hull(points):
    pts=sorted(set(points))
    def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    def side(seq):
        result=[]
        for p in seq:
            while len(result)>1 and cross(result[-2],result[-1],p)<=0:result.pop()
            result.append(p)
        return result
    return side(pts)[:-1]+side(reversed(pts))[:-1]
manifest=json.loads((BASE/'manifest.json').read_text())
report=[]
batches=[(SOURCE,3,[(138,'original sage portable game console'),(27,'hooked sports earbuds in coral case'),(101,'wooden geometric brain teaser cube'),(41,'orange motif soda can'),(206,'bulb reservoir water toy'),(290,'bubble ring toy blaster')]),
    (BASE/'revisions/family-20261128.png',4,[(70,'lemon sparkling water bottles'),(169,'olive oil bottle'),(279,'maple syrup bottle'),(87,'sidewalk chalk box'),(347,'wax crayon tin'),(163,'camping flashlight'),(85,'hair clip trinket dish')])]
entries=[]
for source,columns,items in batches:
    if not source.exists():continue
    atlas=Image.open(source).convert('RGBA')
    for cell,(number,subject) in enumerate(items):
        col,row=cell%columns,cell//columns
        cw,ch=atlas.width/columns,atlas.height/2
        image=atlas.crop(tuple(round(v) for v in (col*cw,row*ch,(col+1)*cw,(row+1)*ch)))
        entries.append((source,cell,number,subject,image))
for source,cell,number,subject,image in entries:
    alpha=image.getchannel('A').point(lambda a:0 if a<48 else min(255,round(a*255/254)))
    image.putalpha(alpha)
    bounds=alpha.getbbox()
    assert bounds,'empty replacement'
    image=image.crop(bounds)
    image.thumbnail((384,384),Image.Resampling.LANCZOS)
    padded=Image.new('RGBA',(image.width+8,image.height+8));padded.paste(image,(4,4));image=padded
    key=f'item-{number:03d}'
    path=BASE/f'items/{key}-r2.webp';image.save(path,'WEBP',lossless=True,method=6)
    mask=image.getchannel('A').resize((48,48),Image.Resampling.NEAREST)
    bits=bytearray(288);points=[]
    for y in range(48):
        for x in range(48):
            if mask.getpixel((x,y))>=128:
                bit=y*48+x;bits[bit>>3]|=1<<(bit&7)
                points.extend([(x/48-.5,.5-y/48),((x+1)/48-.5,.5-(y+1)/48)])
    assert points and image.getchannel('A').getextrema()==(0,255)
    item=manifest['items'][key]
    item.update(subject=subject,path=path.relative_to(ROOT).as_posix(),pixels=list(image.size),outline=hull(points),grid={'columns':48,'rows':48,'bits':base64.b64encode(bits).decode()},source={'kind':'built-in image_gen','sheet':source.relative_to(BASE).as_posix(),'cell':cell,'generation_sha256':hashlib.sha256(source.read_bytes()).hexdigest()},sha256=hashlib.sha256(path.read_bytes()).hexdigest(),technical_checks_passed=True,visual_review='replacement atlas reviewed; game-scale review pending')
    report.append({'key':key,'pixels':list(image.size),'alpha':[0,255],'path':item['path']})
(BASE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
(BASE/'revisions/technical-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
