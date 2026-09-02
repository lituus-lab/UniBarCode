# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## unibarcode — multi-symbology barcode CLI.
##
##   unibarcode <symbology> <payload> [options]
##
## Symbology (case-insensitive): ean13, ean8, upca, upce, ean2, ean5, code39,
## code128, gs1128 (gs1-128), itf, qr (qrcode), microqr (micro-qr), datamatrix,
## pdf417, aztec.
##
## Options:
##   --png PATH           write a PNG render (default: out.png)
##   --svg PATH           write an SVG render (default: out.svg)
##   --no-png             skip the PNG render
##   --no-svg             skip the SVG render
##   --addon PAYLOAD      attach an EAN-2 (2 digits) or EAN-5 (5 digits) add-on
##   --module-size N      pixels per module (default 2)
##   --bar-height N       1-D bar height in pixels (default 80)
##   --guard-height N     1-D guard-bar height (default 90)
##   --quiet-zone N       quiet zone in pixels (default 22)
##   --no-hri             suppress the human-readable text (SVG, 1-D)
##   --fg COLOR           foreground color, CSS string (default #000000)
##   --bg COLOR           background color (default #ffffff; "" for none)
import std/[os, strutils, strformat, math]
import UniBarCode
import UniColor

proc die(msg: string) {.noreturn.} =
  stderr.writeLine "error: " & msg
  quit(1)

const UsageText = """usage:
  unibarcode <symbology> <payload> [options]
symbology: ean13 ean8 upca upce ean2 ean5 code39 code128 gs1128 itf qr microqr datamatrix pdf417 aztec
options:   --png PATH --svg PATH --no-png --no-svg --addon PAYLOAD
           --module-size N --bar-height N --guard-height N --quiet-zone N
           --no-hri --fg COLOR --bg COLOR"""

proc usage() {.noreturn.} =
  ## Asked for. Goes to stdout and exits 0: `--help` is a request that
  ## succeeded, not a misuse.
  echo UsageText
  quit(0)

proc usageError() {.noreturn.} =
  ## Not asked for. Goes to stderr and exits non-zero, so a caller can tell
  ## the two apart.
  stderr.writeLine UsageText
  quit(1)

proc parseSymbology(s: string): BarcodeSymbology =
  case s.toLowerAscii()
  of "ean13": sbEan13
  of "ean8": sbEan8
  of "upca", "upc-a": sbUpcA
  of "upce", "upc-e": sbUpcE
  of "ean2", "ean-2": sbEan2
  of "ean5", "ean-5": sbEan5
  of "code39", "code-39": sbCode39
  of "code128", "code-128": sbCode128
  of "gs1128", "gs1-128": sbGs1128
  of "itf": sbItf
  of "qr", "qrcode", "qr-code": sbQrCode
  of "microqr", "micro-qr": sbMicroQr
  of "datamatrix", "data-matrix": sbDataMatrix
  of "pdf417", "pdf-417": sbPdf417
  of "aztec": sbAztec
  else: die("unknown symbology: " & s)

proc parseFloatArg(name, raw: string): float32 =
  try: result = parseFloat(raw).float32
  except ValueError: die(name & " must be a number: " & raw)
  if result.classify in {fcNan, fcInf, fcNegInf}:
    die(name & " must be a finite number: " & raw)

proc optArg(args: seq[string]; i: var int; name: string): string =
  ## Pull the value for a `--name value` pair, or the `=value` suffix.
  let a = args[i]
  if a.startsWith("--" & name & "="):
    result = a[name.len + 3 ..< a.len]
  else:
    if i + 1 >= args.len: die("--" & name & " needs a value")
    result = args[i + 1]; i += 1

proc main() =
  let args = commandLineParams()
  # Before the arity check: `--help` on its own is one argument, and asking for
  # help is not a misuse to be reported as one.
  for a in args:
    if a == "--help" or a == "-h": usage()
  if args.len < 2: usageError()
  let sym = parseSymbology(args[0])
  let payload = args[1]

  var pngOut = "out.png"
  var svgOut = "out.svg"
  var doPng = true
  var doSvg = true
  var opts = defaultRenderOptions()
  var bgNone = false
  var addonPayload = ""

  var i = 2
  while i < args.len:
    let a = args[i]
    if a.startsWith("--png=") or a == "--png":
      pngOut = optArg(args, i, "png")
    elif a.startsWith("--svg=") or a == "--svg":
      svgOut = optArg(args, i, "svg")
    elif a == "--no-png": doPng = false
    elif a == "--no-svg": doSvg = false
    elif a.startsWith("--addon=") or a == "--addon":
      addonPayload = optArg(args, i, "addon")
    elif a.startsWith("--module-size=") or a == "--module-size":
      opts.moduleSize = parseFloatArg("--module-size", optArg(args, i,
          "module-size"))
    elif a.startsWith("--bar-height=") or a == "--bar-height":
      opts.barHeight = parseFloatArg("--bar-height", optArg(args, i, "bar-height"))
    elif a.startsWith("--guard-height=") or a == "--guard-height":
      opts.guardHeight = parseFloatArg("--guard-height", optArg(args, i,
          "guard-height"))
    elif a.startsWith("--quiet-zone=") or a == "--quiet-zone":
      opts.quietZone = parseFloatArg("--quiet-zone", optArg(args, i, "quiet-zone"))
    elif a == "--no-hri": opts.showHri = false
    elif a.startsWith("--fg=") or a == "--fg":
      let r = parseColor(optArg(args, i, "fg"))
      if not r.isOk: die("bad --fg color")
      opts.foreground = r.get
    elif a.startsWith("--bg=") or a == "--bg":
      let raw = optArg(args, i, "bg")
      if raw == "":
        bgNone = true
      else:
        let r = parseColor(raw)
        if not r.isOk: die("bad --bg color")
        opts.background = r.get
    elif a == "--help" or a == "-h": usage()
    else: die("unknown option: " & a)
    i += 1

  if opts.moduleSize <= 0: die("--module-size must be positive")
  if opts.barHeight <= 0: die("--bar-height must be positive")
  if opts.guardHeight < 0: die("--guard-height must not be negative")
  if opts.quietZone < 0: die("--quiet-zone must not be negative")

  let res = if addonPayload == "":
    encode(sym, payload)
  else:
    let addonSym = case addonPayload.len
      of 2: sbEan2
      of 5: sbEan5
      else: die("--addon must be 2 or 5 digits, got " & $addonPayload.len)
    encodeComposite(sym, payload, addonSym, addonPayload)
  if not res.isOk:
    die("encode failed: " & $res.error.kind & " — " & res.error.message)

  if bgNone:
    let transparent = color(tagSrgb, 0'f32, 0'f32, 0'f32, 0'f32)
    if transparent.isOk: opts.background = transparent.get

  if doSvg and doPng and svgOut == pngOut:
    die("--svg and --png must write to different paths")

  if doSvg:
    writeFile(svgOut, toSvg(res, opts))
  if doPng:
    let png = toPng(res, opts)
    # `png` is a seq[byte] and writeFile takes one: casting it to a string
    # reinterprets the memory of one type as another for no gain.
    writeFile(pngOut, png)

  let kind = if res.modules.is2D: "2D" else: "1D"
  let dims = if res.modules.is2D:
    &"{res.modules.gridWidth}x{res.modules.gridHeight}"
  else:
    $res.modules.width
  echo &"encoded {sym} ({kind}) -> {dims}"
  if doSvg: echo &"  wrote {svgOut}"
  if doPng: echo &"  wrote {pngOut}"

when isMainModule: main()
