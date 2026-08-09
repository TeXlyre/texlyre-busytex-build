#!/usr/bin/env python3
"""Generate the XeTeX font catalogue served alongside the remote TeX Live tree."""

from __future__ import annotations

import argparse
import logging
import math
import os
from pathlib import Path
import sys

from fontTools.ttLib import TTCollection, TTFont, TTLibError

FORMAT_VERSION = 1
FONT_ROOTS = ("opentype", "truetype")
FONT_SUFFIXES = (".otf", ".ttf", ".otc", ".ttc")
NAME_FULL, NAME_FAMILY, NAME_STYLE, NAME_PS = 4, 1, 2, 6
NAME_PREFERRED_FAMILY, NAME_PREFERRED_STYLE = 16, 17
DECIPOINT_TO_TEXPOINT = 72.27 / 72.0 / 10.0


def sanitize(value: str) -> str:
    return " ".join(value.replace("|", " ").split())


def decode(record) -> str | None:
    try:
        return sanitize(str(record.toUnicode()))
    except Exception:
        return None


def is_preferred(record) -> bool:
    return record.platformID == 1 and record.platEncID == 0 and record.langID == 0


def collect_names(font: TTFont) -> tuple[str, list[str], list[str], list[str]]:
    buckets: dict[int, list[str]] = {
        NAME_FULL: [], NAME_FAMILY: [], NAME_STYLE: [],
        NAME_PREFERRED_FAMILY: [], NAME_PREFERRED_STYLE: [],
    }
    psname = ""

    for record in font["name"].names:
        if record.nameID == NAME_PS and not psname:
            decoded = decode(record)
            if decoded:
                psname = decoded
            continue
        bucket = buckets.get(record.nameID)
        if bucket is None or record.platformID not in (0, 1, 3):
            continue
        if record.platformID == 1 and not is_preferred(record):
            continue
        decoded = decode(record)
        if not decoded or decoded in bucket:
            continue
        if is_preferred(record):
            bucket.insert(0, decoded)
        else:
            bucket.append(decoded)

    families = buckets[NAME_PREFERRED_FAMILY] or buckets[NAME_FAMILY]
    styles = buckets[NAME_PREFERRED_STYLE] or buckets[NAME_STYLE]
    return psname, families, styles, buckets[NAME_FULL]


def collect_style_flags(font: TTFont) -> tuple[int, int, int, int, int, int]:
    weight = width = slant = 0
    is_regular = is_bold = is_italic = 0

    os2 = font.get("OS/2")
    if os2 is not None:
        weight = int(os2.usWeightClass)
        width = int(os2.usWidthClass)
        selection = int(os2.fsSelection)
        is_regular = int(bool(selection & (1 << 6)))
        is_bold = int(bool(selection & (1 << 5)))
        is_italic = int(bool(selection & (1 << 0)))

    head = font.get("head")
    if head is not None:
        mac_style = int(head.macStyle)
        is_bold |= int(bool(mac_style & (1 << 0)))
        is_italic |= int(bool(mac_style & (1 << 1)))

    post = font.get("post")
    if post is not None:
        slant = int(1000 * math.tan(math.radians(-float(post.italicAngle))))

    return weight, width, slant, is_regular, is_bold, is_italic


def collect_opsize(font: TTFont) -> tuple[float, float, float, int, int]:
    gpos = font.get("GPOS")
    if gpos is None or gpos.table is None or gpos.table.FeatureList is None:
        return 10.0, 0.0, 0.0, 0, 0

    for feature in gpos.table.FeatureList.FeatureRecord:
        if feature.FeatureTag != "size":
            continue
        params = feature.Feature.FeatureParams
        if params is None or not hasattr(params, "DesignSize"):
            continue
        return (
            params.DesignSize * DECIPOINT_TO_TEXPOINT,
            params.RangeStart * DECIPOINT_TO_TEXPOINT,
            params.RangeEnd * DECIPOINT_TO_TEXPOINT,
            int(params.SubfamilyID),
            int(params.SubfamilyNameID),
        )

    return 10.0, 0.0, 0.0, 0, 0


def face_count(path: Path) -> int:
    if path.suffix.lower() not in (".ttc", ".otc"):
        return 1
    with TTCollection(str(path), lazy=True) as collection:
        return len(collection.fonts)


def build_record(path: Path, face: int) -> str | None:
    with TTFont(str(path), fontNumber=face, lazy=True) as font:
        if "name" not in font:
            return None
        psname, families, styles, fullnames = collect_names(font)
        if not psname or not families:
            return None
        weight, width, slant, is_regular, is_bold, is_italic = collect_style_flags(font)
        design, minimum, maximum, subfamily_id, name_code = collect_opsize(font)

    if not fullnames:
        fullnames = [families[0] + ((" " + styles[0]) if styles else "")]

    return "\t".join([
        path.name, str(face), psname,
        str(weight), str(width), str(slant),
        str(is_regular), str(is_bold), str(is_italic),
        f"{design:.4f}", f"{minimum:.4f}", f"{maximum:.4f}",
        str(subfamily_id), str(name_code),
        "|".join(families), "|".join(styles), "|".join(fullnames),
    ])


def font_files(texmf_dist: Path) -> list[Path]:
    files: list[Path] = []
    for root in FONT_ROOTS:
        base = texmf_dist / "fonts" / root
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            for filename in sorted(filenames):
                if filename.lower().endswith(FONT_SUFFIXES):
                    files.append(Path(dirpath) / filename)
    return files


def build(texmf_dist: Path, output: Path) -> None:
    seen: set[str] = set()
    records: list[str] = []
    skipped = 0

    for path in font_files(texmf_dist):
        key = path.name.lower()
        if key in seen:
            continue
        seen.add(key)
        try:
            for face in range(face_count(path)):
                record = build_record(path, face)
                if record:
                    records.append(record)
        except (TTLibError, OSError, KeyError, AttributeError, ValueError):
            skipped += 1

    if not records:
        sys.exit(f"No usable faces found below {texmf_dist / 'fonts'}")

    records.sort()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"busytex-fontindex {FORMAT_VERSION}\n")
        for record in records:
            handle.write(record + "\n")

    print(f"{output}: {len(records)} faces, {skipped} unreadable files")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--texmf-dist", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


if __name__ == "__main__":
    logging.getLogger("fontTools").setLevel(logging.ERROR)
    args = parse_args()
    if not (args.texmf_dist / "fonts").is_dir():
        sys.exit(f"No font tree below {args.texmf_dist}")
    build(args.texmf_dist.resolve(), args.output.resolve())
