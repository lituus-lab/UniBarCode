# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/strutils
import nimib, nimibook
import lituus_theme
import UniBarCode

nbInit(theme = useNimibook)
useLituus()
nb.title = "Clean-room"

nbText: """
## Clean-room

The encoders are original code against public documented standards (ISO/IEC
15438 for PDF417, ISO/IEC 18004 for QR Code and Micro QR, ISO/IEC 16022 for
Data Matrix, ISO/IEC 24778 for Aztec, ISO/IEC 16390 for ITF, ISO/IEC 15417 for
Code 128 and GS1-128, ISO/IEC 16388 for Code 39, GS1 for EAN/UPC, UPC-E and
EAN-2/5 add-ons, W3C SVG for the vector backend). No pixie code or references
appear anywhere — comments, docs, commits, ADRs.
"""

nbCode:
  import std/strutils
  import UniBarCode

  echo "version ", UniBarCodeVersion

nbText: """
"""

nbSave
