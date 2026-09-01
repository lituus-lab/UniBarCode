# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — EAN-5 add-on encoder.
##
## Reference: ISO/IEC 15420:2009 + GS1 General Specifications (Five-Digit Add-On).
##
## The EAN-5 add-on encodes 5 digits in 47 modules to the right of a primary
## EAN/UPC symbol (e.g. a book price supplement on an EAN-13). Structure:
## add-on guard (1011) | 5 digits x7 (L/G) separated by delineators (01) =
## 4 + 5*7 + 4*2 = 47 modules. No right guard. The checksum weights
## `[3,9,3,9,3]` (sum mod 10) select the L/G parity pattern; the checksum is
## not printed.

import ../common/types
import ../common/digits
import ../common/eanpatterns
import contracts

const
  ModuleCount* = 47
  Symbology = sbEan5

  ## Checksum weights: digit i is multiplied by 3 then 9, alternating,
  ## starting with 3. Source: ISO/IEC 15420 + GS1.
  CheckWeights: array[5, int] = [3, 9, 3, 9, 3]

  ## L/G parity for the five digits, indexed by the checksum.
  ## true = L (odd), false = G (even). Source: ISO/IEC 15420 + GS1.
  ParityByCheck: array[10, array[5, bool]] = [
    [false, false, true, true, true], # 0: GGLLL
    [false, true, false, true, true], # 1: GLGLL
    [false, true, true, false, true], # 2: GLLGL
    [false, true, true, true, false], # 3: GLLLG
    [true, false, false, true, true], # 4: LGGLL
    [true, true, false, false, true], # 5: LLGGL
    [true, true, true, false, false], # 6: LLLGG
    [true, false, true, false, true], # 7: LGLGL
    [true, false, true, true, false], # 8: LGLLG
    [true, true, false, true, false], # 9: LLGLG
  ]

func computeCheck*(digits5: string): int {.contractual.} =
  ## EAN-5 checksum: each digit weighted `[3,9,3,9,3]`, summed, mod 10.
  ## Precondition: `digits5` is exactly 5 ASCII digits.
  ## Postcondition: `result` in 0..9.
  require:
    digits5.len == 5
    isAllDigits(digits5)
  ensure:
    result in 0..9
  body:
    var sum = 0
    for i in 0 ..< 5:
      sum += digitValue(digits5[i]) * CheckWeights[i]
    result = sum mod 10

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  ## Accept exactly 5 ASCII digits. There is no printed check digit to verify;
  ## the checksum only selects parity, so it is not validated against input.
  if not isAllDigits(payload):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "EAN-5 payload must contain digits only"))
  if payload.len != 5:
    return ValidationResult(isValid: false,
      error: newError(ekValidation,
        "EAN-5 payload must be 5 digits, got " & $payload.len))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as an EAN-5 add-on. Exactly five digits, the supplement
  ## that carries a price.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  let parity = ParityByCheck[computeCheck(payload)]

  var bars = newSeqOfCap[bool](ModuleCount)
  for b in AddonGuard: bars.add(b)
  for i in 0 ..< 5:
    let d = digitValue(payload[i])
    let code = if parity[i]: LCodes[d] else: GCodes[d]
    for b in code: bars.add(b)
    if i < 4:
      for b in AddonDelineator: bars.add(b)

  assert bars.len == ModuleCount,
    "EAN-5 produced " & $bars.len & " modules, expected " & $ModuleCount

  var layout = BarcodeLayout()
  for i in 0 ..< 5:
    layout.hri.add(GlyphPlacement(text: $payload[i],
      moduleCenter: 4.0 + float(i) * 9.0 + 3.5))

  encodeOk(Symbology, payload, BarcodeModules(bars: bars), layout)









