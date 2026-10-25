"""
Unicode font lookup for the complaint PDF (C-10, C-17).

The built-in PDF fonts are latin-1 only, so a Hindi complaint needs a real
Unicode TTF plus harfbuzz shaping (Devanagari reorders matras and builds
conjuncts). We look for a Devanagari font in the usual places:

  - `api/fonts/` — drop any .ttf here and it wins (works everywhere)
  - the Noto package the Dockerfile installs (Linux)
  - the system fonts macOS ships (local dev)

If none is found, the caller falls back to the latin-1 core font and says so
rather than crashing.
"""
import os

_HERE = os.path.dirname(os.path.abspath(__file__))

CANDIDATES = [
    # bundled: drop a .ttf in api/fonts/ and it is used first
    os.path.join(_HERE, os.pardir, "fonts", "NotoSansDevanagari-Regular.ttf"),
    # Linux (installed by the Dockerfile)
    "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    # macOS
    "/System/Library/Fonts/Supplemental/Devanagari Sangam MN.ttc",
    "/System/Library/Fonts/Supplemental/DevanagariMT.ttc",
]


def find_unicode_font():
    """Absolute path to a usable Unicode font, or None."""
    for path in CANDIDATES:
        path = os.path.normpath(path)
        if os.path.exists(path):
            return path
    return None


def needs_unicode(text: str) -> bool:
    """True when `text` cannot be written with the latin-1 core fonts."""
    try:
        text.encode("latin-1")
        return False
    except UnicodeEncodeError:
        return True
