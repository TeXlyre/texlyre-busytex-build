#!/usr/bin/env python3
"""Wire the remote font catalogue into XeTeX's fontconfig font manager."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

MARKER = "busytex"

FONT_MGR = "texk/web2c/xetexdir/XeTeXFontMgr_FC.cpp"
LAYOUT = "texk/web2c/xetexdir/XeTeXLayoutInterface.cpp"

FONT_INDEX_DECLARATIONS = '''#include "XeTeXFontMgr_FC.h"

extern "C" {
int busytex_font_index_load(void);
int busytex_font_index_count(void);
const char *busytex_font_index_file(int entry);
int busytex_font_index_face(int entry);
const char *busytex_font_index_psname(int entry);
void busytex_font_index_style(int entry, int *weight, int *width, int *slant,
                              int *is_regular, int *is_bold, int *is_italic);
void busytex_font_index_opsize(int entry, double *design_size, double *min_size,
                               double *max_size, int *subfamily_id, int *name_code);
int busytex_font_index_name_count(int entry, int kind);
const char *busytex_font_index_name(int entry, int kind, int position);
}

#define BUSYTEX_FONT_INDEX_OBJECT "busytexfontindex"

static bool busytexFontIndexLoaded = false;
'''

STYLE_FROM_INDEX = '''    int busytexEntry;
    if (FcPatternGetInteger(theFont->fontRef, BUSYTEX_FONT_INDEX_OBJECT, 0, &busytexEntry) == FcResultMatch) {
        int weight, width, slant, isReg, isBold, isItalic, subFamilyID, nameCode;
        double designSize, minSize, maxSize;

        busytex_font_index_style(busytexEntry, &weight, &width, &slant, &isReg, &isBold, &isItalic);
        busytex_font_index_opsize(busytexEntry, &designSize, &minSize, &maxSize, &subFamilyID, &nameCode);

        theFont->weight = (uint16_t) weight;
        theFont->width = (uint16_t) width;
        theFont->slant = (int16_t) slant;
        theFont->isReg = isReg != 0;
        theFont->isBold = isBold != 0;
        theFont->isItalic = isItalic != 0;
        theFont->opSizeInfo.designSize = designSize;
        theFont->opSizeInfo.minSize = minSize;
        theFont->opSizeInfo.maxSize = maxSize;
        theFont->opSizeInfo.subFamilyID = (unsigned int) subFamilyID;
        theFont->opSizeInfo.nameCode = (unsigned int) nameCode;
        return;
    }

    XeTeXFontMgr::getOpSizeRecAndStyleFlags(theFont);'''

SEARCH_TAIL_ANCHOR = '''        if (found || cachedAll)
            break;
        cachedAll = true;
    }
}'''

SEARCH_TAIL_PATCHED = '''        if (found || cachedAll)
            break;
        cachedAll = true;
    }

    if (busytexFontIndexLoaded || !busytex_font_index_load())
        return;

    busytexFontIndexLoaded = true;

    for (int entry = 0; entry < busytex_font_index_count(); ++entry) {
        FcPattern* pat = FcPatternCreate();
        FcPatternAddString(pat, FC_FILE, (const FcChar8*) busytex_font_index_file(entry));
        FcPatternAddInteger(pat, FC_INDEX, busytex_font_index_face(entry));
        FcPatternAddInteger(pat, BUSYTEX_FONT_INDEX_OBJECT, entry);

        NameCollection* names = new NameCollection;
        names->m_psName = busytex_font_index_psname(entry);

        for (int kind = 0; kind < 3; ++kind) {
            std::list<std::string>* list = (kind == 0) ? &names->m_familyNames
                                         : (kind == 1) ? &names->m_styleNames
                                                       : &names->m_fullNames;
            for (int j = 0; j < busytex_font_index_name_count(entry, kind); ++j)
                list->push_back(busytex_font_index_name(entry, kind, j));
        }

        addToMaps(pat, names);
        delete names;
    }
}'''

LAYOUT_DECLARATIONS = '''#include "XeTeXFontMgr.h"

#include <string.h>
#include <stdlib.h>

extern "C" char *kpse_find_file(const char *name, int format, int must_exist);

#define BUSYTEX_KPSE_TRUETYPE_FORMAT 36
#define BUSYTEX_KPSE_OPENTYPE_FORMAT 47
'''

CREATE_FONT_ANCHOR = '''    FcChar8* pathname = 0;
    FcPatternGetString(fontRef, FC_FILE, 0, &pathname);
    int index;
    FcPatternGetInteger(fontRef, FC_INDEX, 0, &index);
    XeTeXFontInst* font = new XeTeXFontInst((const char*)pathname, index, Fix2D(pointSize), status);'''

CREATE_FONT_PATCHED = '''    FcChar8* pathname = 0;
    FcPatternGetString(fontRef, FC_FILE, 0, &pathname);
    int index;
    FcPatternGetInteger(fontRef, FC_INDEX, 0, &index);
    if (pathname == 0)
        return NULL;
    char* resolved = NULL;
    if (strchr((const char*)pathname, '/') == NULL) {
        resolved = kpse_find_file((const char*)pathname, BUSYTEX_KPSE_OPENTYPE_FORMAT, 0);
        if (resolved == NULL)
            resolved = kpse_find_file((const char*)pathname, BUSYTEX_KPSE_TRUETYPE_FORMAT, 0);
        if (resolved == NULL)
            return NULL;
    }
    XeTeXFontInst* font = new XeTeXFontInst(resolved ? resolved : (const char*)pathname, index, Fix2D(pointSize), status);
    free(resolved);'''

EDITS = {
    FONT_MGR: (
        ('#include "XeTeXFontMgr_FC.h"\n', FONT_INDEX_DECLARATIONS),
        ('    XeTeXFontMgr::getOpSizeRecAndStyleFlags(theFont);', STYLE_FROM_INDEX),
        (SEARCH_TAIL_ANCHOR, SEARCH_TAIL_PATCHED),
    ),
    LAYOUT: (
        ('#include "XeTeXFontMgr.h"\n', LAYOUT_DECLARATIONS),
        (CREATE_FONT_ANCHOR, CREATE_FONT_PATCHED),
    ),
}


def patch(root: Path) -> None:
    for relative, edits in EDITS.items():
        path = root / relative
        if not path.is_file():
            sys.exit(f"Missing source file: {path}")

        text = path.read_text(encoding="utf-8")
        if MARKER in text.lower():
            print(f"{relative}: already patched")
            continue

        for anchor, replacement in edits:
            occurrences = text.count(anchor)
            if occurrences != 1:
                sys.exit(f"{relative}: anchor found {occurrences} times, expected 1:\n{anchor}")
            text = text.replace(anchor, replacement)

        path.write_text(text, encoding="utf-8")
        print(f"{relative}: patched")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--texlive-source", type=Path, required=True)
    return parser.parse_args()


if __name__ == "__main__":
    patch(parse_args().texlive_source)
