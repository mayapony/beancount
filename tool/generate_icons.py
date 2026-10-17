"""生成「金豆」品牌图标：Android 五密度 + Web favicon / 192 / 512 / maskable。

用法（仓库根目录）：
    python tool/generate_icons.py

颜色取自设计 token：暖砂底 + 金色豆子 + 一点豆绿叶子。
所有尺寸由同一张 1024 母版下采样，避免每次重画导致像素差异。
"""

from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

SAND = (250, 247, 240, 255)      # 暖砂底（页面底色）
GOLD = (232, 163, 61, 255)       # 金色豆子（品牌主色）
GOLD_DEEP = (196, 128, 32, 255)  # 豆缝
LEAF = (58, 150, 104, 255)       # 豆绿（叶子）
WHITE = (255, 255, 255, 255)

MASTER = 1024


def _rotate(point: tuple[float, float], angle: float) -> tuple[float, float]:
    c, s = math.cos(angle), math.sin(angle)
    x, y = point
    return (x * c - y * s, x * s + y * c)


def draw_master(padding_ratio: float = 0.0) -> Image.Image:
    """画 1024 的母版。padding_ratio 用于 maskable 图标（留安全边）。"""
    canvas = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    inset = int(MASTER * padding_ratio)
    size = MASTER - inset * 2

    # 圆角方底
    draw.rounded_rectangle(
        [inset, inset, inset + size, inset + size],
        radius=int(size * 0.22),
        fill=SAND,
    )

    # 豆子：倾斜的椭圆
    angle = math.radians(-20)
    cx, cy = MASTER / 2, MASTER / 2
    rx, ry = size * 0.30, size * 0.23
    points = []
    for i in range(120):
        t = 2 * math.pi * i / 120
        px, py = rx * math.cos(t), ry * math.sin(t)
        dx, dy = _rotate((px, py), angle)
        points.append((cx + dx, cy + dy))
    draw.polygon(points, fill=GOLD)

    # 豆缝：沿长轴的一道深金弧
    seam = []
    for i in range(60):
        t = math.pi * (0.15 + 0.7 * i / 59)
        px = rx * 0.72 * math.cos(t)
        py = ry * 0.16 * math.sin(t) - ry * 0.30
        dx, dy = _rotate((px, py), angle)
        seam.append((cx + dx, cy + dy))
    draw.line(seam, fill=GOLD_DEEP, width=max(6, int(size * 0.014)), joint="curve")

    # 高光：沿长轴的椭圆，贴近豆子上缘
    hl = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        px = -rx * 0.26 + rx * 0.13 * math.cos(t)
        py = -ry * 0.40 + ry * 0.09 * math.sin(t)
        dx, dy = _rotate((px, py), angle)
        hl.append((cx + dx, cy + dy))
    draw.polygon(hl, fill=(255, 255, 255, 165))

    # 叶子：一小片从豆子右上角冒出来
    if size >= 300:
        leaf_box = [
            cx + size * 0.13,
            cy - size * 0.33,
            cx + size * 0.31,
            cy - size * 0.17,
        ]
        draw.ellipse(leaf_box, fill=LEAF)
        stem = [(cx + size * 0.16, cy - size * 0.22), (cx + size * 0.20, cy - size * 0.10)]
        draw.line(stem, fill=LEAF, width=max(4, int(size * 0.010)))

    return canvas


def save(image: Image.Image, size: int, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path, format="PNG")
    print(f"{path.relative_to(ROOT)}  {size}x{size}")


def main() -> None:
    master = draw_master()
    maskable = draw_master(padding_ratio=0.16)

    android = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in android.items():
        save(
            master,
            size,
            ROOT / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png",
        )

    save(master, 32, ROOT / "web" / "favicon.png")
    save(master, 192, ROOT / "web" / "icons" / "Icon-192.png")
    save(master, 512, ROOT / "web" / "icons" / "Icon-512.png")
    save(maskable, 192, ROOT / "web" / "icons" / "Icon-maskable-192.png")
    save(maskable, 512, ROOT / "web" / "icons" / "Icon-maskable-512.png")

    # 顺带留一张预览，方便在 doc/评审里看
    preview = ROOT / "build" / "icon-preview.png"
    preview.parent.mkdir(parents=True, exist_ok=True)
    save(master, 256, preview)


if __name__ == "__main__":
    main()
