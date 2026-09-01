# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — Code 39 encoder.
## Each character: 5 bars + 4 spaces = 9 elements, 3 wide + 6 narrow.
## Wide = 2 modules, narrow = 1 module. Inter-character gap = 1 narrow space.
## Supported: 0-9, A-Z, space, - . $ / + %. '*' is reserved for start/stop.

import std/strutils
import ../common/types

const
  Symbology = sbCode39
  Charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%*"

  ## 9 elements per symbol: B1 S1 B2 S2 B3 S3 B4 S4 B5. true = wide.
  ## Each character has exactly 3 wide elements (ISO/IEC 16388:2007).
  Patterns: array[44, array[9, bool]] = [
    [false, false, false, true, true, false, true, false, false], # 0
    [true, false, false, true, false, false, false, false, true], # 1
    [false, false, true, true, false, false, false, false, true], # 2
    [true, false, true, true, false, false, false, false, false], # 3
    [false, false, false, true, true, false, false, false, true], # 4
    [true, false, false, true, true, false, false, false, false], # 5
    [false, false, true, true, true, false, false, false, false], # 6
    [false, false, false, true, false, false, true, false, true], # 7
    [true, false, false, true, false, false, true, false, false], # 8
    [false, false, true, true, false, false, true, false, false], # 9
    [true, false, false, false, false, true, false, false, true], # A
    [false, false, true, false, false, true, false, false, true], # B
    [true, false, true, false, false, true, false, false, false], # C
    [false, false, false, false, true, true, false, false, true], # D
    [true, false, false, false, true, true, false, false, false], # E
    [false, false, true, false, true, true, false, false, false], # F
    [false, false, false, false, false, true, true, false, true], # G
    [true, false, false, false, false, true, true, false, false], # H
    [false, false, true, false, false, true, true, false, false], # I
    [false, false, false, false, true, true, true, false, false], # J
    [true, false, false, false, false, false, false, true, true], # K
    [false, false, true, false, false, false, false, true, true], # L
    [true, false, true, false, false, false, false, true, false], # M
    [false, false, false, false, true, false, false, true, true], # N
    [true, false, false, false, true, false, false, true, false], # O
    [false, false, true, false, true, false, false, true, false], # P
    [false, false, false, false, false, false, true, true, true], # Q
    [true, false, false, false, false, false, true, true, false], # R
    [false, false, true, false, false, false, true, true, false], # S
    [false, false, false, false, true, false, true, true, false], # T
    [true, true, false, false, false, false, false, false, true], # U
    [false, true, true, false, false, false, false, false, true], # V
    [true, true, true, false, false, false, false, false, false], # W
    [false, true, false, false, true, false, false, false, true], # X
    [true, true, false, false, true, false, false, false, false], # Y
    [false, true, true, false, true, false, false, false, false], # Z
    [false, true, false, false, false, false, true, false, true], # -
    [true, true, false, false, false, false, true, false, false], # .
    [false, true, true, false, false, false, true, false, false], # space
    [false, true, false, true, false, true, false, false, false], # $
    [false, true, false, true, false, false, false, true, false], # /
    [false, true, false, false, false, true, false, true, false], # +
    [false, false, false, true, false, true, false, true, false], # %
    [false, true, false, false, true, false, true, false, false], # * (start/stop)
  ]

func charIndex(c: char): int =
  for i, ch in Charset:
    if ch == c: return i
  -1

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  if payload.len == 0:
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "Code 39 payload must not be empty"))
  for c in payload.toUpperAscii():
    if c == '*':
      return ValidationResult(isValid: false,
        error: newError(ekValidation, "Code 39: '*' is reserved for start/stop"))
    if charIndex(c) < 0:
      return ValidationResult(isValid: false,
        error: newError(ekValidation, "Code 39 invalid character: '" & $c & "'"))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

proc addSymbol(bars: var seq[bool]; idx: int) =
  for i, isWide in Patterns[idx]:
    let mods = if isWide: 2 else: 1
    let isBar = (i mod 2 == 0)
    for _ in 0 ..< mods: bars.add(isBar)

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a Code 39 symbol. Only the 43-character Code 39
  ## alphabet encodes: digits, upper case, and `-. $/+%` plus space.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  let upper = payload.toUpperAscii()
  var bars: seq[bool]

  addSymbol(bars, charIndex('*')) # start
  bars.add(false) # inter-character gap

  for c in upper:
    addSymbol(bars, charIndex(c))
    bars.add(false)

  addSymbol(bars, charIndex('*')) # stop

  # Each symbol is 12 modules (3 wide x2 + 6 narrow x1) + 1 gap = 13 modules.
  # Start symbol + gap = 13 modules; data chars follow at 13-module stride.
  var layout = BarcodeLayout()
  let stride = 13.0
  let startMods = 13.0
  for i, c in upper:
    layout.hri.add(GlyphPlacement(text: $c,
      moduleCenter: startMods + float(i) * stride + stride / 2.0))

  encodeOk(Symbology, "*" & upper & "*", BarcodeModules(bars: bars), layout)









