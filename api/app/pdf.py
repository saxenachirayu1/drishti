"""Complaint PDF generation (C-10), Hindi included (C-17)."""
import os

from fpdf import FPDF
from fpdf.enums import XPos, YPos

from .fonts import find_unicode_font, needs_unicode

OUT_DIR = os.getenv("PDF_OUT_DIR", "out")

TITLES = {
    "Hindi": "प्रोजेक्ट दृष्टि - नगरपालिका शिकायत",
    "English": "Project Drishti - Municipal Complaint",
}

# Shown instead of the Hindi body when no Unicode font is installed.
NO_FONT_NOTICE = (
    "[This complaint was drafted in Hindi. No Devanagari font is installed on "
    "the server, so the Hindi text could not be rendered into this PDF. The "
    "full Hindi text is stored on the complaint record and was emailed to the "
    "ward officer. See api/fonts/README.md to install the font.]"
)


def _setup_font(pdf: FPDF, text: str):
    """Register a Unicode font if `text` needs one. Returns (family, ok)."""
    if not needs_unicode(text):
        return "Helvetica", True
    path = find_unicode_font()
    if not path:
        return "Helvetica", False
    pdf.add_font("drishti", "", path)
    pdf.set_text_shaping(True)   # Devanagari needs harfbuzz shaping
    return "drishti", True


def make_complaint_pdf(complaint_id: str, text: str, language: str = "English") -> str:
    os.makedirs(OUT_DIR, exist_ok=True)
    pdf = FPDF()
    pdf.set_left_margin(18)
    pdf.set_right_margin(18)
    pdf.add_page()

    title = TITLES.get(language, TITLES["English"])
    family, ok = _setup_font(pdf, text + title)
    if not ok:
        # No Unicode font: keep the PDF valid and explain the gap.
        title = TITLES["English"]
        text = NO_FONT_NOTICE

    pdf.set_font(family, "B" if family == "Helvetica" else "", 14)
    pdf.set_x(pdf.l_margin)
    pdf.multi_cell(0, 9, title, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.ln(4)

    pdf.set_font(family, size=11)
    for line in text.split("\n"):
        if line.strip() == "":
            pdf.ln(6)
        else:
            pdf.set_x(pdf.l_margin)
            pdf.multi_cell(0, 7, line, new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    path = os.path.join(OUT_DIR, f"complaint_{complaint_id}.pdf")
    pdf.output(path)
    return path
