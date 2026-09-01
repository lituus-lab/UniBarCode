<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0001: Sibling package dependencies

- Status: Accepted
- Date: 2026-07-15
- Scope: `requires` in `UniBarCode.nimble`, checked by `nimble checkVGraph`

## Decision

`vgraph.cfg`'s `[engines]` section is the exhaustive list of similarly-prefixed
packages this repo may name in a `requires` line; any name absent from it is a
violation caught by `nimble checkVGraph`. The direct dependencies are
UniVector (path construction and the SVG and raster backends), UniImage (the
raster surface a symbol is written into) and UniColor (the two colours a symbol
is drawn with). UniLinalg and UniMath arrive transitively through those and are
listed so that naming one directly stays a reviewed decision rather than an
error. Adding another entry is a deliberate, reviewed exception, not a default.

They are `requires` and not a `--path` into a directory beside this checkout.
A relative path resolves only where the sibling happens to sit, shadows the
resolved dependency with whatever is uncommitted next door, and does not exist
at all where one repository is checked out on its own.

UniGlyph is deliberately not a dependency: the human-readable interpretation is
an SVG `<text>` element, and the raster backend draws bars and cells only, so no
font is ever shaped.

Non-domain infrastructure (`nim`, `NimContracts`) is unaffected and unchecked by
this rule. Inside this repo, `common/` never imports `symbology/`, and neither
imports `render/` (enforced by the same tool, via `vgraph.cfg [layers]`).
