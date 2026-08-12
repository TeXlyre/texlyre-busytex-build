#!/bin/bash
# Wrapper placed ahead of emcc on PATH while perl's Configure runs.
# emcc <= 1.39 emitted extensionless output as JS with a node shebang and the
# executable bit; 3.x does not, and Configure executes its test programs.
# SINGLE_FILE avoids emscripten's fetch-based wasm loader, which breaks on
# node >= 18 where fetch is global.
export NODE_PATH=${NODE_PATH:-/usr/share/nodejs}
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
args=("$@")
case "$out" in
    *.o|*.a|*.bc|"") ;;
    *) args+=("-sSINGLE_FILE=1") ;;
esac
"$EMCC_REAL" "${args[@]}"; rc=$?
if [ $rc -eq 0 ] && [ -n "$out" ] && [ -f "$out" ]; then
    case "$out" in
        *.o|*.a|*.bc|*.wasm) ;;
        *)
            if ! head -c 2 "$out" | grep -q '^#!' && file "$out" | grep -qiE 'text|javascript'; then
                printf '#!/usr/bin/env node\n' | cat - "$out" > "$out.tmp" && mv "$out.tmp" "$out"
                chmod +x "$out"
            fi
            ;;
    esac
fi
exit $rc
