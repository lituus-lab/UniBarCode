# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/symbology — Data Matrix ECC 200 encoder.
## ISO/IEC 16022:2006. ASCII encoding, GF(256) Reed-Solomon (poly 0x12D),
## Utah module placement (Annex F). Multi-region symbols use one global RS
## block whose codeword stream is placed on the combined mapping matrix, then
## split into nReg×nReg physical sub-regions (§5.8.2).

import std/sequtils
import ../common/types

const Symbology = sbDataMatrix

# ── GF(256), primitive polynomial 0x12D = x^8+x^5+x^3+x^2+1 ─────────────────
# Source: ISO/IEC 16022:2006 Section 5.6

var dmExp: array[512, uint8]
var dmLog: array[256, int]

block:
  var x = 1u8
  for i in 0 ..< 255:
    dmExp[i] = x
    dmLog[x] = i
    let hi = (x and 0x80u8) != 0u8
    x = (x shl 1u8) xor (if hi: 0x2Du8 else: 0u8)
  for i in 255 ..< 512: dmExp[i] = dmExp[i - 255]

proc dmMul(a, b: uint8): uint8 {.inline.} =
  if a == 0 or b == 0: 0u8 else: dmExp[(dmLog[a] + dmLog[b]) mod 255]

proc dmRem(data: seq[uint8]; nec: int): seq[uint8] =
  ## Reed-Solomon remainder over GF(256), generator roots alpha^1..alpha^nec.
  ## Source: ISO/IEC 16022:2006 Section 5.6.
  var gen = @[1u8]
  for i in 0 ..< nec:
    let fac = dmExp[i + 1]
    var nxt = newSeq[uint8](gen.len + 1)
    for j in 0 ..< gen.len:
      nxt[j] = nxt[j] xor dmMul(gen[j], fac)
      nxt[j+1] = nxt[j+1] xor gen[j]
    gen = nxt
  result = newSeq[uint8](nec)
  for b in data:
    let c = b xor result[0]
    for i in 0 ..< nec - 1:
      result[i] = result[i+1] xor dmMul(gen[nec-1-i], c)
    result[nec-1] = dmMul(gen[0], c)

# ── Symbol sizes (square ECC 200) — ISO/IEC 16022:2006 Table 2 ───────────────
# (sz, dSz, dCW, eCW): sz = total side, dSz = data-region side per sub-region,
# dCW = total data codewords, eCW = total error-correction codewords.
# Sub-regions per side: nReg = sz / (dSz + 2).

type SymSz = tuple[sz, dSz, dCW, eCW: int]

const Szs: array[24, SymSz] = [
  (10, 8, 3, 5), (12, 10, 5, 7), (14, 12, 8, 10), (16, 14, 12, 12),
  (18, 16, 18, 14), (20, 18, 22, 18), (22, 20, 30, 20), (24, 22, 36, 24),
  (26, 24, 44, 28), (32, 14, 62, 36), (36, 16, 86, 42), (40, 18, 114, 48),
  (44, 20, 144, 56), (48, 22, 174, 68), (52, 24, 204, 84), (64, 14, 280, 112),
  (72, 16, 368, 144), (80, 18, 456, 192), (88, 20, 576, 224), (96, 22, 696, 272),
  (104, 24, 816, 336), (120, 18, 1050, 408), (132, 20, 1304, 496), (144, 22,
      1558, 620),
]

proc selSz(n: int): int =
  for i, s in Szs:
    if s.dCW >= n: return i
  -1

# ── Rectangular symbol sizes (ISO/IEC 16022:2006 Table 7) ────────────────────

type RectSz = tuple[rows, cols, dSzRows, dSzCols, nRegCols, dCW, eCW: int]

const RectSzs: array[6, RectSz] = [
  (rows: 8, cols: 18, dSzRows: 6, dSzCols: 16, nRegCols: 1, dCW: 5, eCW: 7),
  (rows: 8, cols: 32, dSzRows: 6, dSzCols: 14, nRegCols: 2, dCW: 10, eCW: 11),
  (rows: 12, cols: 26, dSzRows: 10, dSzCols: 24, nRegCols: 1, dCW: 16, eCW: 14),
  (rows: 12, cols: 36, dSzRows: 10, dSzCols: 16, nRegCols: 2, dCW: 22, eCW: 18),
  (rows: 16, cols: 36, dSzRows: 14, dSzCols: 16, nRegCols: 2, dCW: 32, eCW: 24),
  (rows: 16, cols: 48, dSzRows: 14, dSzCols: 22, nRegCols: 2, dCW: 49, eCW: 28),
]

proc selSzRect(n: int): int =
  for i, s in RectSzs:
    if s.dCW >= n: return i
  -1

# ── ASCII encoding — ISO/IEC 16022:2006 Section 5.2.1 ────────────────────────
## Precondition: every byte of `s` is ASCII (< 128). The public encoder
## validates this before calling; upper-shift is out of scope.

proc encASCII(s: string): seq[uint8] =
  var i = 0
  while i < s.len:
    if i + 1 < s.len and s[i] in '0'..'9' and s[i+1] in '0'..'9':
      result.add(uint8((ord(s[i]) - ord('0')) * 10 +
                       (ord(s[i+1]) - ord('0')) + 130))
      i += 2
    else:
      result.add(uint8(ord(s[i]) + 1))
      inc i

# ── Utah module placement — ISO/IEC 16022:2006 Annex F ───────────────────────
# Operates on data-region grid g[0..nrow)[0..ncol) where
#   0 = unset, 2 = data dark, 3 = data light.
# Only writes to cells that are still 0 (unset) to avoid overwriting corners.

proc dmSetMod(g: var seq[seq[uint8]]; nrow, ncol, r, c: int;
    dark: bool) {.inline.} =
  ## Write one module, applying boundary-wrap per ISO 16022 Section 5.8.1.
  var row = r; var col = c
  if row < 0:
    row += nrow
    col += 4 - ((nrow + 4) mod 8)
  if col < 0:
    col += ncol
    row += 4 - ((ncol + 4) mod 8)
  if row >= nrow: row -= nrow
  if col >= ncol: col -= ncol
  if g[row][col] == 0:
    g[row][col] = if dark: 2u8 else: 3u8

proc dmUtah(g: var seq[seq[uint8]]; nrow, ncol, row, col: int; cw: uint8) =
  ## Place one 8-bit codeword in the Utah shape (Figure F.1, ISO 16022 Annex F).
  ## Bit 7 (MSB) → top-left offset, bit 0 (LSB) → bottom-right.
  dmSetMod(g, nrow, ncol, row-2, col-2, (cw and 0x80u8) != 0)
  dmSetMod(g, nrow, ncol, row-2, col-1, (cw and 0x40u8) != 0)
  dmSetMod(g, nrow, ncol, row-1, col-2, (cw and 0x20u8) != 0)
  dmSetMod(g, nrow, ncol, row-1, col-1, (cw and 0x10u8) != 0)
  dmSetMod(g, nrow, ncol, row-1, col, (cw and 0x08u8) != 0)
  dmSetMod(g, nrow, ncol, row, col-2, (cw and 0x04u8) != 0)
  dmSetMod(g, nrow, ncol, row, col-1, (cw and 0x02u8) != 0)
  dmSetMod(g, nrow, ncol, row, col, (cw and 0x01u8) != 0)

proc dmCorner1(g: var seq[seq[uint8]]; nrow, ncol: int; cw: uint8) =
  ## Corner pattern 1 — ISO/IEC 16022:2006 Annex F.
  dmSetMod(g, nrow, ncol, nrow-1, 0, (cw and 0x80u8) != 0)
  dmSetMod(g, nrow, ncol, nrow-1, 1, (cw and 0x40u8) != 0)
  dmSetMod(g, nrow, ncol, nrow-1, 2, (cw and 0x20u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-2, (cw and 0x10u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-1, (cw and 0x08u8) != 0)
  dmSetMod(g, nrow, ncol, 1, ncol-1, (cw and 0x04u8) != 0)
  dmSetMod(g, nrow, ncol, 2, ncol-1, (cw and 0x02u8) != 0)
  dmSetMod(g, nrow, ncol, 3, ncol-1, (cw and 0x01u8) != 0)

proc dmCorner2(g: var seq[seq[uint8]]; nrow, ncol: int; cw: uint8) =
  ## Corner pattern 2 — ISO/IEC 16022:2006 Annex F.
  dmSetMod(g, nrow, ncol, nrow-3, 0, (cw and 0x80u8) != 0)
  dmSetMod(g, nrow, ncol, nrow-2, 0, (cw and 0x40u8) != 0)
  dmSetMod(g, nrow, ncol, nrow-1, 0, (cw and 0x20u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-4, (cw and 0x10u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-3, (cw and 0x08u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-2, (cw and 0x04u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-1, (cw and 0x02u8) != 0)
  dmSetMod(g, nrow, ncol, 1, ncol-1, (cw and 0x01u8) != 0)

proc dmCorner3(g: var seq[seq[uint8]]; nrow, ncol: int; cw: uint8) =
  ## Corner pattern 3 — ISO/IEC 16022:2006 Annex F.
  dmSetMod(g, nrow, ncol, nrow-3, 0, (cw and 0x80u8) != 0)
  dmSetMod(g, nrow, ncol, nrow-2, 0, (cw and 0x40u8) != 0)
  dmSetMod(g, nrow, ncol, nrow-1, 0, (cw and 0x20u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-2, (cw and 0x10u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-1, (cw and 0x08u8) != 0)
  dmSetMod(g, nrow, ncol, 1, ncol-1, (cw and 0x04u8) != 0)
  dmSetMod(g, nrow, ncol, 2, ncol-1, (cw and 0x02u8) != 0)
  dmSetMod(g, nrow, ncol, 3, ncol-1, (cw and 0x01u8) != 0)

proc dmCorner4(g: var seq[seq[uint8]]; nrow, ncol: int; cw: uint8) =
  ## Corner pattern 4 — ISO/IEC 16022:2006 Annex F.
  dmSetMod(g, nrow, ncol, nrow-1, 0, (cw and 0x80u8) != 0)
  dmSetMod(g, nrow, ncol, nrow-1, ncol-1, (cw and 0x40u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-3, (cw and 0x20u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-2, (cw and 0x10u8) != 0)
  dmSetMod(g, nrow, ncol, 0, ncol-1, (cw and 0x08u8) != 0)
  dmSetMod(g, nrow, ncol, 1, ncol-3, (cw and 0x04u8) != 0)
  dmSetMod(g, nrow, ncol, 1, ncol-2, (cw and 0x02u8) != 0)
  dmSetMod(g, nrow, ncol, 1, ncol-1, (cw and 0x01u8) != 0)

proc placeRegion(g: var seq[seq[uint8]]; nrow, ncol: int; cws: seq[uint8]) =
  ## Fill a nrow×ncol data-region using the Utah diagonal sweep.
  ## Source: ISO/IEC 16022:2006 Annex F, Algorithm F.1.
  var ci = 0
  var row = 4; var col = 0

  while row < nrow or col < ncol:
    if row == nrow and col == 0:
      if ci < cws.len: dmCorner1(g, nrow, ncol, cws[ci]); inc ci
    if row == nrow - 2 and col == 0 and ncol mod 4 != 0:
      if ci < cws.len: dmCorner2(g, nrow, ncol, cws[ci]); inc ci
    if row == nrow - 2 and col == 0 and ncol mod 8 == 4:
      if ci < cws.len: dmCorner3(g, nrow, ncol, cws[ci]); inc ci
    if row == nrow + 4 and col == 2 and ncol mod 8 == 0:
      if ci < cws.len: dmCorner4(g, nrow, ncol, cws[ci]); inc ci

    # Sweep up-right (do-while: body executes before condition is tested)
    while true:
      if row < nrow and col >= 0 and g[row][col] == 0:
        if ci < cws.len: dmUtah(g, nrow, ncol, row, col, cws[ci]); inc ci
      row -= 2; col += 2
      if not (row >= 0 and col < ncol): break
    row += 1; col += 3

    # Sweep down-left (do-while)
    while true:
      if row >= 0 and col < ncol and g[row][col] == 0:
        if ci < cws.len: dmUtah(g, nrow, ncol, row, col, cws[ci]); inc ci
      row += 2; col -= 2
      if not (row < nrow and col >= 0): break
    row += 3; col += 1

  # Forced padding corner — ISO/IEC 16022:2006 Section 5.8.1
  if g[nrow-1][ncol-1] == 0: g[nrow-1][ncol-1] = 2u8 # dark
  if g[nrow-2][ncol-2] == 0: g[nrow-2][ncol-2] = 3u8 # light

# ── Symbol grid assembly ──────────────────────────────────────────────────────

proc buildGrid(s: SymSz; dataCws: seq[uint8]): seq[seq[bool]] =
  ## Build the complete symbol matrix from data codewords.
  ## ISO 16022:2006 §5.8.2: one global RS block; Utah placement runs on the
  ## combined mapping matrix (nReg*dSz × nReg*dSz), then each dSz×dSz quadrant
  ## is copied to its physical sub-region. For single-region symbols nReg=1.
  let nReg = s.sz div (s.dSz + 2)
  let mapSz = nReg * s.dSz
  var g = newSeqWith(s.sz, newSeq[int](s.sz)) # 0=light, 1=dark

  for ry in 0 ..< nReg:
    for rx in 0 ..< nReg:
      let rs = ry * (s.dSz + 2)
      let cs = rx * (s.dSz + 2)
      for i in 0 ..< s.dSz + 2:
        g[rs + i][cs + s.dSz + 1] = if i mod 2 == 1: 1 else: 0 # right timing
      for i in 0 ..< s.dSz + 2:
        g[rs][cs + i] = if i mod 2 == 0: 1 else: 0 # top timing
      for i in 0 ..< s.dSz + 2:
        g[rs + s.dSz + 1][cs + i] = 1 # bottom L-finder
      for i in 0 ..< s.dSz + 2:
        g[rs + i][cs] = 1 # left L-finder

  let ec = dmRem(dataCws, s.eCW)
  var mapGrid = newSeqWith(mapSz, newSeq[uint8](mapSz))
  placeRegion(mapGrid, mapSz, mapSz, dataCws & ec)

  for mr in 0 ..< mapSz:
    for mc in 0 ..< mapSz:
      let ry = mr div s.dSz
      let rx = mc div s.dSz
      let pr = ry * (s.dSz + 2) + 1 + mr mod s.dSz
      let pc = rx * (s.dSz + 2) + 1 + mc mod s.dSz
      g[pr][pc] = if mapGrid[mr][mc] == 2: 1 else: 0

  result = newSeq[seq[bool]](s.sz)
  for r in 0 ..< s.sz:
    result[r] = newSeq[bool](s.sz)
    for c in 0 ..< s.sz:
      result[r][c] = g[r][c] == 1

# ── Rectangular grid assembly ─────────────────────────────────────────────────

proc buildGridRect(s: RectSz; dataCws: seq[uint8]): seq[seq[bool]] =
  ## Build the complete symbol matrix for a rectangular ECC 200 symbol.
  ## One global RS block; Utah placement on the combined
  ## mapRows x (nRegCols x dSzCols) matrix; result mapped to nRegCols physical
  ## regions laid out horizontally (ISO 16022:2006 Table 7).
  let mapRows = s.dSzRows
  let mapCols = s.nRegCols * s.dSzCols
  var g = newSeqWith(s.rows, newSeq[int](s.cols))       # 0=light, 1=dark

  for rx in 0 ..< s.nRegCols:
    let cs = rx * (s.dSzCols + 2)
    for i in 0 ..< s.dSzRows + 2: # left L-finder: all dark
      g[i][cs] = 1
    for i in 0 ..< s.dSzCols + 2: # bottom L-finder: all dark
      g[s.dSzRows + 1][cs + i] = 1
    for i in 0 ..< s.dSzCols + 2: # top timing: dark at even positions
      g[0][cs + i] = if i mod 2 == 0: 1 else: 0
    for i in 0 ..< s.dSzRows + 2: # right timing: dark at odd positions
      g[i][cs + s.dSzCols + 1] = if i mod 2 == 1: 1 else: 0

  let ec = dmRem(dataCws, s.eCW)
  var mapGrid = newSeqWith(mapRows, newSeq[uint8](mapCols))
  placeRegion(mapGrid, mapRows, mapCols, dataCws & ec)

  for mr in 0 ..< mapRows:
    for mc in 0 ..< mapCols:
      let rx = mc div s.dSzCols
      let pr = 1 + mr
      let pc = rx * (s.dSzCols + 2) + 1 + mc mod s.dSzCols
      g[pr][pc] = if mapGrid[mr][mc] == 2: 1 else: 0

  result = newSeq[seq[bool]](s.rows)
  for r in 0 ..< s.rows:
    result[r] = newSeq[bool](s.cols)
    for c in 0 ..< s.cols:
      result[r][c] = g[r][c] == 1

# ── Public encoder ────────────────────────────────────────────────────────────

proc encode*(payload: string): EncodeResult =
  ## Encode `payload` as a Data Matrix symbol. Any byte string encodes; the
  ## symbol size is chosen to fit.
  ## Returns the modules and, on refusal, the reason -- it does not raise.
  if payload.len == 0:
    return encodeError(Symbology, ekValidation, "Data Matrix payload must not be empty")
  for c in payload:
    if ord(c) >= 128:
      return encodeError(Symbology, ekValidation,
        "Data Matrix ASCII mode: non-ASCII byte (ord=" & $ord(c) & ") not supported")

  var cws = encASCII(payload)
  let si = selSz(cws.len)
  if si < 0:
    return encodeError(Symbology, ekValidation, "Data Matrix: payload too long")

  let sz = Szs[si]

  # ECC 200 uses one Reed-Solomon block over GF(256), which holds at most 255
  # codewords. The 52x52 symbol and larger need the multi-block interleave
  # (ISO/IEC 16022:2006 §5.6), which is not implemented here — reject rather
  # than emit a structurally invalid symbol.
  if sz.dCW + sz.eCW > 255:
    return encodeError(Symbology, ekValidation,
      "Data Matrix: payload too long (52x52+ needs multi-block Reed-Solomon, unsupported)")

  # Pad to dCW: first pad = 129, subsequent pads per the 253-state algorithm
  # (ISO/IEC 16022:2006 §5.2.3): R = ((149*P) mod 253)+1, pad = 129+R, wrapping
  # past 254 by subtracting 254. P is the codeword position (count + 1).
  if cws.len < sz.dCW:
    cws.add(129u8)
  while cws.len < sz.dCW:
    let i = cws.len
    let r = ((149 * (i + 1)) mod 253) + 1
    let pad = 129 + r
    cws.add(uint8(if pad <= 254: pad else: pad - 254))
  cws = cws[0 ..< sz.dCW]

  let grid = buildGrid(sz, cws)
  encodeOk(Symbology, payload, BarcodeModules(grid: grid), BarcodeLayout())

proc encodeRect*(payload: string): EncodeResult =
  ## Encode into the smallest rectangular ECC 200 symbol (8x18 to 16x48).
  ## Use encode() for square symbols; this selects rectangular only.
  if payload.len == 0:
    return encodeError(Symbology, ekValidation, "Data Matrix payload must not be empty")
  for c in payload:
    if ord(c) >= 128:
      return encodeError(Symbology, ekValidation,
        "Data Matrix ASCII mode: non-ASCII byte (ord=" & $ord(c) & ") not supported")

  var cws = encASCII(payload)
  let si = selSzRect(cws.len)
  if si < 0:
    return encodeError(Symbology, ekValidation,
      "Data Matrix: payload too large for rectangular symbols (max 16x48, 49 data CW)")

  let sz = RectSzs[si]
  if cws.len < sz.dCW:
    cws.add(129u8)
  while cws.len < sz.dCW:
    let i = cws.len
    let r = ((149 * (i + 1)) mod 253) + 1
    let pad = 129 + r
    cws.add(uint8(if pad <= 254: pad else: pad - 254))
  cws = cws[0 ..< sz.dCW]

  let grid = buildGridRect(sz, cws)
  encodeOk(Symbology, payload, BarcodeModules(grid: grid), BarcodeLayout())









