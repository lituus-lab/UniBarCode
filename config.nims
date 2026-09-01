# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode build config.
##
## No `--path` into a sibling checkout: UniVector, UniImage and UniColor are
## declared `requires`, so nimble resolves them wherever the build happens.
## A relative path to a directory beside this one shadows that with whatever
## is in the working tree next door, and does not exist at all in CI.
##
## UniGlyph is intentionally absent: the human-readable interpretation is an
## SVG `<text>` element and the raster backend draws bars and cells only, so
## no font file is ever loaded.
switch("path", "src")
