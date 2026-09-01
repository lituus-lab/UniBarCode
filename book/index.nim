# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/strutils
import nimib, nimibook
import lituus_theme
import UniBarCode

nbInit(theme = useNimibook)
useLituus()
nb.title = "UniBarCode"

nbText: """
# UniBarCode

A multi-symbology barcode encoder for the lituus-lab `Uni*` family. Fifteen
symbologies — EAN-13/8, UPC-A, UPC-E, EAN-2/5, Code 39, Code 128, GS1-128, ITF,
QR Code, Micro QR, Data Matrix, PDF417, Aztec — exposed across three surfaces:
**Nim**, a **C ABI**, and a **Python** binding. SVG and PNG (raster) backends
render through the sibling engines UniVector, UniImage and UniColor.

This page is a nimib book: every Nim block below is compiled and run when the
book is built, and the output shown is what the code actually produced. A
change that breaks the API breaks the docs build, so the two cannot drift apart.
"""

nbSave
