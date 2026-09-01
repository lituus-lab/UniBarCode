# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/common — symbology-agnostic domain model.
##
## The platform-wide types every encoder, renderer and binding consumes.
## Business logic lives in the encoders; this module only describes data,
## ownership and lifecycle. All types here are value types (`object`/`enum`/
## `seq`): they own their data and copy by Nim's value semantics, so no manual
## lifecycle management is needed at the Nim layer. The C ABI layer adds the
## explicit ownership rules.
import contracts

type
  BarcodeSymbology* = enum
    ## Supported symbologies. Stable identifiers; the ordinals are frozen and
    ## mirror the `UBC_*` constants in include/UniBarCode.h.
    sbEan13 = "EAN-13"
    sbEan8 = "EAN-8"
    sbUpcA = "UPC-A"
    sbCode39 = "Code39"
    sbCode128 = "Code128"
    sbItf = "ITF"
    sbQrCode = "QR Code"
    sbDataMatrix = "Data Matrix"
    sbPdf417 = "PDF417"
    sbAztec = "Aztec"
    sbUpcE = "UPC-E"
    sbEan2 = "EAN-2"
    sbEan5 = "EAN-5"
    sbMicroQr = "Micro QR"
    sbGs1128 = "GS1-128"

  ErrorKind* = enum
    ## Classification of every failure the platform can report. No silent
    ## failures: each fallible operation returns one of these on the error path.
    ekNone = "none"
    ekValidation = "validation" ## input failed a precondition
    ekContractViolation = "contract" ## an invariant/postcondition broke
    ekUnsupportedSymbology = "unsupported_symbology"
    ekCorruptedImage = "corrupted_image"
    ekScannerFailure = "scanner_failure"
    ekInternal = "internal" ## unexpected, treated as fatal

  BarcodeError* = object
    ## A recoverable, inspectable error value. `kind == ekNone` never appears
    ## inside a populated error; absence of error is modelled by the result type.
    kind*: ErrorKind
    message*: string ## human-readable, deterministic

  BarcodeData* = object
    ## Logical payload to encode, independent of any rendering.
    symbology*: BarcodeSymbology
    payload*: string ## raw input (e.g. "978020137962")

  BarcodeModules* = object
    ## A 1-D barcode rendered as a row of modules (bars/spaces), or a 2-D matrix.
    ## `bars[i] == true` means bar (dark), `false` means space (light).
    ## `width == bars.len`; each element is exactly one module wide.
    ## For 2-D, `grid[row][col]` is dark when true.
    bars*: seq[bool]
    grid*: seq[seq[bool]]

  GlyphPlacement* = object
    ## One run of human-readable text and where to center it horizontally,
    ## expressed in module units along the symbol's X axis. `moduleCenter` may
    ## be negative to place a glyph in the left quiet zone (e.g. EAN-13's first
    ## digit). Rendering-agnostic: the renderer maps module units to pixels.
    text*: string
    moduleCenter*: float

  BarcodeSupplement* = object
    ## A 1-D add-on (EAN-2 or EAN-5) attached to a primary EAN/UPC symbol,
    ## rendered to its right with a small gap. Add-ons carry no supplements of
    ## their own (one level only), so this is not recursive.
    symbology*: BarcodeSymbology
    modules*: BarcodeModules
    layout*: BarcodeLayout

  BarcodeLayout* = object
    ## Symbology-specific presentation metadata, computed by the encoder so the
    ## renderer stays symbology-agnostic.
    ## `guardModules`: module indices whose bars are drawn extended (longer) —
    ## EAN/UPC start, center and end guards.
    ## `hri`: human-readable interpretation glyph placements.
    ## `supplements`: add-on symbols (EAN-2/EAN-5) rendered to the right of the
    ## primary; empty for stand-alone symbols.
    guardModules*: seq[int]
    hri*: seq[GlyphPlacement]
    supplements*: seq[BarcodeSupplement]

  EncodeResult* = object
    ## Result of an encode operation. Exactly one of `ok`/`error` is meaningful,
    ## discriminated by `isOk`.
    isOk*: bool
    symbology*: BarcodeSymbology
    normalizedPayload*: string ## payload after validation (checksum appended)
    modules*: BarcodeModules
    layout*: BarcodeLayout ## presentation metadata (guards, HRI)
    error*: BarcodeError

  ValidationResult* = object
    isValid*: bool
    error*: BarcodeError

func width*(m: BarcodeModules): int {.inline.} =
  ## Number of modules in the rendered row. Postcondition: `result >= 0`.
  m.bars.len

func ok*(e: BarcodeError): bool {.inline.} =
  e.kind == ekNone

proc newError*(kind: ErrorKind, message: string): BarcodeError {.contractual.} =
  ## Construct a populated error. Precondition: `kind != ekNone`.
  require:
    kind != ekNone
  body:
    BarcodeError(kind: kind, message: message)

proc encodeError*(symbology: BarcodeSymbology, kind: ErrorKind,
                  message: string): EncodeResult =
  EncodeResult(isOk: false, symbology: symbology,
               error: newError(kind, message))

proc encodeOk*(symbology: BarcodeSymbology, normalizedPayload: string,
               modules: BarcodeModules,
               layout: BarcodeLayout = BarcodeLayout()): EncodeResult =
  EncodeResult(isOk: true, symbology: symbology,
               normalizedPayload: normalizedPayload, modules: modules,
               layout: layout, error: BarcodeError(kind: ekNone))

func toBitString*(m: BarcodeModules): string =
  ## Render modules as a '0'/'1' string ('1' == bar). Useful for golden tests
  ## and debugging. Postcondition: `result.len == m.width`.
  result = newStringOfCap(m.bars.len)
  for b in m.bars:
    result.add(if b: '1' else: '0')

func toGridBitString*(m: BarcodeModules): string =
  ## Render a 2-D grid row-major as a '0'/'1' string ('1' == dark). For golden
  ## tests of matrix symbologies. Postcondition: `result.len == gridWidth * gridHeight`.
  let cols = if m.grid.len > 0: m.grid[0].len else: 0
  result = newStringOfCap(m.grid.len * cols)
  for row in m.grid:
    for b in row:
      result.add(if b: '1' else: '0')

func is2D*(m: BarcodeModules): bool {.inline.} =
  ## True when the barcode is a 2-D matrix (grid non-empty).
  m.grid.len > 0

func gridHeight*(m: BarcodeModules): int {.inline.} =
  ## Rows in a 2-D symbol; 0 for a linear one, whose bars live in `modules`
  ## rather than `grid`.
  m.grid.len
func gridWidth*(m: BarcodeModules): int {.inline.} =
  ## Columns in a 2-D symbol, read from the first row: every row of a matrix
  ## symbology has the same length. 0 for a linear one.
  if m.grid.len > 0: m.grid[0].len else: 0









