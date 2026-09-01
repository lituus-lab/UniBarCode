# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — Code 128B encoder (printable ASCII 32..126).
## Each codeword = 11 modules (3 bars + 3 spaces). Stop = 13 modules.
## Mandatory modulo-103 check digit. Reference: ISO/IEC 15417:2007.

import ../common/types
import ../common/code128widths

const Symbology = sbCode128

proc addWidths(bars: var seq[bool]; w: openArray[int]) =
  var dark = true
  for m in w:
    for _ in 0 ..< m: bars.add(dark)
    dark = not dark

proc addCwStr(bars: var seq[bool]; s: string) =
  var dark = true
  for ch in s:
    let m = int(ch) - int('0')
    for _ in 0 ..< m: bars.add(dark)
    dark = not dark

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a Code 128-B symbol. Every printable ASCII character
  ## encodes. Subset B only: the encoder emits one start code and never
  ## switches, so a run of digits costs one codeword each rather than the two
  ## digits per codeword subset C would pack.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  if payload.len == 0:
    return encodeError(Symbology, ekValidation, "Code 128 payload must not be empty")
  for c in payload:
    if ord(c) < 32 or ord(c) > 126:
      return encodeError(Symbology, ekValidation,
        "Code 128-B: char out of range (ord=" & $ord(c) & ")")

  var bars: seq[bool]
  addWidths(bars, StartBW)

  var check = 104 # Start-B value
  for i, c in payload:
    let v = ord(c) - 32
    addCwStr(bars, RawW[v])
    check += (i + 1) * v

  addCwStr(bars, RawW[check mod 103])
  addWidths(bars, StopW)

  var layout = BarcodeLayout()
  for i, c in payload:
    layout.hri.add(GlyphPlacement(text: $c,
      moduleCenter: 11.0 + float(i) * 11.0 + 5.5))

  encodeOk(Symbology, payload, BarcodeModules(bars: bars), layout)









