"""Генерирует PNG-иконки приложения из SVG-логотипа."""
from pathlib import Path
import io

from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "flutter-app" / "assets" / "logo_u.svg"
ASSETS = ROOT / "flutter-app" / "assets"
TARGET_SIZE = 1024
PADDING = 180


def render_svg_to_png(svg_text: str, size: int) -> Image.Image:
    """SVG string → PIL RGBA Image."""
    drawing = svg2rlg(io.StringIO(svg_text))
    # scale drawing to target size
    scale_x = size / drawing.width
    scale_y = size / drawing.height
    scale = min(scale_x, scale_y)
    drawing.width = size
    drawing.height = size
    drawing.scale(scale, scale)
    buf = io.BytesIO()
    renderPM.drawToFile(drawing, buf, fmt="PNG", dpi=72, bg=0x00000000)
    buf.seek(0)
    return Image.open(buf).convert("RGBA")


U_PATH = 'd="M814.11 1749.73C683.766 1749.73 580.926 1732.99 505.589 1699.51C430.252 1664.83 376.44 1612.81 344.153 1543.45C311.866 1474.1 295.723 1386.8 295.723 1281.57V458.247H582.719V1281.57C582.719 1372.45 603.646 1434.63 645.5 1468.12C688.549 1500.4 760.896 1516.55 862.541 1516.55H1208.73C1310.38 1516.55 1382.12 1500.4 1423.98 1468.12C1467.03 1434.63 1488.55 1372.45 1488.55 1281.57V458.247H1775.55V1281.57C1775.55 1386.8 1759.41 1474.1 1727.12 1543.45C1694.83 1612.81 1641.02 1664.83 1565.68 1699.51C1490.35 1732.99 1387.51 1749.73 1257.16 1749.73H814.11Z"'


def foreground_svg(size: int, pad: int) -> str:
    inner = size - 2 * pad
    scale = inner / 1716
    return f'''<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g" x1="{size-100}" y1="{size-100}" x2="0" y2="0" gradientUnits="userSpaceOnUse">
      <stop stop-color="#2C36FF"/>
      <stop offset="0.47" stop-color="#8D02FF"/>
      <stop offset="1" stop-color="#FF1861"/>
    </linearGradient>
  </defs>
  <g transform="translate({pad}, {pad}) scale({scale:.5f}) translate(-176, -243)">
    <path {U_PATH} fill="url(#g)"/>
  </g>
</svg>'''


def main():
    out_dir = ASSETS / "icon"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Foreground: только U на прозрачном
    fg_img = render_svg_to_png(foreground_svg(TARGET_SIZE, PADDING + 80), TARGET_SIZE)
    fg_img.save(out_dir / "app_icon_foreground.png")
    print(f"[ok] {out_dir / 'app_icon_foreground.png'}")

    # Full icon: тёмный фон со скруглением + U сверху
    bg = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0x15, 0x1F, 0x2A, 255))
    # Rounded rect mask
    mask = Image.new("L", (TARGET_SIZE, TARGET_SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (TARGET_SIZE, TARGET_SIZE)], radius=180, fill=255)
    bg.putalpha(mask)

    u_img = render_svg_to_png(foreground_svg(TARGET_SIZE, PADDING), TARGET_SIZE)
    bg.alpha_composite(u_img)
    bg.save(out_dir / "app_icon.png")
    print(f"[ok] {out_dir / 'app_icon.png'}")


if __name__ == "__main__":
    main()
