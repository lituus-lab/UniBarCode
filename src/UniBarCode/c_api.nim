# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## C ABI for UniBarCode. Built --app:staticlib/--app:lib --noMain --mm:arc
## -d:release. Keep in sync with include/UniBarCode.h; tests/c links the header
## against this lib.
##
## Conventions (see the header for the authoritative contract):
##   * Call `ubc_init()` once per process before anything else (it runs the
##     Nim runtime initialiser).
##   * Handles are opaque `void*`. The library owns them; free with the
##     matching `ubc_barcode_free` / `ubc_options_free` / `ubc_color_free`. NULL
##     is a no-op for every free.
##   * A handle carries no lock. One thread at a time may use or free a given
##     handle; a caller sharing one across threads serializes that itself.
##     Distinct handles are independent.
##   * `ubc_render_svg` / `ubc_render_png` allocate C-owned buffers; free them
##     with `ubc_buffer_free`.
##   * No Nim exception or Defect crosses the ABI: every entry point traps both
##     and maps them to a `UBC_*` code. Untrusted payloads and color inputs are
##     handled under `-d:release` (not `-d:danger`), so Nim's bounds checks stay
##     as defense-in-depth.
import ../UniBarCode ## facade: encode / RenderOptions / toSvg / toPng / types.
import UniColor ## Color / parseColor / color / tagSrgb — not re-exported by the
              ## UniBarCode facade (only its own common types are), so import
              ## UniColor directly (vgraph-clean: UniColor is an engine, not a
              ## layer).

when defined(danger):
  {.warning: "libUniBarCode built with -d:danger: bounds checks are off and the " &
    "Defect backstops at the ABI boundary cannot fire. Prefer -d:release for a " &
    "hardened encoder facing untrusted payloads and colors.".}

const UniBarCodeAbiVersion = 1

type
  BarcodeHandle = ref object
    res: EncodeResult
  OptionsHandle = ref object
    opts: RenderOptions
  ColorHandle = ref object
    color: Color

proc NimMain() {.importc.}

proc barcodeOf(p: pointer): BarcodeHandle {.inline.} = cast[BarcodeHandle](p)
proc optionsOf(p: pointer): OptionsHandle {.inline.} = cast[OptionsHandle](p)
proc colorOf(p: pointer): ColorHandle {.inline.} = cast[ColorHandle](p)

proc clampOpt(v: float32): float32 {.inline.} =
  ## Clamp an option scalar to a non-negative finite value: NaN, infinities and
  ## negatives map to 0. The never-raises ABI contract must not feed garbage
  ## into the renderer (a NaN module size or negative quiet zone would yield a
  ## broken image or a Defect).
  if v >= 0 and v <= float32.high: v else: 0'f32

# Status codes — keep in sync with `ubc_status` in UniBarCode.h.
const
  UBC_OK = cint(0)
  UBC_ERR_FORMAT = cint(2) # bad arg / nil handle / unparseable color / encode error
  UBC_ERR_UNSUP = cint(4) # unknown symbology
  UBC_ERR_MEM = cint(8)   # allocation failed

proc writeBytes(src: openArray[byte]; outData: ptr ptr uint8;
    outLen: ptr csize_t): cint =
  ## Copy `src` into a C-owned buffer; caller frees with `ubc_buffer_free`.
  if outData == nil or outLen == nil: return UBC_ERR_FORMAT
  outData[] = nil
  outLen[] = 0
  let n = src.len
  let buf = allocShared(n)
  if buf == nil: return UBC_ERR_MEM
  if n > 0: copyMem(buf, unsafeAddr src[0], n)
  outData[] = cast[ptr uint8](buf)
  outLen[] = csize_t(n)
  UBC_OK

proc writeString(s: string; outData: ptr ptr uint8;
    outLen: ptr csize_t): cint =
  ## Copy `s` plus a NUL terminator into a C-owned buffer. `*outLen` is the
  ## string length (excluding the NUL), so the buffer holds `*outLen + 1` bytes.
  ## Caller frees with `ubc_buffer_free`.
  if outData == nil or outLen == nil: return UBC_ERR_FORMAT
  outData[] = nil
  outLen[] = 0
  let n = s.len
  let buf = allocShared(n + 1)
  if buf == nil: return UBC_ERR_MEM
  if n > 0: copyMem(buf, unsafeAddr s[0], n)
  cast[ptr UncheckedArray[uint8]](buf)[n] = 0
  outData[] = cast[ptr uint8](buf)
  outLen[] = csize_t(n)
  UBC_OK

template swallowAbiFaults(body: untyped) =
  ## Run `body` so no CatchableError or Defect crosses the C boundary. Void
  ## mutators use this: the never-raises contract means a faulted mutation is
  ## dropped (the handle keeps its prior state) rather than escaping as a trap.
  try:
    body
  except CatchableError, Defect:
    discard

# Unmangled C symbols, C calling convention, exported from the shared lib.

# --noMain suppresses the generated entry point and with it every auto-init
# hook: neither the static nor the shared build emits a DllMain or an ELF
# constructor, so nothing initializes the Nim runtime. The first entry point
# then enters Nim code whose globals were never set up. The shared build was
# assumed to be covered by a loader hook it does not have -- allocShared then
# drew from an uninitialized allocator and every render call failed.
# Every --noMain task passes -d:ubcNoAutoInit; an ordinary executable linking
# this module must not, since its own main already ran NimMain.
when defined(ubcNoAutoInit):
  # A once primitive, not a plain flag: two threads reaching an entry point
  # together would both see the flag unset, both call NimMain, and the second
  # would enter Nim code the first had not finished initializing. The platform
  # primitives block the losers until the winner returns, which a flag cannot.
  #
  # C statics, not Nim globals: module initialization would reset a Nim one and
  # NimMain would run again. NimMain is declared here too — the generated
  # prototype comes after this section.
  {.emit: """/*VARSECTION*/
void NimMain(void);
#ifdef _WIN32
#  include <windows.h>
static INIT_ONCE ubc_runtime_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK ubc_runtime_init(PINIT_ONCE o, PVOID p, PVOID *c) {
  (void)o; (void)p; (void)c; NimMain(); return TRUE;
}
static void ubc_runtime_ensure(void) {
  InitOnceExecuteOnce(&ubc_runtime_once, ubc_runtime_init, NULL, NULL);
}
#else
#  include <pthread.h>
static pthread_once_t ubc_runtime_once = PTHREAD_ONCE_INIT;
static void ubc_runtime_init(void) { NimMain(); }
static void ubc_runtime_ensure(void) {
  pthread_once(&ubc_runtime_once, ubc_runtime_init);
}
#endif
""".}
  template ensureRuntime() =
    {.emit: "  ubc_runtime_ensure();".}
else:
  template ensureRuntime() = discard


{.push exportc, cdecl, dynlib.}

proc ubc_init(): cint =
  ## Idempotent NimMain bootstrap. Call once before any other ubc_* entry.
  ## Never raises.
  ##
  ## The work is `ensureRuntime`, which every entry point calls: a once
  ## primitive in a --noMain build, nothing when an ordinary main has already
  ## run NimMain. Calling NimMain again here ran it a second time -- the very
  ## thing the section above guards against -- and the flag that guarded it
  ## was a Nim global, which module initialization resets.
  ensureRuntime()
  UBC_OK

proc ubc_abi_version(): cint =
  ensureRuntime()
  cint(UniBarCodeAbiVersion)

proc ubc_version(): cstring =
  ## Static engine version string; do not free. Never raises.
  ensureRuntime()
  cstring(UniBarCodeVersion)

proc ubc_strerror(code: cint): cstring =
  ## Static message for an ubc_* status code.
  ensureRuntime()
  case code
  of UBC_OK: cstring"ok"
  of UBC_ERR_FORMAT: cstring"bad argument / nil handle / unparseable color / encode error"
  of UBC_ERR_UNSUP: cstring"unsupported symbology"
  of UBC_ERR_MEM: cstring"out of memory"
  else: cstring"unknown error"

# ------------------------------ barcode -------------------------------------

proc ubc_encode(symbology: cint; payload: cstring): pointer =
  ## Encode `payload` with `symbology` (a `BarcodeSymbology` ordinal, 0..14).
  ## NULL on a nil payload, unknown symbology, or encode error. The handle
  ## holds the `EncodeResult` even on a validation error — call
  ## `ubc_barcode_is_ok` to check. Never raises.
  ensureRuntime()
  if payload == nil: return nil
  if symbology < 0 or symbology > int(high(BarcodeSymbology)): return nil
  try:
    let res = encode(BarcodeSymbology(symbology), $payload)
    let h = BarcodeHandle(res: res)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ubc_barcode_is_ok(h: pointer): cint =
  ## 1 if the encode succeeded, 0 otherwise (nil handle -> 0).
  ensureRuntime()
  if h == nil: return 0
  if barcodeOf(h).res.isOk: 1 else: 0

proc ubc_barcode_symbology(h: pointer): cint =
  ## Symbology ordinal of the result (-1 on a nil handle).
  ensureRuntime()
  if h == nil: return -1
  cint(barcodeOf(h).res.symbology.ord)

proc ubc_barcode_width(h: pointer): cint =
  ## Module width of the barcode (1-D: bar count; 2-D: grid columns). 0 on a
  ## nil handle or failed encode.
  ensureRuntime()
  if h == nil: return 0
  let r = barcodeOf(h).res
  if not r.isOk: return 0
  if r.modules.is2D: cint(r.modules.gridWidth) else: cint(r.modules.width)

proc ubc_barcode_height(h: pointer): cint =
  ## Module height of the barcode (1-D: 1; 2-D: grid rows). 0 on a nil handle
  ## or failed encode.
  ensureRuntime()
  if h == nil: return 0
  let r = barcodeOf(h).res
  if not r.isOk: return 0
  if r.modules.is2D: cint(r.modules.gridHeight) else: 1

proc ubc_barcode_is_2d(h: pointer): cint =
  ## 1 if the symbology is 2-D, 0 otherwise (nil handle -> 0).
  ensureRuntime()
  if h == nil: return 0
  if barcodeOf(h).res.modules.is2D: 1 else: 0

proc ubc_barcode_error(h: pointer): cstring =
  ## Static message for the result's error kind ("" when ok or nil handle).
  ensureRuntime()
  if h == nil: return cstring""
  let r = barcodeOf(h).res
  if r.isOk: return cstring""
  case r.error.kind
  of ekValidation: cstring"validation error"
  of ekContractViolation: cstring"contract violation"
  of ekUnsupportedSymbology: cstring"unsupported symbology"
  of ekCorruptedImage: cstring"corrupted image"
  of ekScannerFailure: cstring"scanner failure"
  of ekInternal: cstring"internal error"
  else: cstring""

proc ubc_barcode_free(h: pointer) =
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: GC_unref(barcodeOf(h))

proc ubc_encode_composite(symbology: cint; payload: cstring;
    addon: cint; addonPayload: cstring): pointer =
  ## Encode a primary `payload` with an EAN-2/EAN-5 `addon` (a `UBC_SBC_EAN2` or
  ## `UBC_SBC_EAN5` ordinal) attached to its right. NULL on a nil
  ## payload/addon, out-of-range symbology, or encode error. The handle holds
  ## the result even on a validation error — call `ubc_barcode_is_ok`. Never
  ## raises.
  ensureRuntime()
  if payload == nil or addonPayload == nil: return nil
  if symbology < 0 or symbology > int(high(BarcodeSymbology)): return nil
  if addon < 0 or addon > int(high(BarcodeSymbology)): return nil
  try:
    let res = encodeComposite(BarcodeSymbology(symbology), $payload,
                              BarcodeSymbology(addon), $addonPayload)
    let h = BarcodeHandle(res: res)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

# ------------------------------ options -------------------------------------

proc ubc_options_new(): pointer =
  ## Default render options (black on white, module 2px, HRI on). NULL on
  ## allocation failure.
  ensureRuntime()
  try:
    let h = OptionsHandle(opts: defaultRenderOptions())
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ubc_options_set_module_size(h: pointer; v: float32) =
  ## Pixels per module (>= 0). No-op on a nil handle.
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: optionsOf(h).opts.moduleSize = clampOpt(v)

proc ubc_options_set_bar_height(h: pointer; v: float32) =
  ## Bar height in pixels (1-D). No-op on a nil handle.
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: optionsOf(h).opts.barHeight = clampOpt(v)

proc ubc_options_set_guard_height(h: pointer; v: float32) =
  ## Guard-bar height in pixels (EAN/UPC). No-op on a nil handle.
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: optionsOf(h).opts.guardHeight = clampOpt(v)

proc ubc_options_set_quiet_zone(h: pointer; v: float32) =
  ## Quiet-zone width in pixels. No-op on a nil handle.
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: optionsOf(h).opts.quietZone = clampOpt(v)

proc ubc_options_set_show_hri(h: pointer; v: cint) =
  ## Non-zero shows the HRI text strip (SVG, 1-D only). No-op on a nil handle.
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: optionsOf(h).opts.showHri = v != 0

proc ubc_options_set_foreground(h: pointer; c: pointer) =
  ## Foreground (bar) color from a `ubc_color*` handle. No-op on nil args.
  ensureRuntime()
  if h == nil or c == nil: return
  swallowAbiFaults: optionsOf(h).opts.foreground = colorOf(c).color

proc ubc_options_set_background(h: pointer; c: pointer) =
  ## Background color from a `ubc_color*` handle. No-op on nil args.
  ensureRuntime()
  if h == nil or c == nil: return
  swallowAbiFaults: optionsOf(h).opts.background = colorOf(c).color

proc ubc_options_free(h: pointer) =
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: GC_unref(optionsOf(h))

# ------------------------------- color --------------------------------------

proc ubc_color_parse(s: cstring): pointer =
  ## Parse a CSS Color 4 string (hex/rgb/oklch/...). NULL on a nil string or
  ## unparseable input. Never raises (parseColor returns a Result).
  ensureRuntime()
  if s == nil: return nil
  let r = parseColor($s)
  if not r.isOk: return nil
  try:
    let h = ColorHandle(color: r.get)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ubc_color_rgba(r, g, b, a: float32): pointer =
  ## An sRGB color from straight-alpha floats in `[0, 1]`. NULL on an
  ## out-of-gamut / non-finite input.
  ensureRuntime()
  let cr = color(tagSrgb, r, g, b, a)
  if not cr.isOk: return nil
  try:
    let h = ColorHandle(color: cr.get)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ubc_color_free(h: pointer) =
  ensureRuntime()
  if h == nil: return
  swallowAbiFaults: GC_unref(colorOf(h))

# ------------------------------- render -------------------------------------

proc ubc_render_svg(h: pointer; opts: pointer; outData: ptr ptr uint8;
    outLen: ptr csize_t): cint =
  ## Render the barcode to a standalone SVG string. On success allocates
  ## `*outData` as a NUL-terminated buffer (free with `ubc_buffer_free`) and
  ## sets `*outLen` to the string length (excluding the NUL). `opts` may be
  ## NULL (defaults are used).
  ensureRuntime()
  if outData == nil or outLen == nil: return UBC_ERR_FORMAT
  outData[] = nil
  outLen[] = 0
  if h == nil: return UBC_ERR_FORMAT
  try:
    let b = barcodeOf(h)
    if not b.res.isOk: return UBC_ERR_FORMAT
    let o = if opts == nil: defaultRenderOptions() else: optionsOf(opts).opts
    let s = toSvg(b.res, o)
    if s.len == 0: return UBC_ERR_FORMAT
    writeString(s, outData, outLen)
  except CatchableError, Defect:
    UBC_ERR_FORMAT

when not defined(ubcNoRaster):
  proc ubc_render_png(h: pointer; opts: pointer; outData: ptr ptr uint8;
      outLen: ptr csize_t): cint =
    ## Render the barcode to a PNG byte string. On success allocates `*outData`
    ## (free with `ubc_buffer_free`) and sets `*outLen`.
    ensureRuntime()
    if outData == nil or outLen == nil: return UBC_ERR_FORMAT
    outData[] = nil
    outLen[] = 0
    if h == nil: return UBC_ERR_FORMAT
    try:
      let b = barcodeOf(h)
      if not b.res.isOk: return UBC_ERR_FORMAT
      let o = if opts == nil: defaultRenderOptions() else: optionsOf(opts).opts
      let bytes = toPng(b.res, o)
      if bytes.len == 0: return UBC_ERR_FORMAT
      writeBytes(bytes, outData, outLen)
    except CatchableError, Defect:
      UBC_ERR_FORMAT

# ------------------------------- buffer -------------------------------------

proc ubc_buffer_free(p: pointer; len: csize_t) =
  ## Free a buffer returned by `ubc_render_svg` / `ubc_render_png`. NULL is a
  ## no-op. `len` is ignored (kept for symmetry with the allocator).
  ensureRuntime()
  if p == nil: return
  swallowAbiFaults: deallocShared(p)

{.pop.}









