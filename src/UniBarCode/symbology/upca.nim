# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — UPC-A encoder.
## UPC-A is structurally EAN-13 with a leading '0' (same 95-module bar pattern,
## parity LLLLLL). User supplies 11 digits; check digit computed. HRI places the
## first and last digits in the quiet zones.

import ../common/types
import ../common/digits
import ean13 as e13
import contracts

const Symbology = sbUpcA

func computeChecksum*(digits11: string): int {.contractual.} =
  ## Weights `[3,1,3,1,3,1,3,1,3,1,3]` for positions 1..11.
  ## Precondition: `digits11` is exactly 11 ASCII digits.
  ## Postcondition: `result` in 0..9.
  require:
    digits11.len == 11
    isAllDigits(digits11)
  ensure:
    result in 0..9
  body:
    var sum = 0
    for i in 0 ..< 11:
      let d = digitValue(digits11[i])
      let w = if (i and 1) == 0: d * 3 else: d
      sum += w
    result = (10 - (sum mod 10)) mod 10

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  if not isAllDigits(payload):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "UPC-A requires digits only"))
  if payload.len notin {11, 12}:
    return ValidationResult(isValid: false,
      error: newError(ekValidation,
        "UPC-A requires 11 or 12 digits, got " & $payload.len))
  if payload.len == 12:
    let expected = computeChecksum(payload[0 ..< 11])
    if digitValue(payload[11]) != expected:
      return ValidationResult(isValid: false,
        error: newError(ekValidation,
          "UPC-A check digit invalid: expected " & $expected))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a UPC-A symbol. Eleven data digits plus a check digit,
  ## or twelve with the check digit already correct.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  let full12 =
    if payload.len == 12: payload
    else: payload & $computeChecksum(payload)

  # EAN-13 with prepended '0' yields the identical bar pattern (parity LLLLLL).
  let r = e13.encode("0" & full12)
  if not r.isOk:
    return encodeError(Symbology, r.error.kind, r.error.message)

  # Custom HRI: D1 left quiet zone, D2-D6 left group, D7-D11 right group,
  # D12 right quiet zone.
  var layout = BarcodeLayout(guardModules: r.layout.guardModules)
  layout.hri.add(GlyphPlacement(text: $full12[0], moduleCenter: -5.0))
  for i in 1 ..< 6:
    layout.hri.add(GlyphPlacement(text: $full12[i],
      moduleCenter: 3.0 + float(i - 1) * 7.0 + 3.5))
  for i in 6 ..< 11:
    layout.hri.add(GlyphPlacement(text: $full12[i],
      moduleCenter: 50.0 + float(i - 6) * 7.0 + 3.5))
  layout.hri.add(GlyphPlacement(text: $full12[11], moduleCenter: 100.0))

  encodeOk(Symbology, full12, r.modules, layout)









