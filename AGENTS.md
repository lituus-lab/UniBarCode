<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# AGENTS.md — UniBarCode

## Build & gates

```bash
# Through the gate, not `nimble <task>`: nimble exits 0 even when an `exec`
# inside a task fails, so its exit code says only that nimble ran.
nimble install -y
build/unigate testAll      # Nim debug + release + C ABI
build/unigate unibarcode   # CLI: encode a payload to PNG/SVG
build/unigate pyTest       # Cython + pytest (needs the built libUniBarCode shared lib)
build/unigate example
build/unigate coverage     # gcov + lcov -> coverage/ (needs lcov; linux/macOS)
build/unigate docs         # nimib book + API reference -> pages/ (needs nimib)
```

`nimble docs` needs a complete Nim distribution: `--project` builds `dochack`,
which Homebrew's `nim` omits (no `tools/`). choosenim and the CI action ship it.

CI: 3-OS Nim matrix + C ABI (linux/macOS) + Python.

## Conventions

- English comments, terse, describe what is done. No "deprecated".
- NimContracts `{.contractual.}` + `require:`/`ensure:`/`body:`, compiled away
  under `-d:release`. C ABI never raises — it clamps out-of-range input.
- A postcondition is cheaper than the body: never re-derives the result by
  calling the function itself.
- C ABI: hand-written `include/UniBarCode.h` kept in sync with
  `src/UniBarCode/c_api.nim`; `tests/c` links the header against the lib.
  Built `--app:staticlib`/`--app:lib --noMain --mm:arc -d:release`.
- A change to `c_api.nim` is verified by `ctest`, `pyTest` and, where there
  is one, `wasmTest`: three linkages, three runtime bootstraps. A green
  `ctest` alone proved nothing the day the shared build lost its
  initializer and every registry answered with the sentinel.
- C symbols `ubc_*` (prefix `ubc_`); lib `libUniBarCode`; header `UniBarCode.h`.
- `book/index.nim` is nimib: its code blocks are compiled and run at docs build,
  so prose that outlives its API breaks the build. `py/notebooks/quickstart.ipynb`
  plays the same role for Python and renders natively on GitHub.
- End covered sources with a blank line. Nim maps a trailing statement one line
  past EOF. `nimble coverage` suppresses exactly two lcov categories, both
  compiler artefacts with no source-level fix: `mismatch`, where lcov 2.x and
  gcov disagree on the end line of Nim's generated destructors, and that EOF + 1
  attribution -- `range` on lcov 2.5, `unmapped` on the 2.0 the runners install,
  which is why the task asks the version first. Every other error still fails.

## Scope

UniBarCode is a layer-4 terminal engine in the lituus-lab Uni* family:
multi-symbology barcode encoding (EAN-13/8, UPC-A, UPC-E, EAN-2/5 add-ons,
Code 39, Code 128, GS1-128, ITF, QR Code, Micro QR, Data Matrix, PDF417,
Aztec) with SVG and PNG (raster) backends rendered through UniVector +
UniImage + UniColor. No font file is loaded — HRI is SVG `<text>`, and the
raster backend draws bars/cells only. Clean-room from public standards
(ISO/IEC, GS1, W3C SVG); no pixie code or references anywhere. Apache-2.0,
DCO. The `ubc_*` C ABI and Python binding mirror the family pattern
(UniGlyph `ugly_`, UniVector `uv_`).
