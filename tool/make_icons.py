#!/usr/bin/env python3
"""ONE brand icons, drawn after the proposal: navy ground, slanted yellow/white stripes, "/ONE" mark.
Outputs app launcher icons (legacy + adaptive), a monochrome notification icon and dashboard favicons."""
import pathlib
from PIL import Image, ImageDraw, ImageFont

NAVY = (43, 76, 155); NAVY_D = (31, 58, 122); YELLOW = (245, 197, 24); WHITE = (255, 255, 255)
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-BlackItalic.otf"
OUT = pathlib.Path(__file__).parent / "icons"
OUT.mkdir(exist_ok=True)
S = 1024

def stripes(img, alpha=255, top=0.64):
    """The proposal's cover stripes, rising from the bottom-left corner (kept below the mark)."""
    d = ImageDraw.Draw(img, "RGBA")
    k = 0.42  # slant: horizontal shift per unit of height
    def band(x, w, col):
        h = 1 - top
        d.polygon([(x * S, S), ((x + w) * S, S), ((x + w + k * h) * S, top * S), ((x + k * h) * S, top * S)], fill=col + (alpha,))
    band(0.02, 0.11, YELLOW)
    band(0.16, 0.03, WHITE)
    band(0.22, 0.065, YELLOW)

def wordmark(img, width_frac, color=WHITE, slash=YELLOW, dy=0.0, dx=0.0):
    d = ImageDraw.Draw(img)
    size = 400
    f = ImageFont.truetype(FONT, size)
    w = d.textlength("/ONE", font=f)
    size = int(size * (S * width_frac) / w)
    f = ImageFont.truetype(FONT, size)
    ws = d.textlength("/", font=f); w = d.textlength("/ONE", font=f)
    bbox = d.textbbox((0, 0), "/ONE", font=f)
    x = (S - w) / 2 + dx * S
    y = (S - (bbox[3] - bbox[1])) / 2 - bbox[1] + dy * S
    d.text((x, y), "/", font=f, fill=slash)
    d.text((x + ws, y), "ONE", font=f, fill=color)

def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], r, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0)); out.paste(img, (0, 0), m); return out

# full icon (legacy launcher, favicons, store)
full = Image.new("RGBA", (S, S), NAVY + (255,))
stripes(full, 255)
# darken stripes slightly behind the text for legibility
veil = Image.new("RGBA", (S, S), NAVY_D + (0,)); full = Image.alpha_composite(full, veil)
wordmark(full, 0.70, dy=-0.07)
full_r = rounded(full, int(S * 0.22))
full_r.save(OUT / "icon-1024.png")

# adaptive icon layers (108dp canvas; keep the mark inside the 66dp safe zone)
bg = Image.new("RGBA", (S, S), NAVY + (255,)); stripes(bg, 255, top=0.66); bg.save(OUT / "adaptive-bg-1024.png")
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0)); wordmark(fg, 0.52, dy=-0.05); fg.save(OUT / "adaptive-fg-1024.png")

# monochrome notification icon: white "/1" mark on transparent
mono = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(mono); f = ImageFont.truetype(FONT, 820)
bb = d.textbbox((0, 0), "/1", font=f); w = bb[2] - bb[0]; h = bb[3] - bb[1]
d.text(((S - w) / 2 - bb[0], (S - h) / 2 - bb[1]), "/1", font=f, fill=WHITE)
mono.save(OUT / "notif-1024.png")
print("drawn")

# ── export sizes ──
RES = pathlib.Path(__file__).parent / "res"
dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
full_sq = full  # unrounded: Android masks legacy icons itself on most launchers
for dn, k in dens.items():
    mm = RES / f"mipmap-{dn}"; mm.mkdir(parents=True, exist_ok=True)
    full_r.resize((int(48 * k), int(48 * k)), Image.LANCZOS).save(mm / "ic_launcher.png")
    bg.resize((int(108 * k), int(108 * k)), Image.LANCZOS).save(mm / "ic_launcher_background.png")
    fg.resize((int(108 * k), int(108 * k)), Image.LANCZOS).save(mm / "ic_launcher_foreground.png")
    dd = RES / f"drawable-{dn}"; dd.mkdir(parents=True, exist_ok=True)
    mono.resize((int(24 * k), int(24 * k)), Image.LANCZOS).save(dd / "ic_stat_one.png")
# monochrome layer for Android 13 themed icons: white mark on transparent
mono_fg = Image.new("RGBA", (S, S), (0, 0, 0, 0)); wordmark(mono_fg, 0.52, dy=-0.05, color=WHITE, slash=WHITE)
for dn, k in dens.items():
    mono_fg.resize((int(108 * k), int(108 * k)), Image.LANCZOS).save(RES / f"mipmap-{dn}" / "ic_launcher_monochrome.png")
av = RES / "mipmap-anydpi-v26"; av.mkdir(parents=True, exist_ok=True)
(av / "ic_launcher.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
""")

# dashboard favicons
DASH = pathlib.Path(__file__).parent.parent / "dashboard"
full_r.resize((32, 32), Image.LANCZOS).save(DASH / "favicon-32.png")
full_r.resize((192, 192), Image.LANCZOS).save(DASH / "favicon-192.png")
full_sq.convert("RGB").resize((180, 180), Image.LANCZOS).save(DASH / "apple-touch-icon.png")
full_r.resize((512, 512), Image.LANCZOS).save(DASH / "icon-512.png")
print("exported")
