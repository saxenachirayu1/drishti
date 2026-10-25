"""
Unicode font lookup for the complaint PDF (C-10, C-17).

The built-in PDF fonts are latin-1 only, so a Hindi complaint needs a real
Unicode TTF plus harfbuzz shaping (Devanagari reorders matras and builds
conjuncts).

Being a "Unicode font" is not enough: DejaVuSans and the plain Noto Sans that
Linux images ship carry no Devanagari glyphs at all, so a letter set in them
comes out as blank boxes - a broken complaint, emailed to a ward officer,
with nothing in the logs. So every candidate is checked for actual Devanagari
coverage and rejected if it has none.

Search order:
  - `api/fonts/` - drop any .ttf here and it wins (works everywhere)
  - the Noto Devanagari package the Dockerfile installs (Linux)
  - the system fonts macOS ships (local dev)

If nothing covers Devanagari, the caller falls back to the latin-1 core font
and says so in the PDF rather than emitting an unreadable one.
"""
import logging
import os

log = logging.getLogger("drishti.fonts")

_HERE = os.path.dirname(os.path.abspath(__file__))

# U+0915 DEVANAGARI LETTER KA - present in any font that can set Hindi.
DEVANAGARI_SAMPLE = 0x0915

CANDIDATES = [
    # bundled: drop a .ttf in api/fonts/ and it is used first
    os.path.join(_HERE, os.pardir, "fonts", "NotoSansDevanagari-Regular.ttf"),
    # Linux (installed by the Dockerfile: fonts-noto-devanagari)
    "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSerifDevanagari-Regular.ttf",
    # macOS
    "/System/Library/Fonts/Supplemental/Devanagari Sangam MN.ttc",
    "/System/Library/Fonts/Supplemental/DevanagariMT.ttc",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
]

_cached = False
_cached_path = None


def covers_devanagari(path: str) -> bool:
    """True if the font can actually set Devanagari, not merely be Unicode."""
    try:
        from fontTools.ttLib import TTFont

        font = TTFont(path, fontNumber=0, lazy=True)
        try:
            return any(DEVANAGARI_SAMPLE in t.cmap
                       for t in font["cmap"].tables if hasattr(t, "cmap"))
        finally:
            font.close()
    except Exception as e:
        log.debug("could not read %s: %s", path, e)
        return False


def find_unicode_font(refresh: bool = False):
    """Path to a font that can set Devanagari, or None. Result is cached."""
    global _cached, _cached_path
    if _cached and not refresh:
        return _cached_path

    _cached_path = None
    for path in CANDIDATES:
        path = os.path.normpath(path)
        if os.path.exists(path) and covers_devanagari(path):
            _cached_path = path
            break
        if os.path.exists(path):
            log.info("%s has no Devanagari glyphs; skipping", path)
    _cached = True
    if _cached_path is None:
        log.warning("no Devanagari font found; Hindi PDFs will say so instead "
                    "of rendering blank boxes (see api/fonts/README.md)")
    return _cached_path


def needs_unicode(text: str) -> bool:
    """True when `text` cannot be written with the latin-1 core fonts."""
    try:
        text.encode("latin-1")
        return False
    except UnicodeEncodeError:
        return True
