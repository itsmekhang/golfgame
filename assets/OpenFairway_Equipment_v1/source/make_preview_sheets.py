from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import io,os
from catalog_source import CATALOG,RARITY_COLORS
PACK=Path(__file__).resolve().parents[1];PRE=PACK/'previews'
def font(n,bold=False,serif=False):
    name='DejaVuSerif' if serif else 'DejaVuSans'
    p=Path('/usr/share/fonts/truetype/dejavu')/(name+('-Bold' if bold else '')+'.ttf')
    if not p.exists():p=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
    return ImageFont.truetype(str(p),n)
def save(im,p):
    b=io.BytesIO();im.save(b,format='PNG');temp=p.with_suffix('.png.tmp');temp.write_bytes(b.getvalue());os.replace(temp,p)
def preview(c):
    suffix='_back' if c['family']=='putter' else ''
    return Image.open(PRE/f'ofg_{c["id"]}{suffix}.png').convert('RGBA')
def sheet(items,cols,card_w,card_h,title,subtitle,filename):
    margin=54;gap=20;header=180;footer=70;rows=(len(items)+cols-1)//cols
    W=margin*2+cols*card_w+(cols-1)*gap;H=header+rows*card_h+(rows-1)*gap+footer
    out=Image.new('RGB',(W,H),'#f1efe3');d=ImageDraw.Draw(out)
    d.text((margin,29),'O P E N F A I R W A Y   /   E Q U I P M E N T',font=font(16,True),fill='#526254')
    d.text((margin,64),title,font=font(47,True,True),fill='#203c30')
    d.text((margin,125),subtitle,font=font(18),fill='#5b695c')
    for i,c in enumerate(items):
        x=margin+(i%cols)*(card_w+gap);y=header+(i//cols)*(card_h+gap)
        d.rounded_rectangle((x,y,x+card_w,y+card_h),radius=12,fill='#e5e8df',outline='#d1d6c9',width=1)
        im=preview(c);im.thumbnail((card_w-12,card_h-90),Image.Resampling.LANCZOS)
        out.paste(im,(x+(card_w-im.width)//2,y+4),im)
        d.text((x+19,y+card_h-76),c['name'],font=font(18 if cols==5 else 25,True),fill='#253d30')
        d.text((x+19,y+card_h-45),c['id'],font=font(12 if cols==5 else 16),fill='#617060')
        rarity=('DEVELOPER · '+c['rarity'].upper()) if c.get('admin_only') else c['rarity'].upper()
        d.text((x+card_w-18,y+card_h-23),rarity,font=font(11 if cols==5 else 13,True),anchor='rs',fill='#826136' if c['rarity'] in ['legendary','mythic'] else '#52684e')
        d.rounded_rectangle((x+18,y+18,x+24,y+39),radius=3,fill=RARITY_COLORS[c['rarity']])
    d.text((margin,H-39),'Rendered from the exported 3D models · Metres · +Y up · Face toward −Z',font=font(15),fill='#6b7669')
    save(out,PRE/filename)
if __name__=='__main__':
    sheet(CATALOG,5,342,336,'The Pro Shop','45 club items with individual finishes, plus a separate fitted headcover.','OpenFairway_All_45_Clubs.png')
    sheet([c for c in CATALOG if c['family']=='putter'],3,610,498,'The Putter Collection','Seven collectibles, the clubhouse loaner, and the developer-only Auto-Putt.','OpenFairway_Putter_Collection.png')
    print('PREVIEW_SHEETS_COMPLETE')
