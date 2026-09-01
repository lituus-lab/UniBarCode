# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/strutils
import nimib, nimibook
import lituus_theme
import UniBarCode

nbInit(theme = useNimibook)
useLituus()
nb.title = "Encoding"

nbText: """
## Encode

`encode(symbology, payload)` returns an `EncodeResult`. Validation errors are
values, not exceptions: `isOk` discriminates the ok/error paths.
"""

nbCode:
  let r = encode(sbEan13, "978020137962")
  if r.isOk:
    echo "modules = ", r.modules.width
    echo "normalized = ", r.normalizedPayload
  else:
    echo "refused: ", r.error.message

nbText: """
2-D symbologies fill `modules.grid`; `is2D` tells them apart.
"""

nbCode:
  let qr = encode(sbQrCode, "Hello")
  echo "is2D = ", qr.modules.is2D
  echo "grid = ", qr.modules.gridWidth, "x", qr.modules.gridHeight

nbText: """
The family also covers UPC-E, EAN-2/EAN-5 add-ons (attached to a primary
EAN/UPC via `encodeComposite`), Micro QR (M1-M4), and GS1-128 - Code 128 with
an FNC1 first-position indicator and parenthesized `(AI)DATA` element strings.
Variable-length AIs are separated by an FNC1 codeword unless they are last.
"""

nbCode:
  let upce = encode(sbUpcE, "012345")
  echo "UPC-E width = ", upce.modules.width
  let comp = encodeComposite(sbEan13, "978020137962", sbEan5, "52495")
  echo "composite supplement = ", comp.layout.supplements.len
  let mqr = encode(sbMicroQr, "12345")
  echo "Micro QR = ", mqr.modules.gridWidth, "x", mqr.modules.gridHeight
  let gs1 = encode(sbGs1128, "(01)04212345678904(10)BATCH123")
  echo "GS1-128 width = ", gs1.modules.width

nbText: """
"""

nbSave
