"""Label unretouched Blender renders. Requires Pillow."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
PACK=Path(__file__).resolve().parents[1];PREV=PACK/'previews'
def font(n,bold=False):return ImageFont.truetype('C:/Windows/Fonts/'+('seguisb.ttf' if bold else 'segoeui.ttf'),n)
bg=(29,35,43);white=(237,242,247);muted=(161,177,194);red=(242,70,85)
sheet=Image.new('RGB',(1800,1230),bg);d=ImageDraw.Draw(sheet)
d.text((42,24),'OFG  /  D2 CARBON DRIVER',font=font(37,True),fill=white)
d.text((43,73),'126 x 113 x 59 mm shell   /   10.5 degree loft   /   original driver shaft fitting',font=font(23),fill=muted)
for i,(name,label) in enumerate([('hero','01   THREE-QUARTER'),('face','02   CRIMSON STRIKING FACE'),('crown','03   CARBON CROWN'),('toe','04   TOE PROFILE'),('rear','05   HEEL & REAR'),('sole','06   SCULPTED SOLE & WEIGHTS')]):
    x=24+(i%3)*592;y=125+(i//3)*548
    im=Image.open(PREV/(name+'.png')).convert('RGB');im.thumbnail((574,468));sheet.paste(im,(x+(574-im.width)//2,y))
    d.text((x+12,y+477),label,font=font(20,True),fill=white)
d.line((36,120,1764,120),fill=red,width=2)
d.text((42,1200),'Blender renders of the exported GLB. All final geometry authored in Blender.',font=font(17),fill=muted)
sheet.save(PACK/'preview_sheet.png')
raw=Image.open(PREV/'scale_comparison_raw.png').convert('RGB').crop((0,100,1800,750))
board=Image.new('RGB',(1800,820),bg);board.paste(raw,(0,85));d=ImageDraw.Draw(board)
d.text((40,23),'UNCHANGED SCALE / EXISTING CLUB HEADS',font=font(32,True),fill=white)
for x,label,size in [(316,'FAIRWAY WOOD','106 mm width'),(900,'D1 DRIVER','124 mm width'),(1484,'D2 CARBON DRIVER','126 mm width')]:
    d.text((x,744),label,font=font(23,True),fill=white,anchor='mt');d.text((x,779),size,font=font(20),fill=muted,anchor='mt')
board.save(PACK/'scale_comparison.png')
print('PREVIEW_SHEETS_COMPLETE')
