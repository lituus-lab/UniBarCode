# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — GS1-128 encoder.
##
## Reference: ISO/IEC 15417:2007 (Code 128) + GS1 General Specifications.
##
## GS1-128 is Code 128 with an FNC1 in the first position (the GS1-128 system
## indicator) and Application Identifier (AI) element strings. The payload is
## the human-readable "(AI)DATA(AI)DATA..." form. Variable-length AIs are
## separated by an FNC1 codeword (102) unless they are the final element;
## predefined-length AIs (looked up by their first two digits) need no
## separator. Numeric runs are compacted with Code Set C (digit pairs); the
## rest uses Code Set B (printable ASCII 32..126). A modulo-103 check digit
## closes the symbol before the stop pattern.

import ../common/types
import ../common/code128widths
import contracts

const Symbology = sbGs1128

# ── Predefined-length AI table ───────────────────────────────────────────────
# Indexed by the AI's first two digits → total element-string length (AI digits
# + data digits). -1 = variable-length (needs an FNC1 separator when another
# AI follows). Source: GS1 General Specifications (predefined-length lookup).

const PredefinedLen: array[100, int] = block:
  var t: array[100, int]
  for i in 0 .. 99:
    t[i] = -1
  t[0] = 20 # 00  SSCC (2 + 18)
  t[1] = 16 # 01  GTIN (2 + 14)
  t[2] = 16 # 02  Content (2 + 14)
  t[11] = 8; t[12] = 8; t[13] = 8
  t[15] = 8; t[16] = 8; t[17] = 8 # dates (2 + 6)
  t[20] = 4 # variant (2 + 2)
  t[31] = 10; t[32] = 10; t[33] = 10
  t[34] = 10; t[35] = 10; t[36] = 10 # measures (4 + 6)
  t[41] = 16 # GLN (3 + 13)
  t

proc predefinedTotal(ai: string): int {.inline.} =
  ## Total element-string length for a predefined AI, or -1 if variable.
  if ai.len >= 2:
    PredefinedLen[(ord(ai[0]) - 48) * 10 + (ord(ai[1]) - 48)]
  else:
    -1

# ── Parsing ──────────────────────────────────────────────────────────────────

proc parseAis(payload: string; pairs: var seq[(string, string)]): bool =
  ## Split "(AI)DATA(AI)DATA..." into (ai, data) pairs. Returns false on a
  ## malformed bracket/paren structure, an AI that runs to end-of-input before
  ## its closing ')', or empty element data (e.g. "(10)").
  var i = 0
  while i < payload.len:
    if payload[i] != '(':
      return false
    inc i
    let aiStart = i
    while i < payload.len and payload[i] in '0'..'9':
      inc i
    if i == aiStart or i >= payload.len or payload[i] != ')':
      return false # no digits, end-of-input before ')', or a non-') closer
    let ai = payload[aiStart ..< i]
    inc i # skip ')'
    let dataStart = i
    while i < payload.len and payload[i] != '(':
      inc i
    let data = payload[dataStart ..< i]
    if data.len == 0:
      return false # empty element data
    pairs.add((ai, data))
  pairs.len > 0

func validate*(payload: string): ValidationResult =
  ## Whether `payload` is acceptable to this symbology, and why not if it is
  ## not. `encode` performs the same check, so calling this first is only
  ## useful to report the reason without building a symbol.
  ## Syntax + predefined-length validation of the "(AI)DATA..." form: balanced
  ## parens, >=2-digit AIs, printable data, exact data length for predefined
  ## AIs, and numeric data for predefined AIs (which are all GS1 N-format). This
  ## is not full GS1 semantic validation: it does not verify GTIN/SSCC/GLN check
  ## digits, nor that a variable-length AI is an assigned GS1 AI (that needs the
  ## full AI registry). The encoder accepts what validates here.
  if payload.len == 0:
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "GS1-128 payload must not be empty"))
  var pairs: seq[(string, string)]
  if not parseAis(payload, pairs):
    return ValidationResult(isValid: false,
      error: newError(ekValidation, "GS1-128 payload must be (AI)DATA pairs"))
  for (ai, data) in pairs:
    if ai.len < 2:
      return ValidationResult(isValid: false,
        error: newError(ekValidation, "GS1-128 AI too short: (" & ai & ")"))
    for c in data:
      if ord(c) < 32 or ord(c) > 126:
        return ValidationResult(isValid: false,
          error: newError(ekValidation,
            "GS1-128 data char out of printable range: " & $c))
    let total = predefinedTotal(ai)
    if total >= 0:
      if data.len != total - ai.len:
        return ValidationResult(isValid: false,
          error: newError(ekValidation,
            "GS1-128 AI (" & ai & ") needs " & $(total - ai.len) &
            " data chars, got " & $data.len))
      for c in data:
        if c notin '0'..'9':
          return ValidationResult(isValid: false,
            error: newError(ekValidation,
              "GS1-128 AI (" & ai & ") data must be numeric"))
  ValidationResult(isValid: true, error: BarcodeError(kind: ekNone))

# ── Token stream ─────────────────────────────────────────────────────────────

type Tok = object
  fnc1: bool
  ch: char

proc buildTokens(pairs: seq[(string, string)]): seq[Tok] =
  ## FNC1-first, then each AI+data, with an FNC1 separator after a
  ## variable-length AI unless it is the final element.
  result.add Tok(fnc1: true)
  for idx, (ai, data) in pairs:
    for c in ai:
      result.add Tok(fnc1: false, ch: c)
    for c in data:
      result.add Tok(fnc1: false, ch: c)
    if predefinedTotal(ai) < 0 and idx != pairs.high:
      result.add Tok(fnc1: true)

# ── Code 128 compaction (Code sets B + C) ──────────────────────────────────────

type Cs = enum csB, csC

proc compact(toks: seq[Tok]; startSet: Cs): seq[int] =
  ## Encode the data tokens (skipping the leading FNC1-first) to Code 128
  ## codeword values. Code C packs digit pairs; Code B packs one printable
  ## char. Switch to C for ≥6 digits mid-string (≥4 at the end); a lone digit
  ## left over in a C run drops back to B. FNC1 tokens emit codeword 102.
  var cws: seq[int]
  var set = startSet
  var i = 1 # skip FNC1-first
  while i < toks.len:
    if toks[i].fnc1:
      cws.add(102)
      inc i
      continue
    var run = 0
    while i + run < toks.len and not toks[i + run].fnc1 and
          toks[i + run].ch in '0'..'9':
      inc run
    let atEnd = (i + run == toks.len)
    if set == csC:
      if run >= 2:
        while run >= 2:
          cws.add((ord(toks[i].ch) - 48) * 10 + (ord(toks[i + 1].ch) - 48))
          i += 2
          run -= 2
        if run == 1:
          cws.add(100) # Code B
          set = csB
          cws.add(ord(toks[i].ch) - 32)
          inc i
      else:
        cws.add(100) # Code B; reprocess i in B
        set = csB
    else: # csB
      if run >= 6 or (run >= 4 and atEnd):
        cws.add(99) # Code C; reprocess i in C
        set = csC
      else:
        cws.add(ord(toks[i].ch) - 32)
        inc i
  cws

proc checkDigit(startCw: int; cws: seq[int]): int {.contractual.} =
  ## ISO/IEC 15417 modulo-103 check digit.
  ## Precondition: `startCw` is a Code 128 start code (103/104/105).
  ## Postcondition: `result` in 0..102.
  require:
    startCw in {103, 104, 105}
  ensure:
    result in 0 .. 102
  body:
    var s = startCw
    for i, cw in cws:
      s += (i + 1) * cw
    result = s mod 103

# ── Rendering ────────────────────────────────────────────────────────────────

proc addCwStr(bars: var seq[bool]; s: string) =
  var dark = true
  for ch in s:
    let m = int(ch) - int('0')
    for _ in 0 ..< m:
      bars.add(dark)
    dark = not dark

proc addWidths(bars: var seq[bool]; w: openArray[int]) =
  var dark = true
  for m in w:
    for _ in 0 ..< m:
      bars.add(dark)
    dark = not dark

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a GS1-128 symbol. Code 128 with a leading FNC1 and GS1
  ## application identifiers; the payload is validated against them.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  let v = validate(payload)
  if not v.isValid:
    return encodeError(Symbology, v.error.kind, v.error.message)

  var pairs: seq[(string, string)]
  discard parseAis(payload, pairs)
  let toks = buildTokens(pairs)

  # Start set: ≥4 leading digits after the FNC1-first → Code C, else Code B.
  var lead = 0
  while 1 + lead < toks.len and not toks[1 + lead].fnc1 and
        toks[1 + lead].ch in '0'..'9':
    inc lead
  let startSet = if lead >= 4: csC else: csB
  let startCw = if startSet == csC: 105 else: 104

  var dataCws = @[102] # FNC1 first (GS1-128 system indicator)
  for cw in compact(toks, startSet):
    dataCws.add(cw)
  let cd = checkDigit(startCw, dataCws)

  var bars: seq[bool]
  addCwStr(bars, RawW[startCw])
  for cw in dataCws:
    addCwStr(bars, RawW[cw])
  addCwStr(bars, RawW[cd])
  addWidths(bars, StopW)

  var layout = BarcodeLayout()
  layout.hri.add(GlyphPlacement(text: payload, moduleCenter: float(bars.len) / 2.0))
  encodeOk(Symbology, payload, BarcodeModules(bars: bars), layout)










