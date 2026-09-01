# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — EAN-13 encoder.
##
## Reference: GS1 General Specifications, EAN/UPC symbology.
##
## An EAN-13 symbol is 95 modules wide:
##   start guard (101) | 6 left digits x7 | center guard (01010) |
##   6 right digits x7 | end guard (101)
##   = 3 + 42 + 5 + 42 + 3 = 95
##
## The first digit is not drawn directly; it selects the parity pattern
## (L = odd, G = even) applied to the six left-hand digits. Right-hand digits
## always use the R (even) encoding.

import ../common/types
import ../common/digits
import ../common/eanpatterns
import contracts

const
  ModuleCount* = 95
  Symbology = sbEan13

  ## Parity pattern for the six LEFT digits, indexed by the first digit.
  ## true = L (odd), false = G (even).
  FirstDigitParity: array[10, array[6, bool]] = [
    [true, true, true, true, true, true], # 0: LLLLLL
    [true, true, false, true, false, false], # 1: LLGLGG
    [true, true, false, false, true, false], # 2: LLGGLG
    [true, true, false, false, false, true], # 3: LLGGGL
    [true, false, true, true, false, false], # 4: LGLLGG
    [true, false, false, true, true, false], # 5: LGGLLG
    [true, false, false, false, true, true], # 6: LGGGLL
    [true, false, true, false, true, false], # 7: LGLGLG
    [true, false, true, false, false, true], # 8: LGLGGL
    [true, false, false, true, false, true], # 9: LGGLGL
  ]

func computeChecksum*(digits12: string): int {.contractual.} =
  ## Compute the EAN-13 check digit for the first 12 digits.
  ## Precondition: `digits12` is exactly 12 ASCII digits.
  ## Postcondition: `result` in 0..9.
  require:
    digits12.len == 12
    isAllDigits(digits12)
  ensure:
    result in 0..9
  body:
    var sum = 0
    for i in 0 ..< 12:
      let d = digitValue(digits12[i])
      # Odd positions (1-indexed) weight 1, even positions weight 3.
      sum += (if (i and 1) == 0: d else: d * 3)
    result = (10 - (sum mod 10)) mod 10

func validate*(payload: string): ValidationResult =
  ## Validate raw EAN-13 input. Accepts 12 digits (checksum appended)
  ## or 13 digits (checksum must be correct).
  if not isAllDigits(payload):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "EAN-13 payload must contain digits only"))
  if payload.len notin {12, 13}:
    return ValidationResult(isValid: false,
      error: newError(ekValidation,
        "EAN-13 payload must be 12 or 13 digits, got " & $payload.len))
  if payload.len == 13:
    let expected = computeChecksum(payload[0 ..< 12])
    if digitValue(payload[12]) != expected:
      return ValidationResult(isValid: false,
        error: newError(ekValidation,
          "EAN-13 check digit invalid: expected " & $expected &
          ", got " & $payload[12]))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc normalize*(payload: string): string {.contractual.} =
  ## Return the canonical 13-digit form (with check digit).
  ## Precondition: `validate(payload).isValid`.
  require:
    validate(payload).isValid
  body:
    result = if payload.len == 13: payload
             else: payload & $computeChecksum(payload)

proc encode*(payload: string): EncodeResult =
  ## Encode an EAN-13 payload into 95 modules.
  ## Returns an error result (never raises) on invalid input.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  let full = normalize(payload)
  let first = digitValue(full[0])
  let parity = FirstDigitParity[first]

  var bars = newSeqOfCap[bool](ModuleCount)
  for b in StartGuard: bars.add(b)
  # Left group: digits 1..6 (0-indexed 1..6), parity-selected.
  for i in 0 ..< 6:
    let d = digitValue(full[1 + i])
    let code = if parity[i]: LCodes[d] else: GCodes[d]
    for b in code: bars.add(b)
  for b in CenterGuard: bars.add(b)
  # Right group: digits 7..12 (0-indexed 7..12), always R-code.
  for i in 0 ..< 6:
    let d = digitValue(full[7 + i])
    for b in RCodes[d]: bars.add(b)
  for b in EndGuard: bars.add(b)

  # Postcondition: exact module count.
  assert bars.len == ModuleCount,
    "EAN-13 produced " & $bars.len & " modules, expected " & $ModuleCount

  # Presentation metadata (guards + human-readable digit placement).
  # Guard modules: start (0..2), center (45..49), end (92..94).
  var layout = BarcodeLayout()
  for i in 0 .. 2: layout.guardModules.add(i)
  for i in 45 .. 49: layout.guardModules.add(i)
  for i in 92 .. 94: layout.guardModules.add(i)

  # First digit sits in the left quiet zone, before the start guard.
  layout.hri.add(GlyphPlacement(text: $full[0], moduleCenter: -5.0))
  # Left group: 6 digits over modules 3..44, each 7 modules wide.
  for i in 0 ..< 6:
    layout.hri.add(GlyphPlacement(text: $full[1 + i],
      moduleCenter: 3.0 + float(i) * 7.0 + 3.5))
  # Right group: 6 digits over modules 50..91.
  for i in 0 ..< 6:
    layout.hri.add(GlyphPlacement(text: $full[7 + i],
      moduleCenter: 50.0 + float(i) * 7.0 + 3.5))

  encodeOk(Symbology, full, BarcodeModules(bars: bars), layout)









