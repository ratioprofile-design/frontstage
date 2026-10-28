#!/usr/bin/env python3
"""Package the supplied DOT artwork without redrawing it. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageChops
import json, hashlib
root = Path(__file__).resolve().parent.parent
brand = root / "Resources/Brand"
web = root / "Server/Public/brand"
web.mkdir(parents=True, exist_ok=True)
originals = brand / "Originals"
def source(name):
    image = Image.open(originals / name).convert("RGBA")
    return image.crop(image.getbbox())
def square(image, size, fraction=.80, background=(0,0,0,0)):
    out = Image.new("RGBA", (size,size), background)
    image = image.copy()
    image.thumbnail((round(size*fraction),round(size*fraction)), Image.Resampling.LANCZOS)
    out.alpha_composite(image, ((size-image.width)//2,(size-image.height)//2))
    return out
# The supplied Dock filenames are reversed relative to the artwork.
for theme, filename in [("light","3-Dock-Dark-theme-Logo.png"),("dark","2-Dock-Light-Theme-Logo.png")]:
    art = source(filename)
    icon = square(art,1024)
    icon.save(brand / f"dot-app-{theme}.png")
    icon.save(brand / f"dot-{theme}.icns", format="ICNS")
    square(art,256).save(brand / f"dot-{theme}.ico", sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
    for size in [64,192,512]:
        square(art,size).save(web / f"icon-{theme}-{size}.png")
    background = (239,239,239,255) if theme=="light" else (24,7,0,255)
    square(art,512,.72,background).save(web / f"maskable-{theme}-512.png")
    if theme=="light":
        square(art,180,.80,(239,239,239,255)).save(web / "apple-touch-icon.png")
for theme, filename in [("light","4-DOT-White-Theme-LOGO.png"),("dark","1-DOT-Dark-Theme-LOGO.png")]:
    art = source(filename)
    art.thumbnail((640,180), Image.Resampling.LANCZOS)
    art.save(web / f"wordmark-{theme}.png")
    art.save(brand / f"wordmark-{theme}.png")
art = Image.open(originals / "1-DOT-Dark-Theme-LOGO.png").convert("RGBA")
r,g,b,a = art.split()
mask = ImageChops.multiply(ImageChops.multiply(r.point(lambda x:255 if x>150 else 0),g.point(lambda x:255 if x>70 else 0)),b.point(lambda x:255 if x<80 else 0))
mask = ImageChops.multiply(mask,a)
dot = art.crop(mask.getbbox())
for size in [16,32]:
    square(dot,size,.80).save(web / f"favicon-{size}.png")
square(dot,64,.80).save(root / "Server/Public/favicon.ico",sizes=[(16,16),(32,32),(48,48),(64,64)])
manifest = {"sources":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(originals.glob("*.png"))},"iconMapping":{"light":"3-Dock-Dark-theme-Logo.png","dark":"2-Dock-Light-Theme-Logo.png"},"note":"Original artwork preserved; derived assets trim transparent margins and add platform padding."}
(brand / "artwork.json").write_text(json.dumps(manifest,indent=2)+"\n")

card = Image.new("RGBA",(1200,630),(24,7,0,255))
word = source("1-DOT-Dark-Theme-LOGO.png")
word.thumbnail((850,300),Image.Resampling.LANCZOS)
card.alpha_composite(word,((1200-word.width)//2,(630-word.height)//2))
card.convert("RGB").save(web / "social-card.png")
