# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — EAN-2 add-on encoder.
##
## Reference: ISO/IEC 15420:2009 + GS1 General Specifications (Two-Digit Add-On).
##
## The EAN-2 add-on encodes 2 digits in 20 modules to the right of a primary
## EAN/UPC symbol. Structure: add-on guard (1011) | digit 1 x7 (L/G) |
## delineator (01) | digit 2 x7 (L/G) = 4 + 7 + 2 + 7 = 20 modules. No right
## guard. The L/G parity pattern is selected by (10*d1 + d2) mod 4; the
## checksum is not printed.

import ../common/types
import ../common/digits
import ../common/eanpatterns

const
  ModuleCount* = 20
  Symbology = sbEan2

  ## L/G parity for the two digits, indexed by (10*d1 + d2) mod 4.
  ## true = L (odd), false = G (even). Source: ISO/IEC 15420.
  ParityByCheck: array[4, array[2, bool]] = [
    [true, true], # 0: LL
    [true, false], # 1: LG
    [false, true], # 2: GL
    [false, false], # 3: GG
  ]

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  ## Accept exactly 2 ASCII digits.
  if not isAllDigits(payload):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "EAN-2 payload must contain digits only"))
  if payload.len != 2:
    return ValidationResult(isValid: false,
      error: newError(ekValidation,
        "EAN-2 payload must be 2 digits, got " & $payload.len))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as an EAN-2 add-on. Exactly two digits: the supplement
  ## carried beside an EAN or UPC symbol.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  let check = (digitValue(payload[0]) * 10 + digitValue(payload[1])) mod 4
  let parity = ParityByCheck[check]

  var bars = newSeqOfCap[bool](ModuleCount)
  for b in AddonGuard: bars.add(b)
  for i in 0 ..< 2:
    let d = digitValue(payload[i])
    let code = if parity[i]: LCodes[d] else: GCodes[d]
    for b in code: bars.add(b)
    if i == 0:
      for b in AddonDelineator: bars.add(b)

  assert bars.len == ModuleCount,
    "EAN-2 produced " & $bars.len & " modules, expected " & $ModuleCount

  var layout = BarcodeLayout()
  for i in 0 ..< 2:
    layout.hri.add(GlyphPlacement(text: $payload[i],
      moduleCenter: 4.0 + float(i) * 9.0 + 3.5))

  encodeOk(Symbology, payload, BarcodeModules(bars: bars), layout)









