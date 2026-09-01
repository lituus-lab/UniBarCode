# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — ITF (Interleaved 2-of-5) encoder.
## Digit pairs interleave: odd-position digit in bars, even-position in spaces.
## Each digit: 5 elements, 2 wide + 3 narrow. Requires an even digit count.
## Reference: ISO/IEC 16390:2007.

import ../common/types
import ../common/digits

const
  Symbology = sbItf
  Narrow = 1
  Wide = 2

  Patterns: array[10, array[5, bool]] = [
    [false, false, true, true, false], # 0
    [true, false, false, false, true], # 1
    [false, true, false, false, true], # 2
    [true, true, false, false, false], # 3
    [false, false, true, false, true], # 4
    [true, false, true, false, false], # 5
    [false, true, true, false, false], # 6
    [false, false, false, true, true], # 7
    [true, false, false, true, false], # 8
    [false, true, false, true, false], # 9
  ]

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  if not isAllDigits(payload):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "ITF requires digits only"))
  if payload.len == 0 or payload.len mod 2 != 0:
    return ValidationResult(isValid: false,
      error: newError(ekValidation,
        "ITF requires an even number of digits, got " & $payload.len))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as an Interleaved 2 of 5 symbol. Digits only, and in
  ## pairs: the symbology interleaves two digits per bar group, so an odd
  ## count is refused rather than padded -- padding would change the value
  ## the symbol carries.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  var bars: seq[bool]
  # Start guard: narrow bar, narrow space, narrow bar, narrow space.
  bars.add(true); bars.add(false); bars.add(true); bars.add(false)

  var i = 0
  while i < payload.len:
    let bp = Patterns[digitValue(payload[i])]
    let sp = Patterns[digitValue(payload[i + 1])]
    for k in 0 ..< 5:
      let bw = if bp[k]: Wide else: Narrow
      let sw = if sp[k]: Wide else: Narrow
      for _ in 0 ..< bw: bars.add(true)
      for _ in 0 ..< sw: bars.add(false)
    i += 2

  # Stop guard: wide bar, narrow space, narrow bar.
  bars.add(true); bars.add(true); bars.add(false); bars.add(true)

  var layout = BarcodeLayout()
  for k in 0 ..< payload.len:
    let pair = float(k div 2)
    let off = if k mod 2 == 0: 0.0 else: 7.0
    layout.hri.add(GlyphPlacement(text: $payload[k],
      moduleCenter: 4.0 + pair * 14.0 + off + 3.5))

  encodeOk(Symbology, payload, BarcodeModules(bars: bars), layout)









