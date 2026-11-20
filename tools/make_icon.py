# Draws the FlashCD addon icon: a cooldown clock with a bright quarter
# "coming ready" and a lightning bolt flash in front.
import sys, math
from PIL import Image, ImageDraw, ImageFilter

S = 1024  # supersampled canvas
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# rounded-square background with a radial gradient
bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
grad = Image.new("RGBA", (S, S))
px = grad.load()
cx = cy = S / 2
for y in range(S):
    for x in range(S):
        d = min(1.0, math.hypot(x - cx, y - cy) / (S * 0.72))
        r = int(38 * (1 - d) + 8 * d)
        g = int(52 * (1 - d) + 10 * d)
        b = int(96 * (1 - d) + 22 * d)
        px[x, y] = (r, g, b, 255)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([24, 24, S - 24, S - 24], radius=170, fill=255)
bg.paste(grad, (0, 0), mask)
img = Image.alpha_composite(img, bg)

d = ImageDraw.Draw(img)
# gold border
d.rounded_rectangle([24, 24, S - 24, S - 24], radius=170, outline=(214, 170, 64, 255), width=34)

# cooldown ring: dark sweep for the part still cooling, bright for the ready part
R = 330
box = [cx - R, cy - R, cx + R, cy + R]
d.ellipse(box, fill=(10, 14, 28, 255))
d.pieslice(box, start=-90, end=0, fill=(255, 196, 60, 255))            # ready quarter
d.pieslice(box, start=0, end=270, fill=(30, 40, 70, 255))              # still cooling
inner = 250
d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=(18, 24, 46, 255))
d.ellipse(box, outline=(214, 170, 64, 255), width=14)

# lightning bolt with a soft glow behind it
bolt = [(560, 150), (330, 560), (490, 560), (420, 880), (720, 420), (555, 420), (650, 150)]
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).polygon(bolt, fill=(255, 220, 90, 255))
glow = glow.filter(ImageFilter.GaussianBlur(48))
img = Image.alpha_composite(img, glow)
img = Image.alpha_composite(img, glow)

d = ImageDraw.Draw(img)
d.polygon(bolt, fill=(255, 246, 200, 255), outline=(120, 70, 10, 255), width=12)
# brighter core stripe
core = [(575, 200), (400, 535), (515, 535), (470, 760), (665, 450), (580, 450), (630, 200)]
d.polygon(core, fill=(255, 255, 255, 255))

# usage: python tools/make_icon.py <Media dir> <preview dir>
out = sys.argv[1]
small = img.resize((128, 128), Image.LANCZOS)
small.save(out + "/Icon.tga")                 # uncompressed 32-bit TGA for WoW
small.save(sys.argv[2] + "/icon_preview.png")
img.resize((32, 32), Image.LANCZOS).resize((128, 128), Image.NEAREST).save(sys.argv[2] + "/icon_small.png")
print("done")
