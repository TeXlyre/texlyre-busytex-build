#!/bin/sh
# Verifies that the artifacts font-name resolution depends on are present and sane.
set -eu

MODE=${1:?Usage: $0 full|wasm}

INDEX_MIN_RECORDS=1000
INDEX_RECORDS=0
INDEX_KNOWN_FILES='texgyrepagella-regular.otf latinmodern-math.otf'
MAP_MIN_LINES=2000
DB_MIN_ENTRIES=100
DB_MIN_RATIO=2

fail() {
    echo "check_font_assets: $1" >&2
    exit 1
}

check_index() {
    index=$1
    [ -f "$index" ] || fail "missing font index at $index"
    head -n 1 "$index" | grep -q '^busytex-fontindex 1$' \
        || fail "$index has no recognised header"

    records=$(($(wc -l < "$index") - 1))
    INDEX_RECORDS=$records
    [ "$records" -ge "$INDEX_MIN_RECORDS" ] \
        || fail "$index holds $records faces, expected at least $INDEX_MIN_RECORDS"

    malformed=$(awk -F'\t' 'NR > 1 && NF != 17' "$index" | wc -l)
    [ "$malformed" -eq 0 ] || fail "$index has $malformed malformed records"

    for known in $INDEX_KNOWN_FILES; do
        cut -f1 "$index" | grep -qx "$known" \
            || fail "$index does not list $known"
    done

    echo "check_font_assets: index ok, $records faces"
}

check_map() {
    map=$1
    [ -f "$map" ] || fail "missing pdftex.map at $map"
    lines=$(grep -c . "$map" || true)
    [ "$lines" -ge "$MAP_MIN_LINES" ] \
        || fail "$map holds $lines entries, expected at least $MAP_MIN_LINES"
    echo "check_font_assets: pdftex.map ok, $lines entries"
}

db_entries() {
    case $1 in
        *.gz) gzip -dc "$1" | grep -o basename | wc -l ;;
        *)    grep -o basename < "$1" | wc -l ;;
    esac
}

check_db() {
    db=$1
    conf=$2
    expected=${3:-0}
    [ -f "$db" ] || fail "missing luaotfload database at $db"
    entries=$(db_entries "$db")
    [ "$entries" -ge "$DB_MIN_ENTRIES" ] \
        || fail "$db holds $entries entries, expected at least $DB_MIN_ENTRIES"
    if [ "$expected" -gt 0 ]; then
        floor=$((expected / DB_MIN_RATIO))
        [ "$entries" -ge "$floor" ] \
            || fail "$db holds $entries entries against $expected indexed faces, the scan missed most of the tree"
    fi
    [ -f "$conf" ] || fail "missing luaotfload.conf at $conf"
    grep -q 'location-precedence *= *texmf' "$conf" \
        || fail "$conf does not pin location-precedence to texmf"
    grep -q 'update-live *= *false' "$conf" \
        || fail "$conf does not disable live updates, a rescan would discard the generated database"
    cmp -s "$conf" luaotfload.conf \
        || fail "$conf differs from the luaotfload.conf in this checkout"
    echo "check_font_assets: luaotfload database ok, $entries entries"
}

case $MODE in
    full)
        TEXMFDIST=${2:-build/texlive-full/texmf-dist}
        check_index "$TEXMFDIST/busytex-fontindex.txt"
        check_map "$TEXMFDIST/texmf-var/fonts/map/pdftex/updmap/pdftex.map"
        check_db "$TEXMFDIST/texmf-var/luatex-cache/generic/names/luaotfload-names.lua.gz" \
                 "$TEXMFDIST/tex/luatex/luaotfload/luaotfload.conf" "$INDEX_RECORDS"
        ;;
    wasm)
        WASM=${2:-build/wasm/busytex.wasm}
        [ -f "$WASM" ] || fail "missing $WASM"
        grep -aq 'busytex-fontindex.txt' "$WASM" \
            || fail "$WASM carries no font index, font_index.cpp was not linked in"
        echo "check_font_assets: wasm font index linked in"

        for name in basic recommended extra; do
            tree=build/texlive-$name/texmf-dist
            [ -d "$tree" ] || continue
            check_map "$tree/texmf-var/fonts/map/pdftex/updmap/pdftex.map"
            check_db "$tree/texmf-var/luatex-cache/generic/names/luaotfload-names.lua.gz" \
                     "$tree/tex/luatex/luaotfload/luaotfload.conf"
        done
        ;;
    *)
        fail "unknown mode $MODE"
        ;;
esac
