"""Deterministic, original PBR atlases. No reference photographs are embedded."""
from pathlib import Path
import hashlib,json,math,io,os,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont,ImageFilter
from catalog_source import CATALOG

PACK=Path(__file__).resolve().parents[1]
OUT=PACK/'assets/openfairway_equipment/textures'
OUT.mkdir(parents=True,exist_ok=True)
S=1024; T=512
yy,xx=np.mgrid[0:T,0:T].astype(float); x=xx/T; y=yy/T
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
def rgb(h): return np.array([int(h[i:i+2],16) for i in (1,3,5)],float)
def noise(rng,n=40):
    a=Image.fromarray(rng.integers(0,256,(n,n),dtype=np.uint8)).resize((T,T),Image.Resampling.BICUBIC)
    return np.asarray(a,dtype=float)/255
def text_at(d,xy,s,size=24,fill=(230,231,219),bold=False):
    path=BOLD if bold else FONT
    font=ImageFont.truetype(path,size) if Path(path).exists() else ImageFont.load_default(size=size)
    d.text(xy,s,font=font,fill=fill,anchor='mm')
def normals(h):
    gy,gx=np.gradient(h)
    a=np.stack([-gx*1.5,gy*1.5,np.ones_like(h)],-1)
    a/=np.linalg.norm(a,axis=2)[...,None]
    return Image.fromarray(np.uint8(np.clip((a*.5+.5)*255,0,255)))
def save(im,p):
    buffer=io.BytesIO();im.save(buffer,format='PNG',compress_level=6)
    tmp=p.with_suffix('.png.tmp')
    with tmp.open('wb') as f:
        f.write(buffer.getvalue());f.flush();os.fsync(f.fileno())
    os.replace(tmp,p)
    with Image.open(p) as check:check.verify()

def make(c):
    if c['family']=='iron':
        from iron_finishes import make_iron
        return make_iron(c,OUT)
    if c['family']=='wedge':
        from wedge_finishes import make_wedge
        return make_wedge(c,OUT)
    name=c['id']; style=c['style']; family=c['family']
    dest=OUT/name; dest.mkdir(exist_ok=True)
    rng=np.random.default_rng(int(hashlib.sha256(name.encode()).hexdigest()[:8],16))
    low=noise(rng,26); fine=noise(rng,160)
    base=Image.new('RGB',(S,S)); orm=Image.new('RGB',(S,S)); normal=Image.new('RGB',(S,S),(128,128,255)); mask=Image.new('RGB',(S,S))
    cs=[rgb(c['crown']),rgb(c['face']),rgb(c['sole']),rgb(c['crown'])*.88]
    for q in range(4):
        color=np.broadcast_to(cs[q],(T,T,3)).copy()
        color+=(low-.5)[...,None]*5+(fine-.5)[...,None]*2
        height=np.zeros((T,T)); rough=np.full((T,T),.35 if q==1 else .29); metal=np.full((T,T),.90)
        if family in ['driver','fairway','hybrid'] and q!=1: metal[:]=.35;rough[:]=.27
        if style in ['tour_black','midnight','blackout','robot']:rough[:]=.57 if q!=1 else .43;metal[:]=.68
        if style in ['rental','garage','cavity','lowball','rescue']:rough[:]=.52 if q!=1 else .44
        if style in ['grail','copper']:rough[:]=.20 if q!=1 else .35;metal[:]=.99
        if style=='brass':rough[:]=.49;metal[:]=.88
        if style=='tourline':rough[:]=.55;metal[:]=.93
        if style=='persimmon' and q!=1 and q!=2:
            grain=np.sin(x*50+np.sin(y*8)*3+low*2)*.5+.5
            dark=np.sin(x*140+np.sin(y*9)*6)*.5+.5
            color*= (.74+grain*.34+dark*.09)[...,None];height+=grain*.15;rough[:]=.30;metal[:]=0
        if style=='maple' and q!=1:
            bands=np.sin((y+.10*np.sin(x*6))*95)
            color*= (.76+(bands>0)*.29+.1*low)[...,None];rough[:]=.35;metal[:]=0;height+=bands*.15
        if style=='carbon' and q in [0,3]:
            a=np.floor(xx/18).astype(int);b=np.floor(yy/18).astype(int);alt=(a+b)%2
            fiber=np.where(alt==0,np.cos(xx*2),np.cos(yy*2))
            color*= (.58+alt*.25+fiber*.07)[...,None];rough[:]=.26;metal[:]=.25;height+=alt*.18+fiber*.06
        if style in ['rust','rustbelt','raw','brass','bronze']:
            if style=='rust': amount=np.clip(low*.8+.22,0,1)
            elif style=='rustbelt':
                sweet=np.exp(-((x-.5)/.32)**4-((y-.53)/.36)**4)
                amount=np.clip((low*.7+.15)*(sweet if q==1 else .7),0,1)
            elif style=='raw':amount=np.clip((low-.57)*1.3,0,.22)*(q==1)
            elif style=='bronze':amount=np.clip((low-.5)*.3,0,.10)
            else:
                corners=np.clip(abs(x-.5)*1.8+abs(y-.5)*1.5-.7,0,1)
                amount=np.clip((low*.55+corners*.7-.27),0,.72)
            oxidation=np.array([53,93,71]) if style=='brass' else np.array([139,71,35])
            color=color*(1-amount[...,None])+oxidation*amount[...,None]
            rough+=amount*.25;metal*=1-amount*.7;height+=fine*amount*.4
        # Face scoring and milling are embossed detail, not raised geometry.
        if q==1:
            if family!='putter':
                lines=np.mod(yy-50,36)
                groove=((lines<2)&(xx>54)&(xx<458)&(yy>55)&(yy<450))
                color[groove]*=.50;height[groove]-=1.5
                color[groove & (np.mod(xx,8)<4)]*=.91
            elif style not in ['rental','robot']:
                wave=np.sin(xx*.55+3*np.sin(yy*.14))
                height+=wave*.34;color+=(wave*.9)[...,None]
                if style=='grail' or style=='blackout':height+=np.sin(yy*.39)*.35
        if q==2:
            height+=np.sin(xx*.33+yy*.025)*.06
        color=np.uint8(np.clip(np.round(color/2)*2,0,255));im=Image.fromarray(color);d=ImageDraw.Draw(im)
        if q==0:
            if style=='offset':
                d.arc((200,180,325,305),85,295,fill='#dadace',width=7);d.polygon([(202,198),(228,202),(205,222)],fill='#dadace')
            elif style=='rocket':
                d.polygon([(183,0),(242,0),(350,512),(278,512)],fill='#e8ddb9');d.line([(267,0),(379,512)],fill='#ded5bb',width=7)
            elif style=='carbon':
                d.polygon([(288,74),(423,65),(430,123),(296,137)],fill='#dc8439');text_at(d,(358,103),'9.5',29,(38,30,20))
            elif style=='grenade':
                for k in range(-512,1024,66):
                    d.line([(k,0),(k+512,512)],fill='#303d27',width=3);d.line([(k,0),(k-512,512)],fill='#303d27',width=3)
                d.ellipse((77,306,151,380),outline='#dfba43',width=9)
            elif style=='cloud': d.line([(250,175),(250,310)],fill='#c9d0cc',width=5)
            elif style=='titan':
                d.polygon([(230,208),(278,208),(264,241),(244,241)],outline='#677178',width=3)
            elif style=='maple':text_at(d,(255,187),'///',24,(82,47,23))
            elif style=='lowball':d.arc((212,196,297,255),20,285,fill='#849583',width=5)
        if q==2:
            if style in ['tour_black','blackout']:
                d.ellipse((316,270,396,350),fill='#b99245',outline='#5a4929',width=6);d.line([(340,310),(372,310)],fill='#413f31',width=5)
            if style=='grenade':text_at(d,(254,264),'09 / 0460',33,(207,198,148),True)
            elif style=='persimmon':
                d.rounded_rectangle((91,74,421,430),radius=30,outline='#655231',width=12)
                for px,py in [(127,111),(385,111),(127,391),(385,391)]:d.ellipse((px-9,py-9,px+9,py+9),fill='#554f36');d.line([(px-5,py),(px+5,py)],fill='#a99b71',width=3)
            elif style=='steelhead':d.rounded_rectangle((74,98,438,420),radius=40,outline='#5e747b',width=8)
            elif style in ['titan','rescue','rocket']:
                d.rounded_rectangle((169,297,355,365),radius=4,fill='#d4c9a9')
                text_at(d,(262,330),'THIN FACE' if style=='rocket' else ('3H' if style=='rescue' else '460'),24,(55,59,52))
            if family=='wedge':
                label=c.get('loft_label',{'rust':'52','raw':'56','grind':'58','flop':'60','shovel':'SW','bent':'45','grocery':'PW'}.get(style,''))
                if label:text_at(d,(257,240),label,55,(42,49,44),True)
            elif family=='fairway' and style not in ['tour_black','persimmon']:
                text_at(d,(257,221),'5' if '5w' in name else '3',40,(205,207,194),True)
        if q==3:
            if style in ['sgi','rental'] and family=='iron':
                d.rounded_rectangle((114,156,413,347),radius=25,fill='#47575a',outline='#c0c7c4',width=7)
                if style=='sgi': d.polygon([(152,300),(329,193),(384,193),(207,300)],fill='#ad3a31');text_at(d,(313,310),'XL',36,(230,231,217),True)
            if style=='cavity' and family=='iron':
                # The thrift set has a painted burgundy badge and brass trim,
                # distinct from the loaner's plain dark steel cavity.
                d.rounded_rectangle((84,138,438,382),radius=30,fill='#843936',outline='#c5a06b',width=10)
                d.rounded_rectangle((101,155,421,365),radius=20,outline='#aa6255',width=3)
                d.line([(127,187),(127,332)],fill='#c5a06b',width=8)
                text_at(d,(275,256),'CB',88,(223,229,224),True)
                d.line([(206,328),(343,328)],fill='#c5a06b',width=5)
                badge=Image.new('L',(T,T),0)
                ImageDraw.Draw(badge).rounded_rectangle((96,150,426,370),radius=22,fill=255)
                painted=np.asarray(badge)>0
                rough[painted]=.69
                metal[painted]=.12
            if style in ['tour_cb','combo','bronze','forged','utility','grind','bent']:
                label={'tour_cb':'/ / /','combo':'PROTO','bronze':'FORGED','forged':'FORGED','utility':'TOUR','grind':'M6','bent':'45°'}[style]
                text_at(d,(260,250),label,42,((196,164,87) if style in ['tour_cb','bronze'] else (206,213,202)),True)
                if style=='combo':d.rectangle((303,352,433,413),fill='#dd8540');text_at(d,(367,382),'P',32,(41,36,29))
                if style=='utility':d.line([(75,378),(441,378)],fill='#404e4e',width=5)
            if style=='robot':text_at(d,(264,273),'9000',46,(125,157,155),True)
            if style=='tourline':text_at(d,(284,300),'07',20,(51,58,58))
        # Every material has an independent fixed-UV wear mask.
        edge=np.clip((np.maximum(abs(x-.5),abs(y-.5))-.36)*7,0,1)
        dirt=np.clip(low*.66+edge*.42,0,1)
        chips=np.clip((fine-.44)*2.5,0,1)*edge
        oxidation=np.clip((low-.37)*1.7,0,1)*(edge*.7+.12)
        w=np.uint8(np.stack([dirt,chips,oxidation],axis=2)*255)
        wim=Image.fromarray(w);wd=ImageDraw.Draw(wim)
        for _ in range(22):
            sx=int(rng.integers(18,494));sy=int(rng.integers(18,494));dx=int(rng.integers(7,48))
            wd.line((sx,sy,sx+dx,sy-int(rng.integers(1,8))),fill=(110,180,36),width=int(rng.integers(1,3)))
        pos=((q%2)*T,(q//2)*T)
        base.paste(im,pos)
        ao=np.clip(1-edge*.08,0,1)
        orm.paste(Image.fromarray(np.uint8(np.stack([ao,np.clip(rough+(fine-.5)*.025,0,1),metal],-1)*255)),pos)
        normal.paste(normals(height),pos);mask.paste(wim,pos)
    save(base,dest/f'ofg_{name}_albedo.png');save(orm,dest/f'ofg_{name}_orm.png');save(normal,dest/f'ofg_{name}_normal.png');save(mask,dest/f'ofg_{name}_wear.png')
    return {'albedo':f'{name}/ofg_{name}_albedo.png','orm':f'{name}/ofg_{name}_orm.png','normal':f'{name}/ofg_{name}_normal.png','wear':f'{name}/ofg_{name}_wear.png'}

def shared():
    d=OUT/'shared';d.mkdir(exist_ok=True)
    u,v=np.meshgrid(np.arange(512),np.arange(512))
    tread=((u+v*2)%29<3)|((u-v*2)%29<3)
    col=np.full((512,512,3),30,dtype=np.uint8);col[tread]=22
    for ch in range(3):col[:,:,ch]+=np.uint8((np.sin(v/512*np.pi)*4))
    save(Image.fromarray(col),d/'ofg_grip_albedo.png')
    save(normals(tread.astype(float)*.8),d/'ofg_grip_normal.png')
    worn=np.zeros((512,512,3),dtype=np.uint8);worn[:,:,0]=np.uint8((np.sin(u*.033)*np.sin(v*.06)*.3+.5)*230);worn[:,:,1]=tread*130
    save(Image.fromarray(worn),d/'ofg_grip_wear.png')
    fabric=np.full((512,512,3),224,dtype=np.uint8);fabric[:,:,1]=219;fabric[:,:,2]=201
    fabric[((u+v)%7)==0]-=8
    im=Image.fromarray(fabric);dr=ImageDraw.Draw(im)
    dr.rounded_rectangle((22,20,490,490),radius=52,outline='#a23430',width=9)
    for k in range(46,471,16):dr.line((k,37,k+6,37),fill='#eee8d4',width=2);dr.line((k,474,k+6,474),fill='#eee8d4',width=2)
    for k in [194,256,318]:dr.ellipse((k-16,237,k+16,269),fill='#a52c2a')
    save(im,d/'ofg_grail_headcover_albedo.png')

if __name__=='__main__':
    requested=set(sys.argv[1:])
    unknown=requested-{c['id'] for c in CATALOG}
    if unknown:raise SystemExit('Unknown asset IDs: '+', '.join(sorted(unknown)))
    selected=[c for c in CATALOG if not requested or c['id'] in requested]
    index=OUT/'texture_index.json'
    manifest=json.loads(index.read_text()) if requested and index.exists() else {}
    for i,c in enumerate(selected):
        manifest[c['id']]=make(c);print(f'TEXTURES {i+1}/{len(selected)} {c["id"]}',flush=True)
    if not requested:shared()
    index.write_text(json.dumps(manifest,indent=2))
