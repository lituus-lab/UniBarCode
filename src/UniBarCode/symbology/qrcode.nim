# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — QR Code encoder.
## ISO/IEC 18004:2015. Numeric / Alphanumeric / Byte modes, versions 1-40,
## error-correction level M. Reed-Solomon over GF(256) with primitive
## polynomial 0x11D (x^8+x^4+x^3+x^2+1, alpha=2).

import std/sequtils
import ../common/types

const Symbology = sbQrCode

# ── GF(256) with primitive polynomial 0x11D ─────────────────────────────────

var gfExp: array[512, uint8]
var gfLog: array[256, int]

block:
  ## GF(256) with primitive polynomial x^8+x^4+x^3+x^2+1 (0x11D), α=2.
  ## Multiplication by α: shift left one bit, XOR 0x1D on overflow.
  ## Source: ISO 18004:2015 §7.5.2.
  var x = 1u8
  for i in 0 ..< 255:
    gfExp[i] = x
    gfLog[x] = i
    let hi = (x and 0x80u8) != 0u8
    x = (x shl 1u8) xor (if hi: 0x1Du8 else: 0u8)
  for i in 255 ..< 512: gfExp[i] = gfExp[i - 255]

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
  let n = gen.len - 1 # degree = number of EC codewords; gen[n] = 1 (leading coeff excluded)
  result = newSeq[uint8](n)
  for b in data:
    let c = b xor result[0]
    for i in 0 ..< n - 1:
      result[i] = result[i+1] xor gfMul(gen[n-1-i], c)
    result[n-1] = gfMul(gen[0], c)

# ── Version/EC tables (totalCW, ecDeg, g1n, g1d, g1t, g2n, g2d, g2t) ───────

type EcLevel = enum ecL = 0, ecM = 1, ecQ = 2, ecH = 3

type QrMode = enum mNumeric = 1, mAlpha = 2, mByte = 4

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

proc bestMode(payload: string): QrMode =
  if payload.allIt(it in '0'..'9'): return mNumeric
  if payload.allIt(it in QrAlphaSet): return mAlpha
  mByte

proc encodedBitCount(payload: string; mode: QrMode; ver: int): int =
  let n = payload.len
  let countBits =
    if mode == mNumeric:
      if ver <= 9: 10 elif ver <= 26: 12 else: 14
    elif mode == mAlpha:
      if ver <= 9: 9 elif ver <= 26: 11 else: 13
    else:
      if ver <= 9: 8 else: 16
  let rem = n mod 3
  let dataBits =
    if mode == mNumeric:
      (n div 3)*10 + (if rem == 2: 7 elif rem == 1: 4 else: 0)
    elif mode == mAlpha:
      (n div 2)*11 + (if n mod 2 == 1: 6 else: 0)
    else:
      n * 8
  4 + countBits + dataBits

const VT: array[40, array[4, array[8, int]]] = [
  [[19, 7, 1, 19, 26, 0, 0, 0], [16, 10, 1, 16, 26, 0, 0, 0], [13, 13, 1, 13,
      26, 0, 0, 0], [9, 17, 1, 9, 26, 0, 0, 0]],
  [[34, 10, 1, 34, 44, 0, 0, 0], [28, 16, 1, 28, 44, 0, 0, 0], [22, 22, 1, 22,
      44, 0, 0, 0], [16, 28, 1, 16, 44, 0, 0, 0]],
  [[55, 15, 1, 55, 70, 0, 0, 0], [44, 26, 1, 44, 70, 0, 0, 0], [34, 18, 2, 17,
      35, 0, 0, 0], [26, 22, 2, 13, 35, 0, 0, 0]],
  [[80, 20, 1, 80, 100, 0, 0, 0], [64, 18, 2, 32, 50, 0, 0, 0], [48, 26, 2, 24,
      50, 0, 0, 0], [36, 16, 4, 9, 25, 0, 0, 0]],
  [[108, 26, 1, 108, 134, 0, 0, 0], [86, 24, 2, 43, 67, 0, 0, 0], [62, 18, 2,
      15, 33, 2, 16, 34], [46, 22, 2, 11, 33, 2, 12, 34]],
  [[136, 18, 2, 68, 86, 0, 0, 0], [108, 16, 4, 27, 43, 0, 0, 0], [76, 24, 4, 19,
      43, 0, 0, 0], [60, 28, 4, 15, 43, 0, 0, 0]],
  [[156, 20, 2, 78, 98, 0, 0, 0], [124, 18, 4, 31, 49, 0, 0, 0], [88, 18, 2, 14,
      32, 4, 15, 33], [66, 26, 4, 13, 39, 1, 14, 40]],
  [[194, 24, 2, 97, 121, 0, 0, 0], [154, 22, 2, 38, 60, 2, 39, 61], [110, 22, 4,
      18, 40, 2, 19, 41], [86, 26, 4, 14, 40, 2, 15, 41]],
  [[232, 30, 2, 116, 146, 0, 0, 0], [182, 22, 3, 36, 58, 2, 37, 59], [132, 20,
      4, 16, 36, 4, 17, 37], [100, 24, 4, 12, 36, 4, 13, 37]],
  [[274, 18, 2, 68, 86, 2, 69, 87], [216, 26, 4, 43, 69, 1, 44, 70], [154, 24,
      6, 19, 43, 2, 20, 44], [122, 28, 6, 15, 43, 2, 16, 44]],
  [[324, 20, 4, 81, 101, 0, 0, 0], [254, 30, 1, 50, 80, 4, 51, 81], [180, 28, 4,
      22, 50, 4, 23, 51], [140, 24, 3, 12, 36, 8, 13, 37]],
  [[370, 24, 2, 92, 116, 2, 93, 117], [290, 22, 6, 36, 58, 2, 37, 59], [206, 26,
      4, 20, 46, 6, 21, 47], [158, 28, 7, 14, 42, 4, 15, 43]],
  [[428, 26, 4, 107, 133, 0, 0, 0], [334, 22, 8, 37, 59, 1, 38, 60], [244, 24,
      8, 20, 44, 4, 21, 45], [180, 22, 12, 11, 33, 4, 12, 34]],
  [[461, 30, 3, 115, 145, 1, 116, 146], [365, 24, 4, 40, 64, 5, 41, 65], [261,
      20, 11, 16, 36, 5, 17, 37], [197, 24, 11, 12, 36, 5, 13, 37]],
  [[523, 22, 5, 87, 109, 1, 88, 110], [415, 24, 5, 41, 65, 5, 42, 66], [295, 30,
      5, 24, 54, 7, 25, 55], [223, 24, 11, 12, 36, 7, 13, 37]],
  [[589, 24, 5, 98, 122, 1, 99, 123], [453, 28, 7, 45, 73, 3, 46, 74], [325, 24,
      15, 19, 43, 2, 20, 44], [253, 30, 3, 15, 45, 13, 16, 46]],
  [[647, 28, 1, 107, 135, 5, 108, 136], [507, 28, 10, 46, 74, 1, 47, 75], [367,
      28, 1, 22, 50, 15, 23, 51], [283, 28, 2, 14, 42, 17, 15, 43]],
  [[721, 30, 5, 120, 150, 1, 121, 151], [563, 26, 9, 43, 69, 4, 44, 70], [397,
      28, 17, 22, 50, 1, 23, 51], [313, 28, 2, 14, 42, 19, 15, 43]],
  [[795, 28, 3, 113, 141, 4, 114, 142], [627, 26, 3, 44, 70, 11, 45, 71], [445,
      26, 17, 21, 47, 4, 22, 48], [341, 26, 9, 13, 39, 16, 14, 40]],
  [[861, 28, 3, 107, 135, 5, 108, 136], [669, 26, 3, 41, 67, 13, 42, 68], [485,
      30, 15, 24, 54, 5, 25, 55], [385, 28, 15, 15, 43, 10, 16, 44]],
  [[932, 28, 4, 116, 144, 4, 117, 145], [714, 26, 17, 42, 68, 0, 0, 0], [512,
      28, 17, 22, 50, 6, 23, 51], [406, 30, 19, 16, 46, 6, 17, 47]],
  [[1006, 28, 2, 111, 139, 7, 112, 140], [782, 28, 17, 46, 74, 0, 0, 0], [568,
      30, 7, 24, 54, 16, 25, 55], [442, 24, 34, 13, 37, 0, 0, 0]],
  [[1094, 30, 4, 121, 151, 5, 122, 152], [860, 28, 4, 47, 75, 14, 48, 76], [614,
      30, 11, 24, 54, 14, 25, 55], [464, 30, 16, 15, 45, 14, 16, 46]],
  [[1174, 30, 6, 117, 147, 4, 118, 148], [914, 28, 6, 45, 73, 14, 46, 74], [664,
      30, 11, 24, 54, 16, 25, 55], [514, 30, 30, 16, 46, 2, 17, 47]],
  [[1276, 26, 8, 106, 132, 4, 107, 133], [1000, 28, 8, 47, 75, 13, 48, 76], [
      718, 30, 7, 24, 54, 22, 25, 55], [538, 30, 22, 15, 45, 13, 16, 46]],
  [[1370, 28, 10, 114, 142, 2, 115, 143], [1062, 28, 19, 46, 74, 4, 47, 75], [
      754, 28, 28, 22, 50, 6, 23, 51], [596, 30, 33, 16, 46, 4, 17, 47]],
  [[1468, 30, 8, 122, 152, 4, 123, 153], [1128, 28, 22, 45, 73, 3, 46, 74], [
      808, 30, 8, 23, 53, 26, 24, 54], [628, 30, 12, 15, 45, 28, 16, 46]],
  [[1531, 30, 3, 117, 147, 10, 118, 148], [1193, 28, 3, 45, 73, 23, 46, 74], [
      871, 30, 4, 24, 54, 31, 25, 55], [661, 30, 11, 15, 45, 31, 16, 46]],
  [[1631, 30, 7, 116, 146, 7, 117, 147], [1267, 28, 21, 45, 73, 7, 46, 74], [
      911, 30, 1, 23, 53, 37, 24, 54], [701, 30, 19, 15, 45, 26, 16, 46]],
  [[1735, 30, 5, 115, 145, 10, 116, 146], [1373, 28, 19, 47, 75, 10, 48, 76], [
      985, 30, 15, 24, 54, 25, 25, 55], [745, 30, 23, 15, 45, 25, 16, 46]],
  [[1843, 30, 13, 115, 145, 3, 116, 146], [1455, 28, 2, 46, 74, 29, 47, 75], [
      1033, 30, 42, 24, 54, 1, 25, 55], [793, 30, 23, 15, 45, 28, 16, 46]],
  [[1955, 30, 17, 115, 145, 0, 0, 0], [1541, 28, 10, 46, 74, 23, 47, 75], [1115,
      30, 10, 24, 54, 35, 25, 55], [845, 30, 19, 15, 45, 35, 16, 46]],
  [[2071, 30, 17, 115, 145, 1, 116, 146], [1631, 28, 14, 46, 74, 21, 47, 75], [
      1171, 30, 29, 24, 54, 19, 25, 55], [901, 30, 11, 15, 45, 46, 16, 46]],
  [[2191, 30, 13, 115, 145, 6, 116, 146], [1725, 28, 14, 46, 74, 23, 47, 75], [
      1231, 30, 44, 24, 54, 7, 25, 55], [961, 30, 59, 16, 46, 1, 17, 47]],
  [[2306, 30, 12, 121, 151, 7, 122, 152], [1812, 28, 12, 47, 75, 26, 48, 76], [
      1286, 30, 39, 24, 54, 14, 25, 55], [986, 30, 22, 15, 45, 41, 16, 46]],
  [[2434, 30, 6, 121, 151, 14, 122, 152], [1914, 28, 6, 47, 75, 34, 48, 76], [
      1354, 30, 46, 24, 54, 10, 25, 55], [1054, 30, 2, 15, 45, 64, 16, 46]],
  [[2566, 30, 17, 122, 152, 4, 123, 153], [1992, 28, 29, 46, 74, 14, 47, 75], [
      1426, 30, 49, 24, 54, 10, 25, 55], [1096, 30, 24, 15, 45, 46, 16, 46]],
  [[2702, 30, 4, 122, 152, 18, 123, 153], [2102, 28, 13, 46, 74, 32, 47, 75], [
      1502, 30, 48, 24, 54, 14, 25, 55], [1142, 30, 42, 15, 45, 32, 16, 46]],
  [[2812, 30, 20, 117, 147, 4, 118, 148], [2216, 28, 40, 47, 75, 7, 48, 76], [
      1582, 30, 43, 24, 54, 22, 25, 55], [1222, 30, 10, 15, 45, 67, 16, 46]],
  [[2956, 30, 19, 118, 148, 6, 119, 149], [2334, 28, 18, 47, 75, 31, 48, 76], [
      1666, 30, 34, 24, 54, 34, 25, 55], [1276, 30, 20, 15, 45, 61, 16, 46]],
]

# Compile-time self-check of the VT table (ISO/IEC 18004 §7.5.1). Each entry is
# [dataCW, ecDeg, g1n, g1d, g1t, g2n, g2d, g2t]; the block data CW must sum to
# the total, group 2's block size is group 1's plus one, and the per-block
# totals (g1t/g2t) are the data size plus the EC degree. Catches a class of bug
# that previously produced malformed symbols at level M (V30-33, V35-40).
static:
  for v in 0 ..< 40:
    for e in 0 ..< 4:
      let t = VT[v][e]
      doAssert t[2]*t[3] + t[5]*t[6] == t[0],
        "VT[" & $(v+1) & "][" & $e & "] block data CW != total"
      doAssert t[4] == t[3] + t[1], "VT g1t != g1d+ecDeg"
      if t[5] > 0:
        doAssert t[6] == t[3] + 1, "VT g2d != g1d+1"
        doAssert t[7] == t[6] + t[1], "VT g2t != g2d+ecDeg"

const AlignPos: array[40, seq[int]] = [
  @[], @[6, 18], @[6, 22], @[6, 26], @[6, 30], @[6, 34],
  @[6, 22, 38], @[6, 24, 42], @[6, 26, 46], @[6, 28, 50],
  @[6, 30, 54], @[6, 32, 58], @[6, 34, 62], @[6, 26, 46, 66],
  @[6, 26, 48, 70], @[6, 26, 50, 74], @[6, 30, 54, 78], @[6, 30, 56, 82],
  @[6, 30, 58, 86], @[6, 34, 62, 90], @[6, 28, 50, 72, 94], @[6, 26, 50, 74, 98],
  @[6, 30, 54, 78, 102], @[6, 28, 54, 80, 106], @[6, 32, 58, 84, 110],
  @[6, 30, 58, 86, 114], @[6, 34, 62, 90, 118], @[6, 26, 50, 74, 98, 122],
  @[6, 30, 54, 78, 102, 126], @[6, 26, 52, 78, 104, 130], @[6, 30, 56, 82, 108, 134],
  @[6, 34, 60, 86, 112, 138], @[6, 30, 58, 86, 114, 142], @[6, 34, 62, 90, 118, 146],
  @[6, 30, 54, 78, 102, 126, 150], @[6, 24, 50, 76, 102, 128, 154],
  @[6, 28, 54, 80, 106, 132, 158], @[6, 32, 58, 84, 110, 136, 162],
  @[6, 26, 54, 82, 110, 138, 166], @[6, 30, 58, 86, 114, 142, 170],
]

## Format information words (15-bit) for each EC level and mask pattern.
## XOR mask 101010000010010 already applied. Source: ISO 18004 Annex C.
const FI: array[4, array[8, int]] = [
  [0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976], # L
  [0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0], # M
  [0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED], # Q
  [0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B], # H
]

# ── Matrix ───────────────────────────────────────────────────────────────────

type QM = object
  n: int
  d: seq[seq[uint8]] # 0=light,1=dark,2=unset,3=rsv-light,4=rsv-dark

proc newQM(n: int): QM =
  result.n = n
  result.d = newSeqWith(n, newSeq[uint8](n))
  for r in result.d.mitems:
    for c in r.mitems: c = 2

proc rsv(m: var QM; r, c: int; dark: bool) =
  if r >= 0 and r < m.n and c >= 0 and c < m.n:
    m.d[r][c] = if dark: 4u8 else: 3u8

proc set(m: var QM; r, c: int; dark: bool) =
  if r >= 0 and r < m.n and c >= 0 and c < m.n:
    m.d[r][c] = if dark: 1u8 else: 0u8

proc isFn(m: QM; r, c: int): bool = m.d[r][c] != 2

proc addFinder(m: var QM; r0, c0: int) =
  for dr in -1..7:
    for dc in -1..7:
      let r = r0+dr; let c = c0+dc
      if r < 0 or r >= m.n or c < 0 or c >= m.n: continue
      let dark = (dr in 0..6 and dc in {0, 6}) or
                 (dr in {0, 6} and dc in 0..6) or
                 (dr in 2..4 and dc in 2..4)
      rsv(m, r, c, dark)

proc addAlign(m: var QM; r0, c0: int) =
  for dr in -2..2:
    for dc in -2..2:
      let dark = (dr == -2 or dr == 2) or (dc == -2 or dc == 2) or (dr == 0 and
          dc == 0)
      if not isFn(m, r0+dr, c0+dc): rsv(m, r0+dr, c0+dc, dark)

proc setupFn(m: var QM; ver: int) =
  addFinder(m, 0, 0); addFinder(m, 0, m.n-7); addFinder(m, m.n-7, 0)
  for i in 8 ..< m.n-8:
    if not isFn(m, 6, i): rsv(m, 6, i, i mod 2 == 0)
    if not isFn(m, i, 6): rsv(m, i, 6, i mod 2 == 0)
  for i in 0..8:
    if not isFn(m, 8, i): rsv(m, 8, i, false)
    if not isFn(m, i, 8): rsv(m, i, 8, false)
  for i in 0..7:
    rsv(m, m.n-1-i, 8, false); rsv(m, 8, m.n-1-i, false)
  rsv(m, 4*ver+9, 8, true) # dark module last — avoids overwrite by format strip loop
  let ap = AlignPos[ver-1]
  for r in ap:
    for c in ap:
      if not(r == 6 and c == 6) and not(r == 6 and c == ap[^1]) and not(r == ap[
          ^1] and c == 6):
        addAlign(m, r, c)
  if ver >= 7:
    for i in 0..<18:
      rsv(m, i div 3, m.n-11+i mod 3, false)
      rsv(m, m.n-11+i mod 3, i div 3, false)

proc placeData(m: var QM; cws: seq[uint8]) =
  ## Two-column zigzag scan, direction alternating per pair (ISO 18004 §7.7.3).
  ## 'up' must persist outside the outer loop so direction truly alternates.
  var idx = 0; var bit = 7
  var right = m.n - 1
  var up = true
  while right >= 1:
    if right == 6: dec right
    var r = if up: m.n - 1 else: 0
    while r >= 0 and r < m.n:
      for dc in [right, right-1]:
        if not isFn(m, r, dc):
          var dark = false
          if idx < cws.len:
            dark = ((cws[idx] shr bit) and 1) == 1
            dec bit
            if bit < 0: bit = 7; inc idx
          set(m, r, dc, dark)
      if up: dec r else: inc r
    up = not up; right -= 2

proc applyMask(m: var QM; mk: int) =
  ## Apply mask pattern to DATA cells only.
  ## Reserved cells have values 3 (rsv-light) or 4 (rsv-dark); data cells 0 or 1.
  ## After placeData no cell has value 2, so isFn() returns true for everything —
  ## skip reserved cells (>= 3) explicitly rather than using isFn().
  for r in 0..<m.n:
    for c in 0..<m.n:
      if m.d[r][c] >= 3: continue # skip reserved / function modules
      let flip = case mk
        of 0: (r+c) mod 2 == 0
        of 1: r mod 2 == 0
        of 2: c mod 3 == 0
        of 3: (r+c) mod 3 == 0
        of 4: (r div 2 + c div 3) mod 2 == 0
        of 5: (r*c) mod 2 + (r*c) mod 3 == 0
        of 6: ((r*c) mod 2 + (r*c) mod 3) mod 2 == 0
        else: ((r+c) mod 2 + (r*c) mod 3) mod 2 == 0
      if flip: m.d[r][c] = m.d[r][c] xor 1u8

proc applyFormat(m: var QM; ec: EcLevel; mk: int) =
  ## Place both copies of the 15-bit format word (ISO 18004 §7.9.2, Figure 19).
  let b = FI[ord(ec)][mk]
  for i in 0..5:
    m.d[i][8] = if ((b shr i) and 1) == 1: 1u8 else: 0u8
  m.d[7][8] = if ((b shr 6) and 1) == 1: 1u8 else: 0u8
  m.d[8][8] = if ((b shr 7) and 1) == 1: 1u8 else: 0u8
  m.d[8][7] = if ((b shr 8) and 1) == 1: 1u8 else: 0u8
  for i in 0..5:
    m.d[8][5-i] = if ((b shr (9+i)) and 1) == 1: 1u8 else: 0u8
  for i in 0..7:
    m.d[8][m.n-1-i] = if ((b shr i) and 1) == 1: 1u8 else: 0u8
  m.d[m.n-8][8] = 1u8
  for i in 0..6:
    m.d[m.n-7+i][8] = if ((b shr (8+i)) and 1) == 1: 1u8 else: 0u8

proc isDark(v: uint8): bool {.inline.} = v == 1u8 or v == 4u8 # 1=data-dark, 4=rsv-dark

proc versionInfoWord(ver: int): int =
  ## 18-bit version information word: 6-bit version + 12-bit BCH(7,1).
  ## Generator: x^12+x^11+x^10+x^9+x^8+x^5+x^2+1 = 0x1F25. Source: ISO 18004 §7.10.
  var d = ver shl 12
  for shift in countdown(5, 0):
    if ((d shr (shift + 12)) and 1) != 0:
      d = d xor (0x1F25 shl shift)
  (ver shl 12) or d

proc applyVersion(m: var QM; ver: int) =
  ## Write version information into the two 6×3 reserved areas (ISO 18004 §7.10).
  ## No-op for versions 1-6.
  if ver < 7: return
  let vi = versionInfoWord(ver)
  for i in 0 ..< 18:
    let dark = ((vi shr i) and 1) != 0
    rsv(m, i div 3, m.n - 11 + i mod 3, dark)
    rsv(m, m.n - 11 + i mod 3, i div 3, dark)

proc penalty(m: QM): int =
  ## Evaluate mask penalty (ISO 18004 §7.8.3).
  ## Values 3 and 4 are reserved; treat 0/3 as light and 1/4 as dark.
  let n = m.n
  for r in 0..<n:
    var run = 1
    for c in 1..<n:
      if isDark(m.d[r][c]) == isDark(m.d[r][c-1]): inc run
      else:
        if run >= 5: result += 3 + (run-5)
        run = 1
    if run >= 5: result += 3 + (run-5)
  for c in 0..<n:
    var run = 1
    for r in 1..<n:
      if isDark(m.d[r][c]) == isDark(m.d[r-1][c]): inc run
      else:
        if run >= 5: result += 3 + (run-5)
        run = 1
    if run >= 5: result += 3 + (run-5)
  for r in 0..<n-1:
    for c in 0..<n-1:
      let v = isDark(m.d[r][c])
      if v == isDark(m.d[r][c+1]) and v == isDark(m.d[r+1][c]) and
         v == isDark(m.d[r+1][c+1]): result += 3
  # N3: 1:1:3:1:1 finder-like pattern (or its inverse) in rows/cols, 40 each
  # (ISO 18004 §7.8.3). `a` is the leading color, so one test covers both the
  # dark- and light-centred forms.
  for r in 0..<n:
    for c in 0..<(n-6):
      let a = isDark(m.d[r][c])
      if a != isDark(m.d[r][c+1]) and a == isDark(m.d[r][c+2]) and
         a == isDark(m.d[r][c+3]) and a == isDark(m.d[r][c+4]) and
         a != isDark(m.d[r][c+5]) and a == isDark(m.d[r][c+6]): result += 40
  for c in 0..<n:
    for r in 0..<(n-6):
      let a = isDark(m.d[r][c])
      if a != isDark(m.d[r+1][c]) and a == isDark(m.d[r+2][c]) and
         a == isDark(m.d[r+3][c]) and a == isDark(m.d[r+4][c]) and
         a != isDark(m.d[r+5][c]) and a == isDark(m.d[r+6][c]): result += 40
  var dark = 0
  for r in 0..<n:
    for c in 0..<n:
      if isDark(m.d[r][c]): inc dark
  let pct = (dark*100) div (n*n)
  let k1 = abs((pct div 5)-10); let k2 = abs(((pct+5) div 5)-10)
  result += min(k1, k2)*10

# ── Data building ─────────────────────────────────────────────────────────────

proc selectVer(payload: string; mode: QrMode; ec: EcLevel): int =
  for v in 1..40:
    let t = VT[v-1][ord(ec)]
    let capBits = (t[2]*t[3] + t[5]*t[6]) * 8
    if capBits >= encodedBitCount(payload, mode, v): return v
  -1

proc buildCWs(payload: string; ver: int; ec: EcLevel; mode: QrMode): seq[uint8] =
  let t = VT[ver-1][ord(ec)]
  let cap = t[2]*t[3] + t[5]*t[6]
  var bits: seq[bool]
  proc push(v, n: int) =
    for i in countdown(n-1, 0): bits.add(((v shr i) and 1) == 1)
  case mode
  of mNumeric:
    push(1, 4)
    let cn = if ver <= 9: 10 elif ver <= 26: 12 else: 14
    push(payload.len, cn)
    var i = 0
    while i < payload.len:
      let rem = payload.len - i
      if rem >= 3:
        push((ord(payload[i])-48)*100 + (ord(payload[i+1])-48)*10 + (ord(
            payload[i+2])-48), 10)
        i += 3
      elif rem == 2:
        push((ord(payload[i])-48)*10 + (ord(payload[i+1])-48), 7)
        i += 2
      else:
        push(ord(payload[i])-48, 4); i += 1
  of mAlpha:
    push(2, 4)
    let cn = if ver <= 9: 9 elif ver <= 26: 11 else: 13
    push(payload.len, cn)
    var i = 0
    while i < payload.len:
      if i+1 < payload.len:
        push(alphaVal(payload[i])*45 + alphaVal(payload[i+1]), 11); i += 2
      else:
        push(alphaVal(payload[i]), 6); i += 1
  of mByte:
    push(4, 4)
    let cn = if ver <= 9: 8 else: 16
    push(payload.len, cn)
    for c in payload: push(int(c), 8)
  for _ in 0..<min(4, cap*8-bits.len): bits.add(false)
  while bits.len mod 8 != 0: bits.add(false)
  var i = 0
  while i < bits.len:
    var b = 0u8
    for j in 0..<8: b = b or (if bits[i+j]: 1u8 shl uint8(7-j) else: 0u8)
    result.add(b); i+=8
  const Pad = [0xECu8, 0x11u8]
  var pi = 0
  while result.len < cap: result.add(Pad[pi mod 2]); inc pi

proc interleave(data: seq[uint8]; ver: int; ec: EcLevel): seq[uint8] =
  let t = VT[ver-1][ord(ec)]
  let ecDeg = t[1]
  var blocks: seq[seq[uint8]]; var ecBlocks: seq[seq[uint8]]
  let gen = rsGen(ecDeg)
  var off = 0
  for g in 0..1:
    for _ in 0..<t[g*3+2]:
      let bl = data[off..<off+t[g*3+3]]
      blocks.add(bl); ecBlocks.add(rsRem(bl, gen))
      off+=t[g*3+3]
  let maxD = max(t[3], t[6])
  for i in 0..<maxD:
    for b in blocks:
      if i < b.len: result.add(b[i])
  for i in 0..<ecDeg:
    for b in ecBlocks: result.add(b[i])

# ── Public encoder ────────────────────────────────────────────────────────────

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a QR Code. Any byte string encodes; the version and
  ## error-correction level are chosen to fit.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  if payload.len == 0:
    return encodeError(Symbology, ekValidation, "QR Code payload must not be empty")
  if payload.len > 2953:
    return encodeError(Symbology, ekValidation, "QR Code payload too long")

  let ec = ecM
  let mode = bestMode(payload)
  let ver = selectVer(payload, mode, ec)
  if ver < 0:
    return encodeError(Symbology, ekValidation, "QR Code: payload too long")

  let raw = buildCWs(payload, ver, ec, mode)
  let cws = interleave(raw, ver, ec)
  let sz = 17+4*ver

  var best: QM; var bestScore = int.high
  for mk in 0..7:
    var m = newQM(sz)
    setupFn(m, ver); placeData(m, cws); applyMask(m, mk); applyFormat(m, ec, mk)
    let s = penalty(m)
    if s < bestScore: bestScore = s; best = m
  applyVersion(best, ver)

  var grid = newSeq[seq[bool]](sz)
  for r in 0..<sz:
    grid[r] = newSeq[bool](sz)
    for c in 0..<sz: grid[r][c] = best.d[r][c] == 1 or best.d[r][c] == 4

  encodeOk(Symbology, payload, BarcodeModules(grid: grid), BarcodeLayout())









