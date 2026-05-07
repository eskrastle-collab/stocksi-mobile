"""
Сборка маркетинговых скриншотов для App Store Connect.

Берёт raw-скрины iPhone Pro Max из source/, накладывает тёмный брендовый фон
+ tagline сверху, скругляет углы скрина и добавляет тень. Сохраняет 2 набора:

  final/6.9/ — 1320×2868 (iPhone 16 Pro Max — основной обязательный размер)
  final/6.5/ — 1242×2688 (iPhone 11 Pro Max / XS Max — fallback вкладка ASC)

App Store Connect требует один из размеров на screenshot tab. Если у тебя
видна только вкладка 6.5" — грузи из final/6.5/, если 6.9" — из final/6.9/.

Использование:
  1. Скинь в C:\\Users\\eskra\\Downloads\\appstore-screenshots\\source\\
     5 файлов с именами:
       01_dark.png       — лента в тёмной теме
       02_light.png      — лента в светлой теме
       03_sound.png      — настройки → уведомления → звуки
       04_filter.png     — настройки → фильтры (с DSL подсветки)
       05_sources.png    — настройки → источники
  2. Запусти:
       PYTHONIOENCODING=utf-8 python scripts/make_appstore_screenshots.py
  3. Готовые файлы появятся в
     C:\\Users\\eskra\\Downloads\\appstore-screenshots\\final\\6.9\\
     C:\\Users\\eskra\\Downloads\\appstore-screenshots\\final\\6.5\\
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ── Параметры ──────────────────────────────────────────────────────────────
APPSTORE_DIR = Path(r"C:\Users\eskra\Downloads\appstore-screenshots")
SRC_DIR = APPSTORE_DIR / "source"
OUT_DIR = APPSTORE_DIR / "final"

# Размеры под App Store Connect screenshot tabs
SIZES = {
    "6.9": (1320, 2868),       # iPhone 16 Pro Max — основной
    "6.5": (1242, 2688),       # iPhone 11 Pro Max / XS Max — fallback
    "ipad-13": (2064, 2752),   # iPad Pro 13" — обязательный для universal app
}

# База для масштабирования геометрии (соответствует 6.9")
BASE_H = 2868

# Брендовая палитра (совпадает с тёмной темой приложения)
BG_TOP = (15, 23, 33)        # #0F1721 — тёмно-синий, ближе к черному
BG_BOTTOM = (28, 41, 58)     # #1C293A — чуть светлее, для градиента
ACCENT = (98, 161, 255)      # #62A1FF — голубой как у extension
WHITE = (235, 240, 248)
SUB_GREY = (140, 167, 190)   # для подзаголовка

# Базовая геометрия (для 6.9", остальные размеры пропорционально масштабируются)
BASE_PAD_TOP = 200          # отступ сверху до tagline
BASE_TAGLINE_GAP = 56       # между tagline и subtitle
BASE_SCREEN_TOP = 480       # где начинается скрин телефона
BASE_SCREEN_TARGET_H = 2280 # высота скрина в финальной картинке (≈80% полотна)
BASE_CORNER_RADIUS = 64     # скругление углов скрина
BASE_SHADOW_BLUR = 50
SHADOW_OFFSET = 0
SHADOW_OPACITY = 110        # 0..255
BASE_FONT_TAGLINE = 78
BASE_FONT_SUBTITLE = 44

# Шрифты Windows (есть на любой Win-машине)
FONT_BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_REG = r"C:\Windows\Fonts\segoeui.ttf"

# 5 скринов — порядок и подписи
SCREENSHOTS = [
    {
        "src": "01_dark.png",
        "out": "01_news_dark.png",
        "tagline": "Лента биржевых новостей",
        "subtitle": "В реальном времени через WebSocket",
    },
    {
        "src": "02_light.png",
        "out": "02_themes.png",
        "tagline": "Тёмная и светлая темы",
        "subtitle": "Переключение в одно касание",
    },
    {
        "src": "03_sound.png",
        "out": "03_sound_alerts.png",
        "tagline": "Свой звук для каждого триггера",
        "subtitle": "Алерты по хэштегам",
    },
    {
        "src": "04_filter.png",
        "out": "04_filters_highlight.png",
        "tagline": "Фильтры и подсветка",
        "subtitle": "Свой DSL для ключевых слов",
    },
    {
        "src": "05_sources.png",
        "out": "05_sources.png",
        "tagline": "Десятки источников",
        "subtitle": "Эмитенты, агентства, тг-каналы и прочие",
    },
]


# ── Helpers ────────────────────────────────────────────────────────────────
def vertical_gradient(size: tuple[int, int], top: tuple[int, int, int],
                       bottom: tuple[int, int, int]) -> Image.Image:
    """Простой вертикальный градиент top -> bottom."""
    w, h = size
    bg = Image.new("RGB", size, top)
    px = bg.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return bg


def round_corners(im: Image.Image, radius: int) -> Image.Image:
    """Возвращает RGBA-картинку с скруглёнными углами."""
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.width, im.height), radius=radius, fill=255
    )
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def make_shadow(size: tuple[int, int], radius: int, blur: int,
                opacity: int) -> Image.Image:
    """Готовая тень-свечение для прямоугольника size с радиусом скруглений."""
    pad = blur * 2
    sh = Image.new("RGBA", (size[0] + pad * 2, size[1] + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        (pad, pad, pad + size[0], pad + size[1]),
        radius=radius,
        fill=(0, 0, 0, opacity),
    )
    return sh.filter(ImageFilter.GaussianBlur(blur))


def draw_centered_text(draw: ImageDraw.ImageDraw, text: str, y: int,
                        font: ImageFont.FreeTypeFont,
                        color: tuple[int, int, int], canvas_w: int) -> int:
    """Рисует строку по центру горизонтали. Возвращает высоту строки."""
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    draw.text(((canvas_w - text_w) // 2, y), text, fill=color, font=font)
    return text_h


# ── Pipeline ───────────────────────────────────────────────────────────────
def render_one(src_path: Path, out_path: Path, tagline: str, subtitle: str,
               canvas_size: tuple[int, int]):
    print(f"  -> {out_path.name}")

    # Масштаб геометрии относительно базового 6.9"
    scale = canvas_size[1] / BASE_H
    pad_top = int(BASE_PAD_TOP * scale)
    tagline_gap = int(BASE_TAGLINE_GAP * scale)
    screen_top = int(BASE_SCREEN_TOP * scale)
    screen_target_h = int(BASE_SCREEN_TARGET_H * scale)
    corner_radius = int(BASE_CORNER_RADIUS * scale)
    shadow_blur = int(BASE_SHADOW_BLUR * scale)
    font_tagline_size = int(BASE_FONT_TAGLINE * scale)
    font_subtitle_size = int(BASE_FONT_SUBTITLE * scale)
    side_padding = int(80 * scale)

    canvas = vertical_gradient(canvas_size, BG_TOP, BG_BOTTOM)
    draw = ImageDraw.Draw(canvas)

    font_tagline = ImageFont.truetype(FONT_BOLD, font_tagline_size)
    font_subtitle = ImageFont.truetype(FONT_REG, font_subtitle_size)

    # Tagline + subtitle сверху
    y = pad_top
    h = draw_centered_text(draw, tagline, y, font_tagline, WHITE, canvas_size[0])
    y += h + tagline_gap
    draw_centered_text(draw, subtitle, y, font_subtitle, SUB_GREY, canvas_size[0])

    # Загрузить и подготовить скрин
    src = Image.open(src_path).convert("RGB")
    aspect = src.width / src.height
    target_h = screen_target_h
    target_w = int(target_h * aspect)

    # Если скрин получится шире холста минус padding — ресайз по ширине
    max_w = canvas_size[0] - side_padding
    if target_w > max_w:
        target_w = max_w
        target_h = int(target_w / aspect)
    src = src.resize((target_w, target_h), Image.LANCZOS)

    sx = (canvas_size[0] - target_w) // 2
    sy = screen_top

    # Тень-свечение под скрин
    shadow = make_shadow((target_w, target_h), corner_radius, shadow_blur,
                         SHADOW_OPACITY)
    canvas.paste(shadow,
                 (sx - shadow_blur * 2 + SHADOW_OFFSET,
                  sy - shadow_blur * 2 + SHADOW_OFFSET),
                 shadow)

    # Скрин со скруглёнными углами
    rounded = round_corners(src, corner_radius)
    canvas.paste(rounded, (sx, sy), rounded)

    canvas.save(out_path, "PNG", optimize=True)


def main():
    if not SRC_DIR.exists():
        print(f"!! Source dir not found: {SRC_DIR}")
        print(f"   Create it and put files: {[s['src'] for s in SCREENSHOTS]}")
        return

    missing = [s["src"] for s in SCREENSHOTS if not (SRC_DIR / s["src"]).exists()]
    if missing:
        print(f"!! Missing source files in {SRC_DIR}:")
        for m in missing:
            print(f"   - {m}")
        return

    for size_label, canvas_size in SIZES.items():
        out_subdir = OUT_DIR / size_label
        out_subdir.mkdir(parents=True, exist_ok=True)
        print(f"Rendering {len(SCREENSHOTS)} screenshots {canvas_size[0]}x{canvas_size[1]} -> {out_subdir}")
        for s in SCREENSHOTS:
            render_one(SRC_DIR / s["src"], out_subdir / s["out"],
                       s["tagline"], s["subtitle"], canvas_size)
    print("Done!")


if __name__ == "__main__":
    main()
