#!/usr/bin/env python3
"""Builds docs/demo.gif from CI screenshots.

Usage: python tools/make_demo_gif.py SHOTS_DIR docs/demo.gif

SHOTS_DIR holds the PNGs that the Build and End-to-end workflows publish to
the `ci-logs` branch (home.png, bookPage.png, …, after-bilingual.png).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

INK = (31, 42, 68)
SAFFRON = (227, 155, 45)
WIDTH = 760

FRAMES = [
    ("home.png", "78,000+ free books — plus what the world is reading"),
    ("bookPage.png", "Pick any book"),
    ("languages.png", "Choose your language: Tamil, Hindi, Bengali… 200 in all"),
    ("reader.png", "BookIt translates the whole book on your device"),
    ("final.png", "…and keeps it, to read offline anytime"),
    ("after-bilingual.png", "Bilingual view: the original under each paragraph"),
    ("after-quote.png", "Share a favourite passage as an image"),
    ("statsCard.png", "Reading streaks keep you going"),
    ("home-ta.png", "Menus in தமிழ், हिन्दी, বাংলা, తెలుగు, मराठी"),
]


def font(size):
    for name in ("NotoSans-Bold.ttf", "DejaVuSans-Bold.ttf"):
        for d in (os.path.expanduser("~/.fonts"), "/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/noto"):
            p = os.path.join(d, name)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def draw_caption(draw, text, y, h):
    """Draws mixed-script text centred, picking a font for each script run."""
    fonts = {
        "latin": font(24),
        "Taml": ImageFont.truetype(os.path.expanduser("~/.fonts/NotoSansTamil-Bold.ttf"), 24)
        if os.path.exists(os.path.expanduser("~/.fonts/NotoSansTamil-Bold.ttf")) else font(24),
        "Deva": ImageFont.truetype(os.path.expanduser("~/.fonts/NotoSansDevanagari-Bold.ttf"), 24)
        if os.path.exists(os.path.expanduser("~/.fonts/NotoSansDevanagari-Bold.ttf")) else font(24),
        "Beng": ImageFont.truetype(os.path.expanduser("~/.fonts/NotoSansBengali-Bold.ttf"), 24)
        if os.path.exists(os.path.expanduser("~/.fonts/NotoSansBengali-Bold.ttf")) else font(24),
        "Telu": ImageFont.truetype(os.path.expanduser("~/.fonts/NotoSansTelugu-Bold.ttf"), 24)
        if os.path.exists(os.path.expanduser("~/.fonts/NotoSansTelugu-Bold.ttf")) else font(24),
    }

    def script(ch):
        o = ord(ch)
        if 0x0B80 <= o <= 0x0BFF: return "Taml"
        if 0x0900 <= o <= 0x097F: return "Deva"
        if 0x0980 <= o <= 0x09FF: return "Beng"
        if 0x0C00 <= o <= 0x0C7F: return "Telu"
        return None

    runs = []
    for ch in text:
        s = script(ch) or (runs[-1][0] if runs and ch in " ,'" and runs[-1][0] != "latin" else "latin")
        if runs and runs[-1][0] == s:
            runs[-1][1] += ch
        else:
            runs.append([s, ch])
    widths = [draw.textlength(t, font=fonts[s]) for s, t in runs]
    x = (WIDTH - sum(widths)) / 2
    for (s, t), w in zip(runs, widths):
        draw.text((x, y + h / 2), t, font=fonts[s], fill="white", anchor="lm")
        x += w


def frame(path, text):
    img = Image.open(path).convert("RGB")
    scale = WIDTH / img.width
    img = img.resize((WIDTH, round(img.height * scale)), Image.LANCZOS)
    bar = 58
    out = Image.new("RGB", (WIDTH, img.height + bar), INK)
    out.paste(img, (0, 0))
    d = ImageDraw.Draw(out)
    d.rectangle([0, img.height, WIDTH, img.height + 4], fill=SAFFRON)
    draw_caption(d, text, img.height + 4, bar - 4)
    return out


def main():
    shots, dest = sys.argv[1], sys.argv[2]
    frames = [frame(os.path.join(shots, f), t) for f, t in FRAMES if os.path.exists(os.path.join(shots, f))]
    missing = [f for f, _ in FRAMES if not os.path.exists(os.path.join(shots, f))]
    if missing:
        print("missing:", ", ".join(missing))
    h = max(f.height for f in frames)
    frames = [f if f.height == h else f.resize((WIDTH, h)) for f in frames]
    seq, durations = [], []
    for i, f in enumerate(frames):
        seq.append(f)
        durations.append(2300)
        nxt = frames[(i + 1) % len(frames)]
        for a in (0.33, 0.66):
            seq.append(Image.blend(f, nxt, a))
            durations.append(70)
    pal = [s.quantize(colors=200, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for s in seq]
    pal[0].save(dest, save_all=True, append_images=pal[1:], duration=durations, loop=0, optimize=True, disposal=1)
    print(f"{dest}: {len(frames)} scenes, {os.path.getsize(dest) // 1024} KB")


if __name__ == "__main__":
    main()
