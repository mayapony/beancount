"""生成设计评审用的对比图（docs/review/compare.png 与 docs/review/annotated-current.png）。

素材来自 test/tools/capture_screens_test.dart 渲染出的 2x 截图。
运行：
    C:\\Users\\maya\\.dsh\\...\\python.exe docs/review/make_figures.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SHOTS = ROOT / "docs" / "review" / "shots"
OUT = ROOT / "docs" / "review"

FONT_BOLD = r"C:\Windows\Fonts\Noto Sans SC Bold (TrueType).otf"
FONT_REG = r"C:\Windows\Fonts\NotoSansSC-VF.ttf"

RED = (225, 29, 72)
SLATE = (120, 113, 108)
GREEN = (21, 128, 61)


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


# ── 问题区域（坐标基于 804×1748 的 2x 截图） ────────────────────────
# (编号, x0, y0, x1, y1)
ISSUES = [
    (1, 686, 350, 776, 446),   # 关闭入口 / 无标题
    (2, 22, 350, 184, 446),    # 支出 pill 过重
    (3, 24, 442, 800, 830),    # 分类区：色彩噪声 + 选中态
    (4, 24, 838, 800, 962),    # 5 列 12 项留下的空白
    (5, 24, 972, 412, 1052),   # 账户 / 日期 chip
    (6, 24, 1082, 800, 1244),  # 金额卡边界 + 双金色图标
    (7, 18, 1272, 800, 1582),  # 键帽不可见
    (8, 578, 1582, 800, 1702), # 完成按钮禁用态
]


def rounded_rect(draw, box, radius, color, width):
    draw.rounded_rectangle(box, radius=radius, outline=color, width=width)


def badge(draw, cx, cy, n):
    r = 19
    draw.ellipse((cx - r - 4, cy - r - 4, cx + r + 4, cy + r + 4),
                 fill=(255, 255, 255))
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=RED)
    f = font(FONT_BOLD, 23)
    text = str(n)
    w = draw.textlength(text, font=f)
    draw.text((cx - w / 2, cy - 15), text, font=f, fill=(255, 255, 255))


def annotate(img: Image.Image) -> Image.Image:
    im = img.convert("RGB").copy()
    d = ImageDraw.Draw(im)
    for n, x0, y0, x1, y1 in ISSUES:
        rounded_rect(d, (x0, y0, x1, y1), 14, RED, 4)
        badge(d, x0, y0, n)
    return im


def frame(img: Image.Image, width: int = 6) -> Image.Image:
    im = img.convert("RGB").copy()
    d = ImageDraw.Draw(im)
    rounded_rect(d, (0, 0, im.width - 1, im.height - 1), 18, (228, 222, 212),
                 width * 2)
    return im


def build_compare():
    current = Image.open(SHOTS / "00-before-default.png")
    after = Image.open(SHOTS / "01-entry-default.png")
    left = frame(annotate(current))
    right = frame(after)

    pad = 36
    caption_h = 66
    canvas = Image.new(
        "RGB",
        (pad * 3 + left.width + right.width, pad + caption_h + left.height + pad),
        (250, 247, 242),
    )
    d = ImageDraw.Draw(canvas)
    fb = font(FONT_BOLD, 30)

    d.text((pad, pad - 4), "改前：8 个硬伤", font=fb, fill=(28, 25, 23))
    d.text((pad * 2 + left.width, pad - 4), "改后：已落地（同结构，重排层级）",
           font=fb, fill=GREEN)

    y = pad + caption_h
    canvas.paste(left, (pad, y))
    canvas.paste(right, (pad * 2 + left.width, y))
    canvas.save(OUT / "compare.png")
    print("wrote", OUT / "compare.png", canvas.size)


def build_title_compare():
    """果味/标题方向的对照图：改前（标题常驻、卡片阴影）vs 改后（月份当标题、分组列表）。

    左边是从旧版截图里留下的 `00-before-home.png`（页面重做前的 402×874 渲染）。
    """
    current = Image.open(SHOTS / "00-before-home.png")
    after = Image.open(SHOTS / "10-home-current.png")
    left = frame(current)
    right = frame(after)

    pad = 36
    caption_h = 66
    canvas = Image.new(
        "RGB",
        (pad * 3 + left.width + right.width, pad + caption_h + left.height + pad),
        (250, 247, 242),
    )
    d = ImageDraw.Draw(canvas)
    fb = font(FONT_BOLD, 30)

    d.text((pad, pad - 4), "改前：标题常驻 · 卡片阴影 · 15px 正文", font=fb,
           fill=(28, 25, 23))
    d.text((pad * 2 + left.width, pad - 4), "改后：月份当标题 · 分组列表 · 凹槽保留",
           font=fb, fill=GREEN)

    y = pad + caption_h
    canvas.paste(left, (pad, y))
    canvas.paste(right, (pad * 2 + left.width, y))
    canvas.save(OUT / "title-compare.png")
    print("wrote", OUT / "title-compare.png", canvas.size)


def build_annotated():
    img = annotate(Image.open(SHOTS / "00-before-default.png"))
    img.save(OUT / "annotated-current.png")
    print("wrote", OUT / "annotated-current.png", img.size)


if __name__ == "__main__":
    build_annotated()
    build_compare()
    build_title_compare()
