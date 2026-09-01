# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — Micro QR Code encoder.
##
## Reference: ISO/IEC 18004:2015 (Annex C). Versions M1–M4 (11×11 .. 17×17),
## numeric / alphanumeric / byte modes. Reed-Solomon error correction over
## GF(256) with primitive polynomial 0x11D (α=2), shared with QR Code.
##
## Micro QR uses a single finder (top-left), one timing pattern (row 0 and
## column 0, below/right of the finder), a 15-bit BCH(15,5) format word placed
## once around the finder, and four data mask patterns. Mask selection
## maximises the §7.8.3.2 penalty (dark count of the last row and column).
## M1 carries error detection only; M2–M4 carry L/M (M4 also Q).

import std/sequtils
import ../common/types
import contracts

const Symbology = sbMicroQr

# ── GF(256) with primitive polynomial 0x11D ─────────────────────────────────
# Same field as QR Code (ISO 18004 §7.5.2). Multiplication by α: shift left one
# bit, XOR 0x1D on overflow.

var gfExp: array[512, uint8]
var gfLog: array[256, int]

block:
  var x = 1u8
  for i in 0 ..< 255:
    gfExp[i] = x
    gfLog[x] = i
    let hi = (x and 0x80u8) != 0u8
    x = (x shl 1u8) xor (if hi: 0x1Du8 else: 0u8)
  for i in 255 ..< 512:
    gfExp[i] = gfExp[i - 255]

proc gfMul(a, b: uint8): uint8 {.inline.} =
  if a == 0 or b == 0: 0u8 else: gfExp[(gfLog[a] + gfLog[b]) mod 255]

proc rsGen(degree: int): seq[uint8] =
  result = @[1u8]
  for i in 0 ..< degree:
    let fac = gfExp[i]
    var nxt = newSeq[uint8](result.len + 1)
    for j in 0 ..< result.len:
      nxt[j] = nxt[j] xor gfMul(result[j], fac)
      nxt[j+1] = nxt[j+1] xor result[j]
    result = nxt

proc rsRem(data: seq[uint8]; gen: seq[uint8]): seq[uint8] =
  let n = gen.len - 1
  result = newSeq[uint8](n)
  for b in data:
    let c = b xor result[0]
    for i in 0 ..< n - 1:
      result[i] = result[i+1] xor gfMul(gen[n-1-i], c)
    result[n-1] = gfMul(gen[0], c)

# ── Versions, error-correction levels, capacities ────────────────────────────

type
  MqrVer* = enum mvM1 = 0, mvM2 = 1, mvM3 = 2, mvM4 = 3
  MqrEc* = enum ecDetect = 0, ecL = 1, ecM = 2, ecQ = 3
  MqrMode = enum mmNumeric = 0, mmAlpha = 1, mmByte = 2

const SizeOf*: array[MqrVer, int] = [11, 13, 15, 17]

type Spec = tuple[d, e, sym, cap: int] # data CW, EC CW, symbol number, data bits

const InvalidSpec: Spec = (d: -1, e: 0, sym: 0, cap: 0)

const SpecTable: array[MqrVer, array[MqrEc, Spec]] = [
  # M1: detect only
  [(d: 3, e: 2, sym: 0, cap: 20), InvalidSpec, InvalidSpec, InvalidSpec],
  # M2: L, M
  [InvalidSpec, (d: 5, e: 5, sym: 1, cap: 40),
   (d: 4, e: 6, sym: 2, cap: 32), InvalidSpec],
  # M3: L, M
  [InvalidSpec, (d: 11, e: 6, sym: 3, cap: 84),
   (d: 9, e: 8, sym: 4, cap: 68), InvalidSpec],
  # M4: L, M, Q
  [InvalidSpec, (d: 16, e: 8, sym: 5, cap: 128),
   (d: 14, e: 10, sym: 6, cap: 112), (d: 10, e: 14, sym: 7, cap: 80)],
]

proc isFourBitVer(ver: MqrVer): bool {.inline.} = ver == mvM1 or ver == mvM3

# Mode indicator length (bits): M1 has none.
const ModeBits: array[MqrVer, int] = [0, 1, 2, 3]

# Character-count indicator length (bits), -1 = mode unavailable.
const CharCountBits: array[MqrVer, array[MqrMode, int]] = [
  [3, -1, -1], # M1: numeric only
  [4, 3, -1],  # M2: numeric, alphanumeric
  [5, 4, 4],   # M3: numeric, alphanumeric, byte
  [6, 5, 5],   # M4: numeric, alphanumeric, byte
]

# Terminator length (bits), per ISO 18004.
const TermBits: array[MqrVer, int] = [3, 5, 7, 9]

# Format information words (15-bit BCH, mask 0x4445 already applied), indexed by
# symbol number * 4 + mask pattern. Source: ISO/IEC 18004:2015 Table C.1.
const FormatInfo: array[32, int] = [
  0x4445, 0x4172, 0x4e2b, 0x4b1c, 0x55ae, 0x5099, 0x5fc0, 0x5af7,
  0x6793, 0x62a4, 0x6dfd, 0x68ca, 0x7678, 0x734f, 0x7c16, 0x7921,
  0x06de, 0x03e9, 0x0cb0, 0x0987, 0x1735, 0x1202, 0x1d5b, 0x186c,
  0x2508, 0x203f, 0x2f66, 0x2a51, 0x34e3, 0x31d4, 0x3e8d, 0x3bba,
]

const QrAlphaSet = {'0'..'9', 'A'..'Z', ' ', '$', '%', '*', '+', '-', '.', '/', ':'}

proc alphaVal(c: char): int {.inline.} =
  case c
  of '0'..'9': ord(c) - ord('0')
  of 'A'..'Z': ord(c) - ord('A') + 10
  of ' ': 36
  of '$': 37
  of '%': 38
  of '*': 39
  of '+': 40
  of '-': 41
  of '.': 42
  of '/': 43
  of ':': 44
  else: -1

proc canEncode(payload: string; ver: MqrVer; mode: MqrMode): bool {.inline.} =
  ## Whether `mode` can represent every char of `payload` at this version.
  case mode
  of mmNumeric: payload.allIt(it in '0'..'9')
  of mmAlpha: ver >= mvM2 and payload.allIt(it in QrAlphaSet)
  of mmByte: ver >= mvM3

proc bestMode(payload: string; ver: MqrVer): MqrMode =
  ## Most compact encodable mode for this version, or `mmNumeric` as a
  ## placeholder when no mode fits (caller guards with `canEncode`).
  if canEncode(payload, ver, mmNumeric):
    return mmNumeric
  if canEncode(payload, ver, mmAlpha):
    return mmAlpha
  if canEncode(payload, ver, mmByte):
    return mmByte
  mmNumeric

proc push(bits: var seq[bool]; v, n: int) =
  for i in countdown(n - 1, 0):
    bits.add(((v shr i) and 1) == 1)

proc dataBits(payload: string; ver: MqrVer; mode: MqrMode): seq[bool] =
  ## Mode indicator + character-count + encoded data (no terminator/padding).
  if ModeBits[ver] > 0:
    result.push(ord(mode), ModeBits[ver])
  result.push(payload.len, CharCountBits[ver][mode])
  case mode
  of mmNumeric:
    var i = 0
    while i < payload.len:
      let rem = payload.len - i
      if rem >= 3:
        result.push((ord(payload[i]) - 48) * 100 +
                    (ord(payload[i+1]) - 48) * 10 +
                    (ord(payload[i+2]) - 48), 10)
        i += 3
      elif rem == 2:
        result.push((ord(payload[i]) - 48) * 10 + (ord(payload[i+1]) - 48), 7)
        i += 2
      else:
        result.push(ord(payload[i]) - 48, 4)
        i += 1
  of mmAlpha:
    var i = 0
    while i < payload.len:
      if i + 1 < payload.len:
        result.push(alphaVal(payload[i]) * 45 + alphaVal(payload[i+1]), 11)
        i += 2
      else:
        result.push(alphaVal(payload[i]), 6)
        i += 1
  of mmByte:
    for c in payload:
      result.push(int(c), 8)

proc bitsToBytes(bits: seq[bool]; numBytes: int): seq[uint8] {.contractual.} =
  ## Pack MSB-first; a short final byte (M1/M3) is zero-padded on the LSB side.
  require:
    numBytes >= 0 and bits.len <= numBytes * 8
  body:
    result = newSeq[uint8](numBytes)
    for i in 0 ..< numBytes:
      var b = 0u8
      for j in 0 ..< 8:
        let k = i * 8 + j
        if k < bits.len and bits[k]:
          b = b or (1u8 shl uint8(7 - j))
      result[i] = b

proc toBits(bytes: seq[uint8]; lastFour: bool): seq[bool] =
  ## Unpack codewords MSB-first. For M1/M3 the final codeword is 4 bits and
  ## lives in the HIGH nibble of the last byte (bitsToBytes zero-pads the low
  ## side), so emit bits 7..4 there — matching the spec's ``last >> 4`` split.
  for k, b in bytes:
    if lastFour and k == bytes.high:
      for i in countdown(7, 4):
        result.add(((b shr i) and 1) == 1)
    else:
      for i in countdown(7, 0):
        result.add(((b shr i) and 1) == 1)

proc buildMessage(payload: string; ver: MqrVer; ec: MqrEc): seq[bool] =
  ## Full bit stream (data + EC codewords) placed into the encoding region.
  let sp = SpecTable[ver][ec]
  if sp.d < 0:
    return @[] # invalid (ver, ec) pairing
  let mode = bestMode(payload, ver)
  var bits = dataBits(payload, ver, mode)
  # Terminator (capped at remaining capacity).
  let term = min(sp.cap - bits.len, TermBits[ver])
  for _ in 0 ..< term:
    bits.add(false)
  # Byte-boundary padding: M2/M4 only (M1/M3 keep the 4-bit final codeword).
  if not isFourBitVer(ver):
    while bits.len mod 8 != 0:
      bits.add(false)
  # Pad to data capacity: M1/M3 zero-fill to the bit; M2/M4 alternate 0xEC/0x11.
  if isFourBitVer(ver):
    while bits.len < sp.cap:
      bits.add(false)
  else:
    var pi = 0
    while bits.len < sp.cap:
      let pad = if (pi and 1) == 0: 0xECu8 else: 0x11u8
      for i in 0 ..< 8:
        bits.add(((pad shr uint8(7 - i)) and 1) == 1)
      inc pi
  assert bits.len == sp.cap, "Micro QR bit stream " & $bits.len &
    " != capacity " & $sp.cap
  # Data codewords, then Reed-Solomon EC over them.
  let data = bitsToBytes(bits, sp.d)
  let gen = rsGen(sp.e)
  let ecw = rsRem(data, gen)
  result = toBits(data, isFourBitVer(ver))
  result &= toBits(ecw, false)

# ── Matrix ────────────────────────────────────────────────────────────────────

type
  Mq = object
    n: int
    d: seq[seq[uint8]] # 0=light,1=dark
    fn: seq[seq[bool]] # true = function pattern (finder/timing/format)

proc newMq(n: int): Mq =
  result.n = n
  result.d = newSeqWith(n, newSeq[uint8](n))
  result.fn = newSeqWith(n, newSeq[bool](n))

proc putFn(m: var Mq; r, c: int; dark: bool) =
  if r >= 0 and r < m.n and c >= 0 and c < m.n:
    m.d[r][c] = if dark: 1u8 else: 0u8
    m.fn[r][c] = true

proc setupFinder(m: var Mq) =
  ## Single 7×7 finder at top-left + 1-module white separators (row/col 7).
  for r in 0 ..< 8:
    for c in 0 ..< 8:
      let dark = (r in 0..6 and c in {0, 6}) or
                 (r in {0, 6} and c in 0..6) or
                 (r in 2..4 and c in 2..4)
      m.putFn(r, c, dark)

proc setupTiming(m: var Mq) =
  ## Timing along row 0 (cols 8..n-1) and column 0 (rows 8..n-1), dark on even.
  for c in 8 ..< m.n:
    m.putFn(0, c, c mod 2 == 0)
  for r in 8 ..< m.n:
    m.putFn(r, 0, r mod 2 == 0)

proc reserveFormat(m: var Mq) =
  ## Reserve the 15 format-info cells (col 8 rows 1-8, row 8 cols 1-8) as light.
  for i in 1 ..< 8:
    m.putFn(i, 8, false)
    m.putFn(8, i, false)
  m.putFn(8, 8, false)

proc placeData(m: var Mq; bits: seq[bool]; ver: MqrVer) =
  ## Two-column zigzag from the right (ISO 18004 §7.7.3). M1/M3 shift the
  ## up/down phase by two columns so the walk starts at the lower-right corner.
  let phaseShift = if isFourBitVer(ver): 2 else: 0
  var idx = 0
  var right = m.n - 1
  while right >= 1:
    for vertical in 0 ..< m.n:
      let upwards = ((right + phaseShift) and 2) == 0
      let i = if upwards: m.n - 1 - vertical else: vertical
      for z in [right, right - 1]:
        let j = z
        if j < 0 or j >= m.n:
          continue
        if not m.fn[i][j] and idx < bits.len:
          m.d[i][j] = if bits[idx]: 1u8 else: 0u8
          inc idx
    right -= 2

proc applyMask(m: var Mq; mk: int) =
  ## Apply one of the four Micro QR mask patterns to data cells only.
  for i in 0 ..< m.n:
    for j in 0 ..< m.n:
      if m.fn[i][j]:
        continue
      let flip = case mk
        of 0: (i and 1) == 0
        of 1: ((i div 2) + (j div 3)) mod 2 == 0
        of 2: (((i * j) mod 2) + ((i * j) mod 3)) mod 2 == 0
        else: (((i + j) mod 2) + ((i * j) mod 3)) mod 2 == 0
      if flip:
        m.d[i][j] = m.d[i][j] xor 1u8

proc penalty(m: Mq): int =
  ## §7.8.3.2 Micro QR penalty: dark modules in the last column and last row
  ## (excluding index 0), combined as min*16 + max.
  var sum1 = 0 # last column, rows 1..n-1
  var sum2 = 0 # last row, cols 1..n-1
  for i in 1 ..< m.n:
    if m.d[i][m.n - 1] == 1:
      inc sum1
    if m.d[m.n - 1][i] == 1:
      inc sum2
  if sum1 <= sum2: sum1 * 16 + sum2 else: sum2 * 16 + sum1

proc applyFormat(m: var Mq; sym, mk: int) {.contractual.} =
  ## Place the 15-bit format word around the finder (ISO 18004 §7.9.2).
  require:
    sym in 0 .. 7 and mk in 0 .. 3
  body:
    let b = FormatInfo[sym * 4 + mk]
    for i in 0 .. 7:
      let vbit = (b shr i) and 1
      let hbit = (b shr (14 - i)) and 1
      m.d[i + 1][8] = uint8(vbit) # column 8, rows 1..8 (LSB at row 1)
      m.d[8][i + 1] = uint8(hbit) # row 8, cols 1..8 (MSB at col 1)

# ── Public encoder ────────────────────────────────────────────────────────────

proc encodeAt*(payload: string; ver: MqrVer; ec: MqrEc): EncodeResult =
  ## Encode `payload` into a Micro QR symbol of the given version and EC level.
  if payload.len == 0:
    return encodeError(Symbology, ekValidation, "Micro QR payload must not be empty")
  if SpecTable[ver][ec].d < 0:
    return encodeError(Symbology, ekValidation,
      "Micro QR " & $ver & " has no " & $ec & " error-correction level")
  let mode = bestMode(payload, ver)
  if not canEncode(payload, ver, mode) or CharCountBits[ver][mode] < 0:
    return encodeError(Symbology, ekValidation,
      "Micro QR " & $ver & " cannot encode this payload (no fitting mode)")
  # Capacity check: data bits must fit before terminator/padding.
  let sp = SpecTable[ver][ec]
  var probe = dataBits(payload, ver, mode)
  if probe.len > sp.cap:
    return encodeError(Symbology, ekValidation,
      "Micro QR payload too long for " & $ver)
  let bits = buildMessage(payload, ver, ec)
  if bits.len == 0:
    return encodeError(Symbology, ekValidation, "Micro QR " & $ver & "/" & $ec & " unsupported")

  var best: Mq
  var bestScore = -1
  var bestMk = 0
  for mk in 0 .. 3:
    var m = newMq(SizeOf[ver])
    setupFinder(m); setupTiming(m); reserveFormat(m)
    placeData(m, bits, ver)
    applyMask(m, mk)
    let s = penalty(m)
    if s > bestScore:
      bestScore = s
      best = m
      bestMk = mk
  applyFormat(best, sp.sym, bestMk)

  var grid = newSeq[seq[bool]](best.n)
  for r in 0 ..< best.n:
    grid[r] = newSeq[bool](best.n)
    for c in 0 ..< best.n:
      grid[r][c] = best.d[r][c] == 1
  encodeOk(Symbology, payload, BarcodeModules(grid: grid), BarcodeLayout())

proc selectVerEc(payload: string): tuple[ver: MqrVer; ec: MqrEc] =
  ## Smallest version that fits, then the highest EC level within it (boost).
  for ver in MqrVer:
    let mode = bestMode(payload, ver)
    if not canEncode(payload, ver, mode) or CharCountBits[ver][mode] < 0:
      continue
    let probe = dataBits(payload, ver, mode)
    # Try EC levels high → low for this version (Q > M > L > detect).
    for ec in [ecQ, ecM, ecL, ecDetect]:
      let sp = SpecTable[ver][ec]
      if sp.d < 0:
        continue
      # Capacity includes the terminator; reserve its bit budget.
      if probe.len + min(sp.cap - probe.len, TermBits[ver]) <= sp.cap and
         probe.len <= sp.cap:
        return (ver, ec)
  (mvM4, ecQ)

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a Micro QR Code. Smaller than QR and more limited: the
  ## version range caps what fits.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  if payload.len == 0:
    return encodeError(Symbology, ekValidation, "Micro QR payload must not be empty")
  let (ver, ec) = selectVerEc(payload)
  encodeAt(payload, ver, ec)









