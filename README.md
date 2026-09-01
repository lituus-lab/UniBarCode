<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniBarCode

A multi-symbology barcode encoder for the lituus-lab `Uni*` family. Fifteen
symbologies — EAN-13/8, UPC-A, UPC-E, EAN-2/5, Code 39, Code 128, GS1-128, ITF,
QR Code, Micro QR, Data Matrix, PDF417, Aztec — exposed across three surfaces:
**Nim**, a **C ABI**, and a **Python** binding. SVG and PNG (raster) backends
render through the sibling engines UniVector, UniImage and UniColor.

Clean-room from public documented standards (ISO/IEC 15438, 18004, 16022,
24778, 16390, 15417, 16388; GS1 for EAN/UPC/GS1-128; W3C SVG). No pixie code or
references anywhere. Apache-2.0, DCO.

## What's inside

- **Symbology encoders** (`src/UniBarCode/symbology/`) — one module per
  symbology, each turning a payload into modules: the linear families
  (`ean13`, `ean8`, `upca`, `upce`, `ean2`, `ean5`, `code39`, `code128`,
  `gs1128`, `itf`) and the matrix ones (`qrcode`, `microqr`, `datamatrix`,
  `pdf417`, `aztec`).
- **Shared vocabulary** (`src/UniBarCode/common/`) — `types` holds
  `BarcodeSymbology`, `BarcodeModules` and the result types every encoder
  returns; `digits` holds the check-digit arithmetic the GS1 families share.
- **Render backends** (`src/UniBarCode/render/`) — `svg` writes a document,
  `options` carries the geometry and colours both backends read. The raster
  path goes through UniVector and UniImage.
- **Surfaces** — the `ubc_*` C ABI (`src/UniBarCode/c_api.nim`,
  `include/UniBarCode.h`), a Cython binding (`py/`), a CLI
  (`bin/unibarcode_cli.nim`) and a WebAssembly build (`scripts/build_wasm.sh`).

## The Uni* family

Layer 4. It depends on UniVector (path construction, the SVG and raster
backends), UniImage (the surface a symbol is drawn into) and UniColor (the two
colours it is drawn with); UniLinalg and UniMath arrive transitively through
those. Nothing in the family depends on UniBarCode.

UniGlyph is deliberately not a dependency: the human-readable interpretation is
an SVG `<text>` element and the raster backend draws bars and cells only, so no
font is ever shaped.

The family's purpose and philosophy live in
[`lituus-lab/.github`](https://github.com/lituus-lab/.github).

## Provenance & development

The symbology encoders are ported from the author's own openbarcode, under the
same Apache-2.0 licence, and were written clean-room from the published
standards listed above — read, implemented, and checked against the check
values those standards publish. No pixie code or references anywhere.

The git history here is short and linear, and that is not the shape of the
work. The encoders, their invariants and the family's layering are the product
of years of prior hand-written design; what happened at this pace was an
LLM-assisted rewrite pass over that design, not the symbologies being worked
out from a blank page at the speed the commit dates suggest.

## Layout

```text
src/UniBarCode.nim            umbrella facade (encode dispatcher + re-exports)
src/UniBarCode/common/        types, digits (symbology-agnostic domain model)
src/UniBarCode/symbology/     15 encoders
src/UniBarCode/render/        options geometry svg raster
src/UniBarCode/c_api.nim      ubc_* C ABI
include/UniBarCode.h          hand-written C header
bin/unibarcode_cli.nim        CLI (encode -> PNG/SVG)
tests/ tests/c/               Nim + C ABI tests
examples/ examples/c/         Nim + C demos
py/                           Cython binding + pytest + notebook
book/                         nimib book
ADRs/                         0001 DAG, 0002 license, 0003 engine&shell, 0004 conventions
.github/workflows/            ci, release, commitizen
```

## Build

```bash
# Through the gate, not `nimble <task>`: nimble exits 0 even when an `exec`
# inside a task fails, so its exit code says only that nimble ran.
nimble install -y
build/unigate test           # Nim, debug (contracts active)
build/unigate testRelease    # Nim, release (contracts compiled away)
build/unigate testAll        # debug + release + C ABI
build/unigate unibarcode     # CLI: encode a payload to PNG/SVG
build/unigate ctest          # C ABI: static lib + tests/c (links -lz)
build/unigate cexample       # C demo
build/unigate example        # Nim demo
build/unigate pyTest         # Cython + pytest
build/unigate coverage       # gcov + lcov -> coverage/
build/unigate book           # nimib book -> book/index.html
build/unigate docs           # book + API reference -> pages/
build/unigate lint           # nimpretty
build/unigate checkVGraph    # layer DAG + engine dep set
```

## Symbologies

| Ordinal | Name        | `BarcodeSymbology` | Kind |
|---------|-------------|--------------------|------|
| 0       | EAN-13      | `sbEan13`          | 1-D  |
| 1       | EAN-8       | `sbEan8`           | 1-D  |
| 2       | UPC-A       | `sbUpcA`           | 1-D  |
| 3       | Code 39     | `sbCode39`         | 1-D  |
| 4       | Code 128    | `sbCode128`        | 1-D  |
| 5       | ITF         | `sbItf`            | 1-D  |
| 6       | QR Code     | `sbQrCode`         | 2-D  |
| 7       | Data Matrix | `sbDataMatrix`     | 2-D  |
| 8       | PDF417      | `sbPdf417`         | 2-D  |
| 9       | Aztec       | `sbAztec`          | 2-D  |
| 10      | UPC-E       | `sbUpcE`           | 1-D  |
| 11      | EAN-2       | `sbEan2`           | 1-D add-on |
| 12      | EAN-5       | `sbEan5`           | 1-D add-on |
| 13      | Micro QR     | `sbMicroQr`        | 2-D  |
| 14      | GS1-128     | `sbGs1128`         | 1-D  |

## Render

- **SVG** — a standalone W3C SVG document; HRI is `<text>` with a generic
  `monospace` family. No font file is embedded or required, so the output is
  portable.
- **PNG** — an `UniImage.Image[uint8]` (sRGBA) filled via `UniVector.fillPath`;
  bars/cells only (HRI is an SVG-side concern).

UniGlyph is intentionally not a dependency: HRI needs no glyph shaping.

## CI

`test`, `cabi` and `python` on ubuntu/macOS/Windows. `consume-cabi` and
`consume-wheel` rebuild against the published artifacts on a machine without
Nim, so what ships is what was tested. `coverage` and `docs` run on ubuntu.

`dco` blocks PRs missing a `Signed-off-by` trailer; `commitizen` blocks PRs
whose commits or title are not [Conventional Commits](https://www.conventionalcommits.org/)
(`CONTRIBUTING.md`).

The same gates run locally with pre-commit: `pip install pre-commit && pre-commit install`
(`CONTRIBUTING.md`).

`docs` publishes to GitHub Pages only from a public repo.

## AI-assisted contributions

Assistance from AI/LLM tools is welcome on the same terms as any other
contribution.

- **Accountability.** The human contributor is the author and remains fully
  responsible for the change. The DCO sign-off (`Signed-off-by`) is the mechanism:
  by signing you certify the content is yours or properly licensed — this covers
  AI-assisted work, provided you can stand behind it.
- **No third-party contamination.** Ensure AI output introduces no code from a
  third party without a compatible license and attribution. If an LLM reproduced
  protected material, do not submit it.
- **Correctness is yours.** The gates (tests, `nimble lint`, conventional commits,
  pre-commit) catch a lot, but you own the result — review and verify what you
  commit.
- **Atomic commits.** Each commit is one logical change. A PR may stack
  several atomic commits (one per element, say) — one monolithic big-bang
  commit is not.
- **Disclosure.** State in the PR whether AI assistance was used (see the PR
  template). It is not a hard requirement — the DCO remains the gate.

## License

Apache-2.0 (`LICENSE`). DCO sign-off on every commit (`CONTRIBUTING.md`).
