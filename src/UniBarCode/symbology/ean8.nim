# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — EAN-8 encoder.
## Structure: start(3) + 4x L-code(28) + center(5) + 4x R-code(28) + end(3) = 67 modules.
## Checksum: weight pattern `[3,1,3,1,3,1,3]` on the first 7 digits.

import ../common/types
import ../common/digits
import ../common/eanpatterns
import contracts

const
  ModuleCount* = 67
  Symbology = sbEan8

func computeChecksum*(digits7: string): int {.contractual.} =
  ## Compute the EAN-8 check digit for the first 7 digits.
  ## Precondition: `digits7` is exactly 7 ASCII digits.
  ## Postcondition: `result` in 0..9.
  require:
    digits7.len == 7
    isAllDigits(digits7)
  ensure:
    result in 0..9
  body:
    var sum = 0
    for i in 0 ..< 7:
      let d = digitValue(digits7[i])
      let w = if (i and 1) == 0: d * 3 else: d
      sum += w
    result = (10 - (sum mod 10)) mod 10

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  if not isAllDigits(payload):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "EAN-8 requires digits only"))
  if payload.len notin {7, 8}:
    return ValidationResult(isValid: false,
      error: newError(ekValidation,
        "EAN-8 requires 7 or 8 digits, got " & $payload.len))
  if payload.len == 8:
    let expected = computeChecksum(payload[0 ..< 7])
    if digitValue(payload[7]) != expected:
      return ValidationResult(isValid: false,
        error: newError(ekValidation,
          "EAN-8 check digit invalid: expected " & $expected))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc normalize*(payload: string): string {.contractual.} =
  ## Return the canonical 8-digit form (with check digit).
  ## Precondition: `validate(payload).isValid`.
  require:
    validate(payload).isValid
  body:
    result = if payload.len == 8: payload
             else: payload & $computeChecksum(payload)

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as an EAN-8 symbol. Seven data digits plus a check digit,
  ## or eight with the check digit already correct.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)
  let full = normalize(payload)

  var bars = newSeqOfCap[bool](ModuleCount)
  for b in StartGuard: bars.add(b)
  for i in 0 ..< 4:
    for b in LCodes[digitValue(full[i])]: bars.add(b)
  for b in CenterGuard: bars.add(b)
  for i in 4 ..< 8:
    for b in RCodes[digitValue(full[i])]: bars.add(b)
  for b in EndGuard: bars.add(b)

  assert bars.len == ModuleCount

  var layout = BarcodeLayout()
  for i in 0 .. 2: layout.guardModules.add(i)
  for i in 31 .. 35: layout.guardModules.add(i)
  for i in 64 .. 66: layout.guardModules.add(i)

  for i in 0 ..< 4:
    layout.hri.add(GlyphPlacement(text: $full[i],
      moduleCenter: 3.0 + float(i) * 7.0 + 3.5))
  for i in 0 ..< 4:
    layout.hri.add(GlyphPlacement(text: $full[4 + i],
      moduleCenter: 36.0 + float(i) * 7.0 + 3.5))

  encodeOk(Symbology, full, BarcodeModules(bars: bars), layout)









