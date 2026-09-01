// UniBarCode JS wrapper over the ubc_* C ABI (WebAssembly build).
//
// Load: const { UniBarCode, Symbology } = require('./unibarcode-api.js');
//       const ubc = await UniBarCode.create('./unibarcode.wasm');
//       const bc = ubc.encode(Symbology.EAN13, '978020137962');
//       if (bc.isOk) { const svg = bc.renderSvg(); bc.free(); }
//
// The C ABI is handle-based and never raises: every entry maps a fault to a
// UBC_* status code. This wrapper turns those codes into JS values/throws.
// Symbology ordinals are frozen 0..14 and mirror UBC_SBC_* in UniBarCode.h.
/* global UniBarCodeWasm, module, define */

const SYMBOLOGY = Object.freeze({
  EAN13: 0, EAN8: 1, UPCA: 2, CODE39: 3, CODE128: 4, ITF: 5,
  QR: 6, DATAMATRIX: 7, PDF417: 8, AZTEC: 9,
  UPCE: 10, EAN2: 11, EAN5: 12, MICROQR: 13, GS1128: 14,
});

const SYMBOLOGY_NAME = Object.freeze({
  0: 'ean13', 1: 'ean8', 2: 'upca', 3: 'code39', 4: 'code128',
  5: 'itf', 6: 'qr', 7: 'datamatrix', 8: 'pdf417', 9: 'aztec',
  10: 'upce', 11: 'ean2', 12: 'ean5', 13: 'microqr', 14: 'gs1128',
});

function resolveSymbology(s) {
  if (typeof s === 'number') return s;
  if (typeof s === 'string') {
    const up = s.toUpperCase();
    if (up in SYMBOLOGY) return SYMBOLOGY[up];
  }
  throw new TypeError(`unknown symbology: ${s}`);
}

// Encode options mapped onto ubc_options_* setters.
const DEFAULT_OPTIONS = {
  moduleSize: 2, barHeight: 80, guardHeight: 90, quietZone: 10,
  showHri: true, foreground: '#000000', background: '#ffffff',
};

function utf8ByteLength(s) {
  if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(s).length;
  // Fallback: worst-case estimate (1 byte per char for BMP ascii-ish input).
  return Buffer ? Buffer.byteLength(s, 'utf8') : s.length * 4;
}

function cstr(mod, s) {
  const len = utf8ByteLength(s) + 1;
  const buf = mod._malloc(len);
  mod.stringToUTF8(s, buf, len);
  return buf;
}

class Color {
  constructor(mod, ptr) { this._mod = mod; this._ptr = ptr; }
  static parse(mod, s) {
    const buf = cstr(mod, s);
    try {
      const ptr = mod._ubc_color_parse(buf);
      if (!ptr) throw new Error(`unparseable color: ${s}`);
      return new Color(mod, ptr);
    } finally { mod._free(buf); }
  }
  free() { if (this._ptr) { this._mod._ubc_color_free(this._ptr); this._ptr = 0; } }
}

class Options {
  constructor(mod, ptr) { this._mod = mod; this._ptr = ptr; }
  static create(mod, opts = {}) {
    const o = { ...DEFAULT_OPTIONS, ...opts };
    const ptr = mod._ubc_options_new();
    if (!ptr) throw new Error('ubc_options_new returned NULL');
    mod._ubc_options_set_module_size(ptr, o.moduleSize);
    mod._ubc_options_set_bar_height(ptr, o.barHeight);
    mod._ubc_options_set_guard_height(ptr, o.guardHeight);
    mod._ubc_options_set_quiet_zone(ptr, o.quietZone);
    mod._ubc_options_set_show_hri(ptr, o.showHri ? 1 : 0);
    let fg = null, bg = null;
    try {
      fg = Color.parse(mod, o.foreground); mod._ubc_options_set_foreground(ptr, fg._ptr);
      bg = Color.parse(mod, o.background); mod._ubc_options_set_background(ptr, bg._ptr);
    } finally { if (fg) fg.free(); if (bg) bg.free(); }
    return new Options(mod, ptr);
  }
  free() { if (this._ptr) { this._mod._ubc_options_free(this._ptr); this._ptr = 0; } }
}

class Barcode {
  constructor(mod, ptr) { this._mod = mod; this._ptr = ptr; }
  get isOk() { return this._mod._ubc_barcode_is_ok(this._ptr) !== 0; }
  get symbology() { return this._mod._ubc_barcode_symbology(this._ptr); }
  get width() { return this._mod._ubc_barcode_width(this._ptr); }
  get height() { return this._mod._ubc_barcode_height(this._ptr); }
  get is2d() { return this._mod._ubc_barcode_is_2d(this._ptr) !== 0; }
  get error() {
    const p = this._mod._ubc_barcode_error(this._ptr);
    return p ? this._mod.UTF8ToString(p) : '';
  }
  renderSvg(opts) {
    if (!this.isOk) throw new Error(`cannot render: ${this.error}`);
    const opt = opts ? Options.create(this._mod, opts) : null;
    const outDataPtr = this._mod._malloc(8); // ptr ptr uint8
    const outLenPtr = this._mod._malloc(8);  // ptr size_t
    try {
      const rc = this._mod._ubc_render_svg(this._ptr, opt ? opt._ptr : 0, outDataPtr, outLenPtr);
      if (rc !== 0) throw new Error(`ubc_render_svg failed: ${rc}`);
      const buf = this._mod.getValue(outDataPtr, 'i32');
      const len = this._mod.getValue(outLenPtr, 'i32');
      const svg = this._mod.UTF8ToString(buf, len);
      this._mod._ubc_buffer_free(buf, len);
      return svg;
    } finally {
      if (opt) opt.free();
      this._mod._free(outDataPtr);
      this._mod._free(outLenPtr);
    }
  }
  free() { if (this._ptr) { this._mod._ubc_barcode_free(this._ptr); this._ptr = 0; } }
}

class UniBarCode {
  constructor(mod) {
    this._mod = mod;
    const rc = mod._ubc_init();
    if (rc !== 0) throw new Error(`ubc_init failed: ${rc}`);
  }

  static async create(wasmPathOrBuffer, opts) {
    // Browser: the emscripten glue (MODULARIZE=1, EXPORT_NAME=UniBarCodeWasm)
    // loaded via <script> exposes a global factory. Node: require it.
    let factory;
    if (typeof UniBarCodeWasm !== 'undefined') {
      factory = UniBarCodeWasm;
    } else if (typeof require !== 'undefined') {
      factory = require('./unibarcode.js');
    } else {
      throw new Error('UniBarCodeWasm factory not found; load unibarcode.js first');
    }
    const modOpts = Object.assign({}, opts || {});
    if (wasmPathOrBuffer && typeof wasmPathOrBuffer === 'string') {
      modOpts.locateFile = (p) => wasmPathOrBuffer.replace(/[^/]+$/, p);
    }
    const mod = await factory(modOpts);
    return new UniBarCode(mod);
  }

  get version() { return this._mod.UTF8ToString(this._mod._ubc_version()); }
  get abiVersion() { return this._mod._ubc_abi_version(); }
  strerror(code) { return this._mod.UTF8ToString(this._mod._ubc_strerror(code)); }

  encode(symbology, payload) {
    const sym = resolveSymbology(symbology);
    const buf = cstr(this._mod, payload);
    try {
      const ptr = this._mod._ubc_encode(sym, buf);
      if (!ptr) throw new Error('ubc_encode returned NULL (unsupported symbology or bad payload)');
      return new Barcode(this._mod, ptr);
    } finally { this._mod._free(buf); }
  }

  encodeComposite(symbology, payload, addon, addonPayload) {
    const sym = resolveSymbology(symbology);
    const add = resolveSymbology(addon);
    const buf = cstr(this._mod, payload);
    const addBuf = cstr(this._mod, addonPayload);
    try {
      const ptr = this._mod._ubc_encode_composite(sym, buf, add, addBuf);
      if (!ptr) throw new Error('ubc_encode_composite returned NULL (unsupported primary/addon or bad payload)');
      return new Barcode(this._mod, ptr);
    } finally { this._mod._free(buf); this._mod._free(addBuf); }
  }
}

UniBarCode.Symbology = SYMBOLOGY;
UniBarCode.SymbologyName = SYMBOLOGY_NAME;

if (typeof module !== 'undefined') module.exports = { UniBarCode, Symbology: SYMBOLOGY, SymbologyName: SYMBOLOGY_NAME };
if (typeof define === 'function' && define.amd) define(() => ({ UniBarCode, Symbology: SYMBOLOGY, SymbologyName: SYMBOLOGY_NAME }));