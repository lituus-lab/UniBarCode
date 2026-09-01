# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/strformat
import UniBarCode

echo &"UniBarCode {UniBarCodeVersion}"

const cases = [
  (sbEan13, "978020137962", "EAN-13"),
  (sbEan8, "9638507", "EAN-8"),
  (sbUpcA, "03600029145", "UPC-A"),
  (sbCode39, "ABC123", "Code 39"),
  (sbCode128, "ABC123", "Code 128"),
  (sbItf, "1234567890", "ITF"),
  (sbQrCode, "Hello", "QR Code"),
  (sbDataMatrix, "Hello", "Data Matrix"),
  (sbPdf417, "Hello", "PDF417"),
  (sbAztec, "Hello", "Aztec"),
]

for (s, payload, name) in cases:
  let r = encode(s, payload)
  if not r.isOk:
    echo &"{name}: encode failed — {r.error.message}"
    continue
  if r.modules.is2D:
    echo &"{name}: {r.modules.gridWidth}x{r.modules.gridHeight} modules"
  else:
    echo &"{name}: {r.modules.width} modules, payload={r.normalizedPayload}"

# Write one SVG + one PNG to demonstrate the render backends.
let ean = encode(sbEan13, "978020137962")
writeFile("build/demo_ean13.svg", toSvg(ean))
let png = toPng(ean)
writeFile("build/demo_ean13.png", png)
echo "wrote build/demo_ean13.svg and build/demo_ean13.png"
