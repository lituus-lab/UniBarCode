# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — UPC-E encoder.
##
## Reference: ISO/IEC 15420:2009 + GS1 General Specifications §5.2.2.4.
##
## UPC-E is the zero-suppressed form of UPC-A for small packages: it encodes
## a GTIN-12 whose number system is 0 as six explicitly encoded digits (X1..X6)
## in 51 modules. The check digit is not printed; it is carried implicitly by
## the A/B (odd/even) parity pattern of the six digits.
##
## Structure: start guard (101) | 6 digits x7 (A/B sets) | special guard
## (010101) = 3 + 42 + 6 = 51 modules.
##
## Expansion (UPC-E -> 11 GTIN data digits, by the last encoded digit X6):
##   X6 in {0,1,2}: 0 X1 X2 X6 0 0 0 0    X3 X4 X5
##   X6 == 3:        0 X1 X2 X3 0 0 0 0 0  X4 X5
##   X6 == 4:        0 X1 X2 X3 X4 0 0 0 0 0    X5
##   X6 in {5..9}:   0 X1 X2 X3 X4 X5 0 0 0 0    X6
## The GS1 modulo-10 check digit (weights `[3,1,3,1,...]` on the 11 data digits)
## is then computed and selects the A/B parity pattern.

import ../common/types
import ../common/digits
import ../common/eanpatterns
import contracts

const
  ModuleCount* = 51
  Symbology = sbUpcE

  ## A/B parity pattern for the six digits, indexed by the check digit.
  ## true = set A (L/odd), false = set B (G/even). Source: ISO/IEC 15420.
  ParityByCheck: array[10, array[6, bool]] = [
    [false, false, false, true, true, true], # 0: BBBAAA
    [false, false, true, false, true, true], # 1: BBABAA
    [false, false, true, true, false, true], # 2: BBAABA
    [false, false, true, true, true, false], # 3: BBAAAB
    [false, true, false, false, true, true], # 4: BABBAA
    [false, true, true, false, false, true], # 5: BAABBA
    [false, true, true, true, false, false], # 6: BAAABB
    [false, true, false, true, false, true], # 7: BABABA
    [false, true, false, true, true, false], # 8: BABAAB
    [false, true, true, false, true, false], # 9: BAABAB
  ]

  ## UPC-E special stop guard: 010101 (6 modules).
  SpecialGuard = [false, true, false, true, false, true]

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  ## Accept exactly 6 ASCII digits (number system 0 implied).
  if not isAllDigits(payload):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "UPC-E payload must contain digits only"))
  if payload.len != 6:
    return ValidationResult(isValid: false,
      error: newError(ekValidation,
        "UPC-E payload must be 6 digits, got " & $payload.len))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc expandToGtin11(payload: string): string {.contractual.} =
  ## Expand the 6-digit UPC-E payload to the 11 GTIN-12 data digits (NS 0 +
  ## 10 data). Precondition: `payload` is 6 ASCII digits.
  require:
    payload.len == 6
    isAllDigits(payload)
  body:
    let x = payload
    case x[5]
    of '0', '1', '2':
      result = "0" & x[0 ..< 2] & x[5] & "0000" & x[2 ..< 5]
    of '3':
      result = "0" & x[0 ..< 3] & "00000" & x[3 ..< 5]
    of '4':
      result = "0" & x[0 ..< 4] & "00000" & x[4 ..< 5]
    else: # 5..9
      result = "0" & x[0 ..< 5] & "0000" & x[5]

func computeCheck*(gtin11: string): int {.contractual.} =
  ## GS1 modulo-10 check digit for the 11 GTIN data digits.
  ## Precondition: `gtin11` is 11 ASCII digits. Postcondition: `result` in 0..9.
  require:
    gtin11.len == 11
    isAllDigits(gtin11)
  ensure:
    result in 0..9
  body:
    var sum = 0
    for i in 0 ..< 11:
      let d = digitValue(gtin11[i])
      sum += (if (i and 1) == 0: d * 3 else: d)
    result = (10 - (sum mod 10)) mod 10

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a UPC-E symbol. The zero-suppressed form of UPC-A: six
  ## data digits plus a check digit.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  let data11 = expandToGtin11(payload)
  let check = computeCheck(data11)
  let parity = ParityByCheck[check]

  var bars = newSeqOfCap[bool](ModuleCount)
  for b in StartGuard: bars.add(b)
  for i in 0 ..< 6:
    let d = digitValue(payload[i])
    let code = if parity[i]: LCodes[d] else: GCodes[d]
    for b in code: bars.add(b)
  for b in SpecialGuard: bars.add(b)

  assert bars.len == ModuleCount,
    "UPC-E produced " & $bars.len & " modules, expected " & $ModuleCount

  # Guards: start (0..2) and the special stop (45..50).
  var layout = BarcodeLayout()
  for i in 0 .. 2: layout.guardModules.add(i)
  for i in 45 .. 50: layout.guardModules.add(i)

  # HRI: number system 0 in the left quiet zone, the six digits under the bars,
  # and the implicit check digit in the right quiet zone.
  layout.hri.add(GlyphPlacement(text: "0", moduleCenter: -5.0))
  for i in 0 ..< 6:
    layout.hri.add(GlyphPlacement(text: $payload[i],
      moduleCenter: 3.0 + float(i) * 7.0 + 3.5))
  layout.hri.add(GlyphPlacement(text: $check, moduleCenter: 56.0))

  encodeOk(Symbology, payload, BarcodeModules(bars: bars), layout)









