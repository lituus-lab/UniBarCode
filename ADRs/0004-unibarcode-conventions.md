<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0004: UniBarCode conventions

- Status: Accepted
- Date: 2026-07-27
- Scope: UniBarCode engine — layering, C ABI, render backends, clean-room

## Context

UniBarCode is a layer-4 terminal engine in the lituus-lab `Uni*` family: it
depends on UniVector, UniImage and UniColor (transitively UniLinalg, UniMath)
and nothing depends on it. It ports the openbarcode symbology encoders (the
user's own Apache-2.0 code) to the family and replaces the legacy rendering with
UniVector/UniImage/UniColor.

## Layout

```text
UniBarCode.nimble            package + tasks
config.nims                  --path to src + sibling engines (no requires)
vgraph.cfg                   layers + engine dep set
src/UniBarCode.nim           umbrella facade (encode dispatcher + re-exports)
src/UniBarCode/common/       types, digits (symbology-agnostic domain model)
src/UniBarCode/symbology/    15 encoders (ean13 ean8 upca upce ean2 ean5
                             code39 code128 gs1128 itf qrcode microqr
                             datamatrix pdf417 aztec)
src/UniBarCode/render/       options geometry svg raster
src/UniBarCode/c_api.nim     ubc_* C ABI
include/UniBarCode.h         hand-written C header
bin/unibarcode_cli.nim       CLI (encode -> PNG/SVG)
tests/ tests/c/              Nim + C ABI tests
examples/ examples/c/        Nim + C demos
py/                          Cython binding + pytest + notebook
book/                        nimib book
ADRs/                        0001-0004
.github/workflows/           ci, release, commitizen
```

## Layers (`vgraph.cfg`)

`common < symbology < render < c_api`. A module may import its own layer and any
lower one, never a higher one. `[engines]` is the allowlist of family packages
this repo may name in `requires`; UniVector, UniImage and UniColor are declared
there, UniLinalg and UniMath arrive transitively (ADR-0001).

## Naming

- Nim package/module: `UniBarCode`.
- C library: `libUniBarCode`. C header: `UniBarCode.h`.
- C symbol prefix: `ubc_` (family-fixed). Status enum `UBC_*`.
- Symbology ordinals are frozen and mirror the `UBC_SBC_*` constants in the
  header (EAN-13=0 ... Aztec=9).

## Clean-room

Encoders are original code against public documented standards (ISO/IEC 15438
PDF417, ISO/IEC 18004 QR, ISO/IEC 16022 Data Matrix, ISO/IEC 24778 Aztec, GS1
EAN/UPC, ISO/IEC 16390 ITF, ISO/IEC 15417 Code 128, ISO/IEC 16388 Code 39).
Permissive reference implementations are credited in source comments
(zxing-cpp Apache-2.0, aztec_code_generator MIT) where a table or algorithm was
verified against them.

## Render backends

- **SVG** (`render/svg`): a standalone W3C SVG document. One `<path>` whose
  `d` string is UniVector's serialization of the per-module rectangles; HRI is
  `<text>` with a generic `monospace` family. **No font file is embedded or
  required** — the output is portable and renders with any viewer's default.
- **Raster** (`render/raster`): an `UniImage.Image[uint8]` (sRGBA) filled via
  `UniVector.fillPath`; PNG encoded through UniImage. Bars/cells only (no HRI
  in the raster — HRI is an SVG-side concern).
- `render/geometry` holds the single module-to-pixel mapping both backends
  share.

UniGlyph is intentionally **not** a dependency: HRI needs no glyph shaping.

## C ABI (`ubc_*`)

Mirrors the family pattern (UniGlyph `ugly_`, UniVector `uv_`): opaque handles
(`ubc_barcode` / `ubc_options` / `ubc_color`), `{.push exportc, cdecl, dynlib.}`,
`ubc_init` runs NimMain once, never raises (traps `CatchableError`/`Defect` ->
`UBC_*` codes), built `--app:staticlib`/`--app:lib --noMain --mm:arc
-d:release` (not `-d:danger`). C-owned buffers from `ubc_render_svg` /
`ubc_render_png` are freed with `ubc_buffer_free`. The SVG buffer is
NUL-terminated so C can use it as a string directly.

### What it covers, and what it deliberately does not

The C surface is the whole task a consumer has: encode a payload under a
symbology, ask the result its shape, and render it. Twenty-eight entry points
cover it, and the per-symbology encoders are reached through `ubc_encode` with
an ordinal rather than fifteen entries that would each say the same thing.

Four families of exported Nim procs are deliberately absent, and none of them
is a gap waiting for a consumer to ask:

- **Check-digit arithmetic** (`computeChecksum`, `computeCheck`, `digitValue`,
  `isAllDigits`, `normalize`) — an encoder computes its own. A C caller hands
  over a payload and receives a symbol; exposing the intermediate step would
  invite a caller to compute a check digit that the encoder then recomputes.
- **Result constructors** (`encodeOk`, `encodeError`, `newError`) — these build
  the Nim result type. C sees an opaque handle and an error code instead, which
  is what a language without sum types can act on.
- **Render geometry** (`modulePath`, `pixelSize`, `hriBaselineY`,
  `supplementModuleOffsets`) — the backends' own arithmetic. C asks for SVG or
  PNG bytes, not for a path to draw itself.
- **Diagnostics** (`toBitString`, `toGridBitString`) — for reading a symbol in
  a test failure, not for a caller.

## Conventions

- NimContracts `{.contractual.}` + `require:`/`ensure:`/`body:`, compiled away
  under `-d:release`. A postcondition is cheaper than the body and never
  re-derives the result.
- English comments, terse, describe what is done. No "deprecated".
- Covered sources end with a blank line (Nim maps a trailing statement one
  line past EOF; without it lcov aborts on `range`).

## CI gates

- `nimble testCi` + `testCiRelease` on ubuntu/macOS/Windows.
- `nimble ctest` on ubuntu/macOS/Windows (links `libUniBarCode.a`, `-lz` and
  `-lm`).
- `nimble pyTest` on ubuntu/macOS/Windows.
- `nimble lint`, `checkVGraph`, `coverage`, `docs`.
