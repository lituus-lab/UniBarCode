# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — Aztec Code encoder.
## ISO/IEC 24778. Compact symbols (L1-L4) and full symbols (L1-L32).
## Full mode: ring_radius=7, sideSize=11, reference grid at x%16==0 or y%16==0.
## Algorithm based on aztec_code_generator (MIT, Daniel Lenski / Dmitry Alimov).
## See NOTICE for attribution.

import std/[algorithm, sequtils]
import ../common/types

const Symbology = sbAztec

type AztecConf = tuple[size, layers, codewords, cwBits: int]

const AztecCompact: array[4, AztecConf] = [
  (size: 15, layers: 1, codewords: 17, cwBits: 6),
  (size: 19, layers: 2, codewords: 40, cwBits: 6),
  (size: 23, layers: 3, codewords: 51, cwBits: 8),
  (size: 27, layers: 4, codewords: 76, cwBits: 8),
]

const AztecFull: array[32, AztecConf] = [
  (size: 19, layers: 1, codewords: 21, cwBits: 6),
  (size: 23, layers: 2, codewords: 48, cwBits: 6),
  (size: 27, layers: 3, codewords: 60, cwBits: 8),
  (size: 31, layers: 4, codewords: 88, cwBits: 8),
  (size: 37, layers: 5, codewords: 120, cwBits: 8),
  (size: 41, layers: 6, codewords: 156, cwBits: 8),
  (size: 45, layers: 7, codewords: 196, cwBits: 8),
  (size: 49, layers: 8, codewords: 240, cwBits: 8),
  (size: 53, layers: 9, codewords: 230, cwBits: 10),
  (size: 57, layers: 10, codewords: 272, cwBits: 10),
  (size: 61, layers: 11, codewords: 316, cwBits: 10),
  (size: 67, layers: 12, codewords: 364, cwBits: 10),
  (size: 71, layers: 13, codewords: 416, cwBits: 10),
  (size: 75, layers: 14, codewords: 470, cwBits: 10),
  (size: 79, layers: 15, codewords: 528, cwBits: 10),
  (size: 83, layers: 16, codewords: 588, cwBits: 10),
  (size: 87, layers: 17, codewords: 652, cwBits: 10),
  (size: 91, layers: 18, codewords: 720, cwBits: 10),
  (size: 95, layers: 19, codewords: 790, cwBits: 10),
  (size: 101, layers: 20, codewords: 864, cwBits: 10),
  (size: 105, layers: 21, codewords: 940, cwBits: 10),
  (size: 109, layers: 22, codewords: 1020, cwBits: 10),
  (size: 113, layers: 23, codewords: 920, cwBits: 12),
  (size: 117, layers: 24, codewords: 992, cwBits: 12),
  (size: 121, layers: 25, codewords: 1066, cwBits: 12),
  (size: 125, layers: 26, codewords: 1144, cwBits: 12),
  (size: 131, layers: 27, codewords: 1224, cwBits: 12),
  (size: 135, layers: 28, codewords: 1306, cwBits: 12),
  (size: 139, layers: 29, codewords: 1392, cwBits: 12),
  (size: 143, layers: 30, codewords: 1480, cwBits: 12),
  (size: 147, layers: 31, codewords: 1570, cwBits: 12),
  (size: 151, layers: 32, codewords: 1664, cwBits: 12),
]

proc gfPoly(cwBits: int): int =
  case cwBits
  of 4: 19
  of 6: 67
  of 8: 301
  of 10: 1033
  of 12: 4201
  else: 67

# Tables and modulus travel as parameters rather than being captured: a
# nested proc that closes over them builds a ref environment, whose generated
# destructor spans a line range gcov and lcov disagree about, and `nimble
# coverage` suppresses no lcov error.
proc mulGF(a, b: int; alog, logT: openArray[int]; gf: int): int =
  if a == 0 or b == 0: 0 else: alog[(logT[a] + logT[b]) mod (gf - 1)]

proc reedSolomon(wd: var seq[int]; nd, nc, gf, pp: int) =
  ## GF(2^n) RS — in/out array: `wd[0..nd-1]` is data, `wd[nd..nd+nc-1]`
  ## receives the error-correction words.
  var logT = newSeq[int](gf)
  var alog = newSeq[int](gf)
  logT[0] = 1 - gf
  alog[0] = 1
  for i in 1 ..< gf:
    alog[i] = alog[i-1] * 2
    if alog[i] >= gf: alog[i] = alog[i] xor pp
    logT[alog[i]] = i
  var c = newSeq[int](nc + 1)
  c[0] = 1
  for i in 1 .. nc:
    c[i] = c[i-1]
    for j in countdown(i-1, 1): c[j] = c[j-1] xor mulGF(c[j], alog[i], alog,
        logT, gf)
    c[0] = mulGF(c[0], alog[i], alog, logT, gf)
  for i in nd ..< nd + nc: wd[i] = 0
  for i in 0 ..< nd:
    let k = wd[nd] xor wd[i]
    for j in 0 ..< nc:
      wd[nd + j] = mulGF(k, c[nc - j - 1], alog, logT, gf)
      if j < nc - 1: wd[nd + j] = wd[nd + j] xor wd[nd + j + 1]

proc addBits(bits: var seq[bool]; v, n: int) {.inline.} =
  for i in countdown(n - 1, 0): bits.add(((v shr i) and 1) == 1)

proc addBinary(bits: var seq[bool]; payload: string; start, len: int) =
  ## Emit Shift.BINARY (5 bits in UPPER/LOWER) + count + raw bytes.
  bits.addBits(31, 5)
  if len <= 31:
    bits.addBits(len, 5)
  else:
    bits.addBits(0, 5)
    bits.addBits(len - 31, 11)
  for k in start ..< start + len: bits.addBits(int(payload[k]), 8)

## Build the optimal Aztec bit sequence.
## Greedy mode selection: UPPER -> LOWER/DIGIT/PUNCT on demand; BINARY shift for
## the rest. Matches ISO/IEC 24778 Table 2 code assignments.
proc buildBits(payload: string): seq[bool] =
  proc upperIdx(c: char): int =
    if c == ' ': 1 elif c in 'A'..'Z': ord(c) - 63 else: -1

  proc lowerIdx(c: char): int =
    if c == ' ': 1 elif c in 'a'..'z': ord(c) - 95 else: -1

  proc digitIdx(c: char): int =
    if c == ' ': 1 elif c in '0'..'9': ord(c) - 46
    elif c == ',': 12 elif c == '.': 13 else: -1

  proc punctIdx(c: char): int =
    const tbl = "!\"#$%&'()*+,-./:;<=>?[]{}" # codes 6-30 per ISO 24778
    result = -1
    for i in 0 ..< tbl.len:
      if tbl[i] == c: return i + 6

  type Mode = enum mU, mL, mD
  var mode = mU
  var i = 0

  while i < payload.len:
    let c = payload[i]

    case mode
    of mU:
      let u = upperIdx(c)
      if u >= 0: result.addBits(u, 5); inc i; continue

      var nL = 0; var j = i
      while j < payload.len and lowerIdx(payload[j]) >= 0: inc j
      nL = j - i
      var nD = 0; j = i
      while j < payload.len and digitIdx(payload[j]) >= 0: inc j
      nD = j - i

      if nL > 0 and nL >= nD:
        result.addBits(28, 5); mode = mL
      elif nD >= 2:
        result.addBits(30, 5); mode = mD
      else:
        let p = punctIdx(c)
        if p >= 0:
          var jj = i + 1
          while jj < payload.len and punctIdx(payload[jj]) >= 0: inc jj
          var nDAfter = 0
          var jj2 = jj
          while jj2 < payload.len and digitIdx(payload[jj2]) >= 0: inc jj2; inc nDAfter
          if nDAfter >= 2:
            result.addBits(30, 5); mode = mD
          else:
            result.addBits(0, 5); result.addBits(p, 5); inc i
        else:
          var j2 = i
          while j2 < payload.len and upperIdx(payload[j2]) < 0 and
                lowerIdx(payload[j2]) < 0 and digitIdx(payload[j2]) < 0 and
                punctIdx(payload[j2]) < 0: inc j2
          result.addBinary(payload, i, max(1, j2 - i))
          i += max(1, j2 - i)

    of mL:
      let l = lowerIdx(c)
      if l >= 0: result.addBits(l, 5); inc i; continue

      let u = upperIdx(c)
      if u >= 0:
        result.addBits(28, 5); result.addBits(u, 5); inc i; continue

      let p = punctIdx(c)
      if p >= 0:
        result.addBits(0, 5); result.addBits(p, 5); inc i; continue

      var j = i
      while j < payload.len and lowerIdx(payload[j]) < 0 and upperIdx(payload[j]) < 0 and
            digitIdx(payload[j]) < 0 and punctIdx(payload[j]) < 0: inc j
      result.addBinary(payload, i, max(1, j - i))
      i += max(1, j - i)

    of mD:
      let d = digitIdx(c)
      if d >= 0: result.addBits(d, 4); inc i; continue

      let u = upperIdx(c)
      if u >= 0:
        var j = i + 1; while j < payload.len and upperIdx(payload[j]) >= 0: inc j
        if j - i <= 2:
          result.addBits(15, 4); result.addBits(u, 5); inc i
        else:
          result.addBits(14, 4); mode = mU
      else:
        let p = punctIdx(c)
        if p >= 0:
          result.addBits(0, 4); result.addBits(p, 5); inc i
        else:
          result.addBits(14, 4); mode = mU

## Pack bits into codewords with bit stuffing (avoid all-zero and all-ones words).
proc getDataCws(bits: seq[bool]; cwBits: int): seq[int] =
  var sub: seq[bool]
  for bit in bits:
    sub.add(bit)
    if sub.len == cwBits - 1:
      if sub.allIt(not it): sub.add(true)
      elif sub.allIt(it): sub.add(false)
    if sub.len >= cwBits:
      var v = 0
      for b in sub: v = (v shl 1) or (if b: 1 else: 0)
      result.add(v)
      sub = @[]
  if sub.len > 0:
    while sub.len < cwBits: sub.add(true)
    if sub.allIt(it): sub[^1] = false
    var v = 0
    for b in sub: v = (v shl 1) or (if b: 1 else: 0)
    result.add(v)

## Compact mode message: 2 bits (layers-1) + 6 bits (dataCwCount-1) ->
## 2 nibbles + 5 RS = 7 nibbles.
proc getModeMessage(layers, dataCwCount: int): seq[int] =
  let mw = ((layers - 1) shl 6) or (dataCwCount - 1)
  var cws = newSeq[int](7)
  cws[0] = (mw shr 4) and 0xF
  cws[1] = mw and 0xF
  reedSolomon(cws, 2, 5, 16, 19)
  result = cws

## Full mode message: 5 bits (layers-1) + 11 bits (dataCwCount-1) ->
## 4 nibbles + 6 RS = 10 nibbles.
proc getModeMessageFull(layers, dataCwCount: int): seq[int] =
  let mw = ((layers - 1) shl 11) or (dataCwCount - 1)
  var cws = newSeq[int](10)
  cws[0] = (mw shr 12) and 0xF
  cws[1] = (mw shr 8) and 0xF
  cws[2] = (mw shr 4) and 0xF
  cws[3] = mw and 0xF
  reedSolomon(cws, 4, 6, 16, 19)
  result = cws

proc encodeMatrix(cfg: AztecConf; isCompact: bool; payload: string; bits: seq[
    bool]): EncodeResult =
  let dataCws = getDataCws(bits, cfg.cwBits)
  let dataCwCount = dataCws.len

  var cws = newSeq[int](cfg.codewords)
  for i in 0 ..< dataCwCount: cws[i] = dataCws[i]
  let gf = 1 shl cfg.cwBits
  reedSolomon(cws, dataCwCount, cfg.codewords - dataCwCount, gf, gfPoly(cfg.cwBits))

  let sz = cfg.size
  let center = sz div 2
  let rr = if isCompact: 5 else: 7
  let sideSize = if isCompact: 7 else: 11

  var mat = newSeqWith(sz, newSeq[int](sz))

  # 1. Bull's eye (finder): alternating dark/light rings
  for x in -rr ..< rr:
    for y in -rr ..< rr:
      mat[center + y][center + x] = (max(abs(x), abs(y)) + 1) mod 2

  # 2. Orientation marks (6 dark cells at three corners)
  mat[center - rr][center - rr] = 1
  mat[center - rr + 1][center - rr] = 1
  mat[center - rr][center - rr + 1] = 1
  mat[center - rr][center + rr] = 1
  mat[center - rr + 1][center + rr] = 1
  mat[center + rr - 1][center + rr] = 1

  # 3. Reference grid (full mode only): alternating cells outside finder
  if not isCompact:
    for ax in 0 ..< sz:
      for ay in 0 ..< sz:
        let rx = ax - center
        let ry = ay - center
        if abs(rx) <= rr and abs(ry) <= rr: continue
        if rx mod 16 == 0 or ry mod 16 == 0:
          mat[ay][ax] = if (rx + ry + 1) mod 2 != 0: 1 else: 0

  # 4. Data ring: reversed codeword bits placed 2 at a time in outward spiral
  var fullBits: seq[bool]
  for cw in cws:
    for i in countdown(cfg.cwBits - 1, 0): fullBits.add(((cw shr i) and 1) == 1)
  fullBits.reverse()

  # maxNum per layer differs: compact adds 4, full adds 3 (ISO 24778 §7.3 vs §7.4)
  let maxNumBase = rr * 2 + (if isCompact: 4 else: 3)

  var num = 2; var side = 0; var layerIdx = 0
  var posX = center - rr
  var posY = center - rr - 1

  var bi = 0
  while bi < fullBits.len:
    if layerIdx >= cfg.layers: break
    inc num
    let maxNum = maxNumBase + layerIdx * 4
    let b0 = fullBits[bi]
    let b1 = if bi + 1 < fullBits.len: fullBits[bi + 1] else: false
    bi += 2

    case side
    of 0: # top: move right; pair is two rows above the ring edge
      let dy0 = if not isCompact and (center - posY) mod 16 == 0: 1 else: 0
      let dy1 = if not isCompact and (center - posY + 1) mod 16 == 0: 2 else: 1
      mat[posY - dy0][posX] = if b0: 1 else: 0
      mat[posY - dy1][posX] = if b1: 1 else: 0
      inc posX
      if num > maxNum:
        num = 2; side = 1; dec posX; inc posY
      if not isCompact and (center - posX) mod 16 == 0: inc posX
      if not isCompact and (center - posY) mod 16 == 0: inc posY

    of 1: # right: move down; pair is two columns left of ring edge
      let dx0 = if not isCompact and (center - posX) mod 16 == 0: 1 else: 0
      let dx1 = if not isCompact and (center - posX + 1) mod 16 == 0: 2 else: 1
      mat[posY][posX - dx0] = if b1: 1 else: 0
      mat[posY][posX - dx1] = if b0: 1 else: 0
      inc posY
      if num > maxNum:
        num = 2; side = 2; posX -= 2
        if not isCompact and (center - posX - 1) mod 16 == 0: dec posX
        dec posY
      if not isCompact and (center - posY) mod 16 == 0: inc posY
      if not isCompact and (center - posX) mod 16 == 0: dec posX

    of 2: # bottom: move left; pair is two rows above the ring edge
      let dy0 = if not isCompact and (center - posY) mod 16 == 0: 1 else: 0
      let dy1 = if not isCompact and (center - posY + 1) mod 16 == 0: 2 else: 1
      mat[posY - dy0][posX] = if b1: 1 else: 0
      mat[posY - dy1][posX] = if b0: 1 else: 0
      dec posX
      if num > maxNum:
        num = 2; side = 3; inc posX; posY -= 2
        if not isCompact and (center - posY - 1) mod 16 == 0: dec posY
      if not isCompact and (center - posX) mod 16 == 0: dec posX
      if not isCompact and (center - posY) mod 16 == 0: dec posY

    else: # left: move up; pair is two columns right of ring edge
      let dx0 = if not isCompact and (center - posX) mod 16 == 0: 1 else: 0
      let dx1 = if not isCompact and (center - posX - 1) mod 16 == 0: 2 else: 1
      mat[posY][posX + dx1] = if b0: 1 else: 0
      mat[posY][posX + dx0] = if b1: 1 else: 0
      dec posY
      if num > maxNum:
        num = 2; side = 0; inc layerIdx
      if not isCompact and (center - posY) mod 16 == 0: dec posY

  # 5. Mode message: nibbles × 4 bits around the mode ring
  let modeCws = if isCompact: getModeMessage(cfg.layers, dataCwCount)
                else: getModeMessageFull(cfg.layers, dataCwCount)
  var modeBits: seq[bool]
  for cw in modeCws:
    for i in countdown(3, 0): modeBits.add(((cw shr i) and 1) == 1)

  var idx = 0
  for bitVal in modeBits:
    # Full mode: index 5 within each side falls on a reference grid line; skip it
    if not isCompact and (idx mod sideSize) == 5:
      inc idx
    let pos = idx mod sideSize
    var x, y: int
    case idx div sideSize
    of 0: x = pos + 2 - rr; y = -rr
    of 1: x = rr; y = pos + 2 - rr
    of 2: x = rr - pos - 2; y = rr
    else: x = -rr; y = rr - pos - 2
    mat[center + y][center + x] = if bitVal: 1 else: 0
    inc idx

  # 6. Convert to bool grid
  var grid = newSeq[seq[bool]](sz)
  for r in 0 ..< sz:
    grid[r] = newSeq[bool](sz)
    for c in 0 ..< sz: grid[r][c] = mat[r][c] == 1

  encodeOk(Symbology, payload, BarcodeModules(grid: grid), BarcodeLayout())

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as an Aztec Code matrix. Aztec has no fixed payload
  ## shape: any byte string encodes, and the layer count grows with it.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  if payload.len == 0:
    return encodeError(Symbology, ekValidation, "Aztec payload must not be empty")
  if payload.len > 3067:
    return encodeError(Symbology, ekValidation, "Aztec payload too long")

  let bits = buildBits(payload)

  # Try compact first (L1-L4: 15x15 to 27x27)
  for c in AztecCompact:
    let dcws = getDataCws(bits, c.cwBits)
    if float(dcws.len + 3) * 100.0 / 77.0 < float(c.codewords):
      return encodeMatrix(c, true, payload, bits)

  # Fall through to full mode (L1-L32: 19x19 to 151x151)
  for c in AztecFull:
    let dcws = getDataCws(bits, c.cwBits)
    if float(dcws.len + 3) * 100.0 / 77.0 < float(c.codewords):
      return encodeMatrix(c, false, payload, bits)

  encodeError(Symbology, ekValidation, "Aztec: payload too large for any symbol size")









