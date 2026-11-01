#!/usr/bin/env python3
"""Generate a pixel-tile loading GIF from the Hesabix app icon.

Usage:
    python extraScripts/generate_pixel_loading_gif.py
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "hesabixUI" / "hesabix_ui" / "assets" / "images" / "logo.png"
OUT_DIR = ROOT / "hesabixUI" / "hesabix_ui" / "assets" / "images"
OUT_GIF = OUT_DIR / "hesabix_pixel_loading.gif"

GRID = 18
TILE = 14
GROUT = 2
CELL = TILE + GROUT
PAD = CELL
SIZE = PAD * 2 + GRID * CELL
FRAMES = 48
FRAME_MS = 60
TRANSPARENT_KEY = (255, 0, 255)
GROUT_COLOR = (0, 10, 42)

FILL_END = 0.58
HOLD_END = 0.86
UNLIT = 0.38
FRONT_GLOW = 0.48
BRIGHT_LEVELS = (0.38, 0.52, 0.68, 0.84, 1.0, 1.16, 1.32)


def snap_level(value: float, levels: tuple[float, ...] = BRIGHT_LEVELS) -> float:
    return min(levels, key=lambda item: abs(item - value))


def clamp(v: float, lo: float = 0.0, hi: float = 255.0) -> int:
    return int(max(lo, min(hi, round(v))))


def mix_rgb(color: tuple[int, int, int], toward: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(clamp(a + (b - a) * t) for a, b in zip(color, toward))  # type: ignore[return-value]


def scale_rgb(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    if factor >= 1.0:
        return mix_rgb(color, (255, 255, 255), min(0.85, factor - 1.0))
    return tuple(clamp(c * factor) for c in color)  # type: ignore[return-value]


def ease_out_cubic(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1.0 - (1.0 - t) ** 3


def sample_tiles(src: Image.Image) -> list[dict]:
    arr = np.array(src.convert("RGBA"))
    alpha = arr[:, :, 3]
    ys, xs = np.where(alpha > 24)
    cropped = arr[int(ys.min()) : int(ys.max()) + 1, int(xs.min()) : int(xs.max()) + 1]
    ch, cw = cropped.shape[:2]

    blues: list[np.ndarray] = []
    whites: list[np.ndarray] = []
    tiles: list[dict] = []

    for row in range(GRID):
        for col in range(GRID):
            region = cropped[
                int(row * ch / GRID) : int((row + 1) * ch / GRID),
                int(col * cw / GRID) : int((col + 1) * cw / GRID),
            ]
            if region.size == 0:
                continue
            opaque = region[:, :, 3] >= 96
            if float(opaque.mean()) < 0.42:
                continue
            rgb = region[:, :, :3][opaque].mean(axis=0)
            lum = float(0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2])
            if lum >= 148:
                whites.append(rgb)
                kind = "letter"
            else:
                blues.append(rgb)
                kind = "badge"
            tiles.append({"row": row, "col": col, "kind": kind})

    # Prefer the typical interior badge blue, not the dark anti-aliased rim.
    if blues:
        stacked = np.stack(blues)
        brand_blue = tuple(clamp(c) for c in np.percentile(stacked, 72, axis=0))
    else:
        brand_blue = (0, 40, 148)
    brand_white = (255, 255, 255)

    cx = (GRID - 1) / 2.0
    cy = (GRID - 1) / 2.0
    for tile in tiles:
        dx = tile["col"] - cx
        dy = tile["row"] - cy
        ang = math.atan2(dx, -dy)
        tile["angle"] = (ang % (2 * math.pi)) / (2 * math.pi)
        tile["color"] = brand_white if tile["kind"] == "letter" else brand_blue

    print(f"grid={GRID} tiles={len(tiles)} size={SIZE} blue={brand_blue} white={brand_white}")
    return tiles


def tile_box(row: int, col: int, scale: float = 1.0) -> tuple[int, int, int, int, int, int, int, int]:
    cell_x = PAD + col * CELL
    cell_y = PAD + row * CELL
    inset = GROUT // 2
    x = cell_x + inset
    y = cell_y + inset
    if scale >= 0.999:
        return cell_x, cell_y, x, y, x + TILE - 1, y + TILE - 1, cell_x + CELL - 1, cell_y + CELL - 1
    cx = x + TILE / 2.0
    cy = y + TILE / 2.0
    half = (TILE * scale) / 2.0
    x0 = int(round(cx - half))
    y0 = int(round(cy - half))
    x1 = int(round(cx + half)) - 1
    y1 = int(round(cy + half)) - 1
    return cell_x, cell_y, x0, y0, x1, y1, cell_x + CELL - 1, cell_y + CELL - 1


def draw_beveled_tile(draw: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
    if x1 <= x0 or y1 <= y0:
        return
    hi = scale_rgb(color, 1.22)
    lo = scale_rgb(color, 0.78)
    draw.rectangle((x0, y0, x1, y1), fill=color)
    draw.rectangle((x0, y0, x1, y0), fill=hi)
    draw.rectangle((x0, y0, x0, y1), fill=hi)
    draw.rectangle((x0, y1, x1, y1), fill=lo)
    draw.rectangle((x1, y0, x1, y1), fill=lo)


def tile_intensity(tile: dict, t: float) -> tuple[float, float]:
    appear = tile["angle"] * FILL_END
    appear = min(FILL_END, max(0.0, appear + 0.016 * math.sin(tile["row"] * 2.7 + tile["col"] * 1.9)))

    if t < FILL_END:
        if t < appear:
            return UNLIT, 1.0
        local = (t - appear) / 0.07
        if local < 1.0:
            pop = 1.0 + 0.12 * math.sin(math.pi * min(1.0, local))
            glow = 1.0 + FRONT_GLOW * (1.0 - local)
            return glow, pop
        return 1.0, 1.0

    if t < HOLD_END:
        wave = (t - FILL_END) / max(1e-6, HOLD_END - FILL_END)
        delta = (tile["angle"] - wave) % 1.0
        if delta < 0.12:
            k = 1.0 - delta / 0.12
            return 1.0 + FRONT_GLOW * (k**1.5), 1.0 + 0.06 * k
        return 1.0, 1.0

    reset_t = (t - HOLD_END) / max(1e-6, 1.0 - HOLD_END)
    fade = 1.0 - ease_out_cubic(reset_t) * (1.0 - UNLIT)
    return fade, 1.0


def snapped_intensity(tile: dict, t: float) -> tuple[float, float]:
    brightness, _scale = tile_intensity(tile, t)
    return snap_level(brightness), 1.0


def render_frame(tiles: list[dict], t: float) -> Image.Image:
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    ordered = sorted(tiles, key=lambda tile: snapped_intensity(tile, t)[0])
    for tile in ordered:
        brightness, scale = snapped_intensity(tile, t)
        color = scale_rgb(tile["color"], brightness)
        cell_x, cell_y, x0, y0, x1, y1, cell_x1, cell_y1 = tile_box(tile["row"], tile["col"], scale)
        draw.rectangle((cell_x, cell_y, cell_x1, cell_y1), fill=GROUT_COLOR)
        draw_beveled_tile(draw, x0, y0, x1, y1, color)
    return im


def unique_colors(rgb_frames: list[Image.Image]) -> list[tuple[int, int, int]]:
    colors = {TRANSPARENT_KEY}
    for frame in rgb_frames:
        uniq = np.unique(np.array(frame).reshape(-1, 3), axis=0)
        for row in uniq:
            colors.add((int(row[0]), int(row[1]), int(row[2])))
    rest = sorted(c for c in colors if c != TRANSPARENT_KEY)
    palette = [TRANSPARENT_KEY, *rest]
    if len(palette) > 256:
        raise SystemExit(f"Too many colors for GIF palette: {len(palette)}")
    print(f"palette colors={len(palette)}")
    return palette


def to_indexed(rgb: Image.Image, palette: list[tuple[int, int, int]]) -> Image.Image:
    arr = np.array(rgb)
    index = np.zeros(arr.shape[:2], dtype=np.uint8)
    for i, color in enumerate(palette):
        match = np.all(arr == np.array(color, dtype=np.uint8), axis=-1)
        index[match] = i
    pal = Image.fromarray(index, mode="P")
    flat: list[int] = []
    for color in palette:
        flat.extend(color)
    flat.extend([0, 0, 0] * (256 - len(palette)))
    pal.putpalette(flat)
    pal.info["transparency"] = 0
    pal.info["disposal"] = 2
    return pal


def main() -> None:
    tiles = sample_tiles(Image.open(SOURCE))
    if not tiles:
        raise SystemExit("No mosaic tiles sampled from the app icon.")

    rgba_frames = [render_frame(tiles, i / FRAMES) for i in range(FRAMES)]
    rgb_frames: list[Image.Image] = []
    for frame in rgba_frames:
        bg = Image.new("RGB", frame.size, TRANSPARENT_KEY)
        bg.paste(frame, mask=frame.split()[-1])
        rgb_frames.append(bg)

    palette = unique_colors(rgb_frames)
    gif_frames = [to_indexed(frame, palette) for frame in rgb_frames]
    gif_frames[0].save(
        OUT_GIF,
        save_all=True,
        append_images=gif_frames[1:],
        duration=[FRAME_MS] * FRAMES,
        loop=0,
        disposal=2,
        transparency=0,
        optimize=False,
    )
    print(f"wrote {OUT_GIF} ({OUT_GIF.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
