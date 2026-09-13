#!/usr/bin/env python3
"""Inject the ZCode mark (U+E90F) into the vendored Omarchy menu icon font.

The vendored font ships one glyph per app (U+E900..U+E90E, catalogued in
default/fonts/omarchy/README.md); ZCode has none, so its Install -> AI entry
would fall back to the fallback font family's generic glyph. The mark is
traced from the vendor's official app icon (pkgs/omarchy-icons/zcode.svg) and
fitted to the same optical box as the other marks: 896x896 centred in a 1024
upm em, advance 1024.

Usage: inject-glyph.py <font-in.ttf> <mark.svg> <font-out.ttf>

Two fontTools details worth keeping:

  - glyf.__setitem__ already appends the name to the glyph order, and the
    font-level order aliases that list: appending again duplicates the name
    and trips maxp's len(glyphOrder) == len(glyphs) assertion.
  - the font carries a byte-encoded (format 0) cmap subtable, which cannot
    hold a private-use codepoint; only the 16/32-bit subtables get the
    mapping.
"""

import re
import sys

from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import parse_path
from fontTools.ttLib import TTFont

CODEPOINT = 0xE90F
GLYPH_NAME = "zcode"
EM = 1024
BOX = 896
MARGIN = (EM - BOX) // 2


def main(font_path, mark_path, out_path):
    pathdef = re.search(r'\sd="([^"]+)"', open(mark_path).read()).group(1)

    bounds = BoundsPen(None)
    parse_path(pathdef, bounds)
    x_min, y_min, x_max, y_max = bounds.bounds
    width, height = x_max - x_min, y_max - y_min

    scale = BOX / max(width, height)
    pad_x = (BOX - width * scale) / 2
    pad_y = (BOX - height * scale) / 2
    transform = Transform(
        scale,
        0,
        0,
        -scale,
        MARGIN + pad_x - x_min * scale,
        MARGIN + pad_y + y_max * scale,
    )

    glyph_pen = TTGlyphPen(None)
    parse_path(pathdef, TransformPen(glyph_pen, transform))
    glyph = glyph_pen.glyph()

    # recalcTimestamp=False keeps head.modified as vendored, so the patched
    # font is byte-reproducible.
    font = TTFont(font_path, recalcTimestamp=False)
    glyph.recalcBounds(font["glyf"])
    font["glyf"][GLYPH_NAME] = glyph
    font["hmtx"][GLYPH_NAME] = (EM, glyph.xMin)
    font.glyphOrder = font["glyf"].glyphOrder
    for table in font["cmap"].tables:
        if table.format != 0:
            table.cmap[CODEPOINT] = GLYPH_NAME
    font.recalcBBoxes = True
    font.save(out_path)

    check = TTFont(out_path)
    assert check.getBestCmap()[CODEPOINT] == GLYPH_NAME, "glyph did not survive the save"
    print(
        f"{out_path}: U+{CODEPOINT:04X} -> {GLYPH_NAME} "
        f"bbox=({glyph.xMin},{glyph.yMin})-({glyph.xMax},{glyph.yMax})"
    )


if __name__ == "__main__":
    main(*sys.argv[1:4])
