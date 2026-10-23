Drop a Unicode TTF named `NotoSansDevanagari-Regular.ttf` here to guarantee
Hindi complaint PDFs (C-17) render on any machine:

    curl -LO https://github.com/notofonts/devanagari/raw/main/fonts/NotoSansDevanagari/hinted/ttf/NotoSansDevanagari-Regular.ttf

Without it the app falls back to a system Devanagari font (macOS) or the
`fonts-noto-devanagari` package the Dockerfile installs (Linux). If no font is
found at all, the PDF is written in English and says so; the Hindi text is
still stored on the complaint record and emailed.
