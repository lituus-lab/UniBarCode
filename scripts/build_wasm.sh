#!/usr/bin/env bash
# Build dist/unibarcode.{js,wasm} — the UniBarCode C ABI compiled to
# WebAssembly via Emscripten. Consumed by the web app and the Figma plugin.
#
# Requirements:
#   - nim >= 2.0
#   - emsdk activated in the current shell (source emsdk/emsdk_env.sh)
#
# Output: dist/unibarcode.{js,wasm}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAPI="$ROOT/src/UniBarCode/c_api.nim"
CACHE="$ROOT/build/nimcache_wasm"
OUT="$ROOT/dist"
# `|| true`: under `set -euo pipefail` a grep that matches nothing aborts the
# script here, so the diagnostic below never runs and the failure is silent.
NIM_LIB="$(nim dump 2>&1 | grep -E '/lib/pure$' | head -1 | sed 's,/pure$,,' || true)"
if [ -z "$NIM_LIB" ]; then
  echo "build_wasm: could not determine the Nim lib path from 'nim dump'." \
    "Is nim >= 2.0 on PATH?" >&2
  exit 1
fi

# Emptied, not just created: the link step globs every .c in here, so a file
# left by an earlier run under a different dependency resolution is linked
# alongside its replacement and the same symbol is defined twice.
rm -rf "$CACHE"
mkdir -p "$CACHE" "$OUT"

# ── Step 1: Nim → portable C (no platform linking) ───────────────────────────
# config.nims supplies the sibling-engine --path entries (UniVector/UniImage/
# UniColor/UniLinalg/UniMath). -d:release keeps the ABI backstops (not -d:danger,
# so bounds checks stay as defense-in-depth for untrusted payloads/colors).
echo "→ nim: generating C…"
nim c \
  -d:release \
  -d:ubcNoRaster \
  --noMain \
  --noLinking \
  --cpu:i386 \
  --os:linux \
  --cc:gcc \
  --gcc.exe:true \
  --gcc.linkerexe:true \
  --nimcache:"$CACHE" \
  "$CAPI"

# ── Step 2: C → WASM via Emscripten ─────────────────────────────────────────
echo "→ emcc: linking WASM…"

C_FILES=()
while IFS= read -r f; do C_FILES+=("$f"); done < <(find "$CACHE" -name "*.c" | sort)

emcc "${C_FILES[@]}" \
  -I"$CACHE" \
  -I"$NIM_LIB" \
  -o "$OUT/unibarcode.js" \
  -s MODULARIZE=1 \
  -s EXPORT_NAME=UniBarCodeWasm \
  -s EXPORTED_FUNCTIONS='["_ubc_init","_ubc_abi_version","_ubc_version","_ubc_strerror","_ubc_encode","_ubc_encode_composite","_ubc_barcode_is_ok","_ubc_barcode_symbology","_ubc_barcode_width","_ubc_barcode_height","_ubc_barcode_is_2d","_ubc_barcode_error","_ubc_barcode_free","_ubc_options_new","_ubc_options_set_module_size","_ubc_options_set_bar_height","_ubc_options_set_guard_height","_ubc_options_set_quiet_zone","_ubc_options_set_show_hri","_ubc_options_set_foreground","_ubc_options_set_background","_ubc_options_free","_ubc_color_parse","_ubc_color_rgba","_ubc_color_free","_ubc_render_svg","_ubc_buffer_free","_malloc","_free"]' \
  -s EXPORTED_RUNTIME_METHODS='["UTF8ToString","stringToUTF8","getValue","setValue","HEAPU8","HEAP8","HEAPU32","ccall","cwrap"]' \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s INITIAL_MEMORY=33554432 \
  -O2 \
  --no-entry

echo "✓ $OUT/unibarcode.js"
echo "✓ $OUT/unibarcode.wasm"
