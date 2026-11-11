#!/usr/bin/env python3
"""Lightweight schematic previews of maps 12–15, not screenshots. Requires Pillow."""
import sys
if "--overwrite-legacy" not in sys.argv:
    raise SystemExit("Legacy schematic generator: use --overwrite-legacy to overwrite actual rendered map previews.")
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math
OUT = Path(__file__).resolve().parents[1] / 'assets/maps'
font = ImageFont.load_default()

def bg(title, subtitle):
    im = Image.new('RGB',(480,270),(20,34,68)); d=ImageDraw.Draw(im)
    for y in range(270):
        d.line((0,y,480,y), fill=(20+y//15,34+y//10,68+y//7))
    d.rounded_rectangle((12,12,468,258),14,outline=(90,130,170),width=2)
    d.text((26,20),title,fill='white',font=font,stroke_width=0)
    d.text((26,240),subtitle,fill=(180,210,225),font=font)
    return im,d

def house(id,title,cols,rows,theme):
    im,d=bg(title,'SCHEMATIC PREVIEW - HIDE & SEEK')
    colors={'school':[(153,189,152),(221,193,143)],'warehouse':[(105,120,132),(164,146,116)],'museum':[(186,151,193),(222,187,150)]}[theme]
    x0,y0,x1,y1=75,54,405,225
    cw,ch=(x1-x0)/cols,(y1-y0)/rows
    for z in range(rows):
        for x in range(cols):
            a,b=x0+x*cw,y0+z*ch
            d.rectangle((a+3,b+3,a+cw-3,b+ch-3), fill=colors[(x+z)%2],outline=(236,235,215),width=3)
            for k in range(2):
                px=a+12+k*(cw-32);py=b+12
                d.rounded_rectangle((px,py,px+14,py+19),3,fill=(95,68,55),outline=(255,220,160))
            d.ellipse((a+cw/2-4,b+ch/2-4,a+cw/2+4,b+ch/2+4),fill=(248,235,144))
    im.save(OUT/f'map_{id}.png',optimize=True)

im,d=bg('TWISTER ARENA','SCHEMATIC PREVIEW - SURVIVAL')
d.ellipse((90,50,390,223),fill=(45,174,172),outline=(239,240,211),width=5)
for x,color in [(170,(255,103,63)),(310,(175,110,243))]:
    d.line((x-42,155,x+42,108),fill=color,width=12);d.ellipse((x-7,124,x+7,138),fill='white')
for y in (80,194):d.ellipse((230,y-8,250,y+8),fill=(250,204,55))
im.save(OUT/'map_12.png',optimize=True)
# School schematic shows its open central corridor and rooms on both sides.
im,d=bg('SCHOOL','SCHEMATIC PREVIEW - HIDE & SEEK')
d.rectangle((54,62,426,215),fill=(189,193,160),outline=(239,236,210),width=3)
d.rectangle((58,117,422,159),fill=(122,168,168))
for row in range(2):
    for col in range(4):
        x=58+col*91; y=65 if row == 0 else 163
        d.rectangle((x+2,y,x+87,y+49),fill=[(163,191,170),(190,172,142),(232,191,142),(181,166,202)][(row*4+col)%4],outline=(243,234,208),width=2)
        d.rectangle((x+12,y+10,x+29,y+22),fill=(96,68,54))
        d.rectangle((x+57,y+10,x+74,y+22),fill=(96,68,54))
        d.line((x+34,y+49 if row == 0 else y,x+53,y+49 if row == 0 else y),fill=(122,168,168),width=4)
d.text((203,133),'CORRIDOR',fill=(20,50,55),font=font)
im.save(OUT/'map_13.png',optimize=True)
house(14,'WAREHOUSE',3,3,'warehouse')
house(15,'MUSEUM',4,2,'museum')
