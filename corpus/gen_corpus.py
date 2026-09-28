#!/usr/bin/env python3
"""Generate a deterministic image corpus for stb_image differential testing.

Covers JPEG (baseline/progressive, all subsampling ratios, grayscale),
PNG (RGB/RGBA/L/P), GIF (static + animated), BMP, TGA, PNM and PSD (raw).
PNG 16-bit / interlaced coverage comes from upstream tests/pngsuite.

Deterministic: fixed seed; re-running overwrites identical files.
"""
import math
import os
import struct
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = ROOT


def save(img, name, **kw):
    path = os.path.join(OUT, name)
    img.save(path, **kw)
    return path


def trysave(img, name, **kw):
    """Save, skipping unsupported encoder combinations (e.g. progressive JPEG
    with 4:4:4). Returns True if written."""
    try:
        save(img, name, **kw)
        return True
    except Exception as e:
        sys.stderr.write(f"skip {name}: {e}\n")
        return False


def gradient(w, h, seed=0):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = ((x * 255) // max(1, w - 1),
                        (y * 255) // max(1, h - 1),
                        ((x + y + seed) * 255) // max(1, w + h - 2))
    return img


def plasma(w, h, seed=0):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            v = math.sin((x + seed) * 0.07) + math.sin((y - seed) * 0.05) \
                + math.sin((x + y) * 0.03 + seed)
            r = int(128 + 100 * math.sin(v * 1.7))
            g = int(128 + 100 * math.sin(v * 2.3 + 1.0))
            b = int(128 + 100 * math.cos(v * 3.1))
            px[x, y] = (r & 255, g & 255, b & 255)
    return img


def noise(w, h):
    import random
    rng = random.Random(1234)
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = (rng.randrange(256), rng.randrange(256), rng.randrange(256))
    return img


def bases():
    yield "grad_64", gradient(64, 64)
    yield "plasma_256", plasma(256, 256, 3)
    yield "grad_640_480", gradient(640, 480, 7)
    yield "plasma_512", plasma(512, 512, 11)
    yield "noise_320", noise(320, 240)


def write_psd(path, img):
    """Minimal uncompressed RGB PSD (stb supports compression 0 and 1)."""
    img = img.convert("RGB")
    w, h = img.size
    data = img.tobytes()
    r = data[0::3]
    g = data[1::3]
    b = data[2::3]
    with open(path, "wb") as f:
        f.write(b"8BPS")
        f.write(struct.pack(">H", 1))          # version
        f.write(b"\x00" * 6)                   # reserved
        f.write(struct.pack(">H", 3))          # channels
        f.write(struct.pack(">I", h))
        f.write(struct.pack(">I", w))
        f.write(struct.pack(">H", 8))          # depth
        f.write(struct.pack(">H", 3))          # color mode: RGB
        f.write(struct.pack(">I", 0))          # color mode data
        f.write(struct.pack(">I", 0))          # image resources
        f.write(struct.pack(">I", 0))          # layer and mask
        f.write(struct.pack(">H", 0))          # compression: raw
        f.write(r)
        f.write(g)
        f.write(b)


def main():
    n = 0
    for name, img in bases():
        save(img, f"{name}.png")
        save(img.convert("RGBA"), f"{name}_rgba.png")
        save(img.convert("L"), f"{name}_gray.png")
        save(img.convert("P", palette=Image.ADAPTIVE), f"{name}_pal.png")
        n += 4

        for q in (10, 50, 85, 100):
            for prog in (0, 1):
                for sub in (0, 1, 2):
                    f = f"{name}_q{q}_p{prog}_s{sub}.jpg"
                    if trysave(img, f, quality=q, progressive=bool(prog), subsampling=sub):
                        n += 1
        if trysave(img.convert("L"), f"{name}_gray.jpg", quality=80):
            n += 1

        save(img.convert("RGB"), f"{name}.bmp")
        save(img.convert("RGBA"), f"{name}_rgba.bmp")
        save(img.convert("RGB"), f"{name}.tga")
        save(img.convert("RGBA"), f"{name}_rgba.tga")
        save(img.convert("RGB"), f"{name}.ppm")
        save(img.convert("L"), f"{name}.pgm")
        write_psd(os.path.join(OUT, f"{name}.psd"), img)
        n += 7

    # animated + static GIF
    frames = [plasma(128, 96, s).convert("P", palette=Image.ADAPTIVE) for s in (0, 40, 80)]
    try:
        frames[0].save(os.path.join(OUT, "anim.gif"), save_all=True,
                       append_images=frames[1:], duration=100, loop=0)
        n += 1
    except Exception as e:
        sys.stderr.write(f"skip anim.gif: {e}\n")
    if trysave(frames[0].convert("RGB"), "static.gif"):
        n += 1

    # JPEGs derived from pngsuite for real photographic-ish entropy variety
    png_root = os.path.join(ROOT, "..", "upstream", "tests", "pngsuite")
    if os.path.isdir(png_root):
        for dirpath, _dirs, files in os.walk(png_root):
            for fn in sorted(files):
                if not fn.endswith(".png"):
                    continue
                try:
                    im = Image.open(os.path.join(dirpath, fn))
                    im.seek(0)
                    im.load()
                    im = im.convert("RGB")
                    stem = "suite_" + os.path.splitext(fn)[0]
                    im.save(os.path.join(OUT, stem + ".jpg"), quality=75, subsampling=2)
                    im.save(os.path.join(OUT, stem + "_s0.jpg"), quality=90, subsampling=0)
                    n += 2
                except Exception:
                    continue

    print(f"generated {n} files in {OUT}")


if __name__ == "__main__":
    main()
