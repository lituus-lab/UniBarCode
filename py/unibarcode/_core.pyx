# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Cython binding over the UniBarCode C ABI (multi-symbology barcode encoder)."""
from libc.stddef cimport size_t


cdef extern from "UniBarCode.h":
    const char *ubc_version()
    void   ubc_init()
    int    ubc_abi_version()
    const char *ubc_strerror(int code)

    ctypedef struct ubc_barcode
    ctypedef struct ubc_options
    ctypedef struct ubc_color

    ubc_barcode *ubc_encode(int symbology, const char *payload)
    int   ubc_barcode_is_ok(ubc_barcode *h)
    int   ubc_barcode_symbology(ubc_barcode *h)
    int   ubc_barcode_width(ubc_barcode *h)
    int   ubc_barcode_height(ubc_barcode *h)
    int   ubc_barcode_is_2d(ubc_barcode *h)
    const char *ubc_barcode_error(ubc_barcode *h)
    void  ubc_barcode_free(ubc_barcode *h)

    ubc_options *ubc_options_new()
    void  ubc_options_set_module_size(ubc_options *h, float v)
    void  ubc_options_set_bar_height(ubc_options *h, float v)
    void  ubc_options_set_guard_height(ubc_options *h, float v)
    void  ubc_options_set_quiet_zone(ubc_options *h, float v)
    void  ubc_options_set_show_hri(ubc_options *h, int v)
    void  ubc_options_set_foreground(ubc_options *h, ubc_color *c)
    void  ubc_options_set_background(ubc_options *h, ubc_color *c)
    void  ubc_options_free(ubc_options *h)

    ubc_color *ubc_color_parse(const char *s)
    ubc_color *ubc_color_rgba(float r, float g, float b, float a)
    void  ubc_color_free(ubc_color *c)

    int   ubc_render_svg(ubc_barcode *h, ubc_options *opts,
                         unsigned char **out_data, size_t *out_len)
    int   ubc_render_png(ubc_barcode *h, ubc_options *opts,
                         unsigned char **out_data, size_t *out_len)
    void  ubc_buffer_free(void *p, size_t len)


cdef str _borrow_cstr(const char* s):
    if s == NULL:
        return ""
    return (<bytes>s).decode("utf-8")


# Symbology name -> ordinal (keep in sync with include/UniBarCode.h).
SYMBOLOGY = {
    "ean13": 0, "ean8": 1, "upca": 2, "upc-a": 2,
    "code39": 3, "code128": 4, "itf": 5,
    "qr": 6, "qrcode": 6, "datamatrix": 7, "pdf417": 8, "aztec": 9,
    "upce": 10, "upc-e": 10, "ean2": 11, "ean5": 12,
    "microqr": 13, "micro-qr": 13, "gs1128": 14, "gs1-128": 14,
}


def init():
    """Idempotent NimMain bootstrap; call once before any other entry."""
    ubc_init()


def version():
    return _borrow_cstr(ubc_version())


def abi_version():
    return ubc_abi_version()


def strerror(int code):
    return _borrow_cstr(ubc_strerror(code))


def _symbology_ordinal(symbology):
    """Accept a name (str) or an ordinal (int). Returns the int ordinal."""
    if isinstance(symbology, str):
        key = symbology.lower()
        if key not in SYMBOLOGY:
            raise ValueError(f"unknown symbology: {symbology!r}")
        return SYMBOLOGY[key]
    if isinstance(symbology, int):
        if not 0 <= symbology <= 14:
            raise ValueError(f"symbology ordinal out of range: {symbology}")
        return symbology
    raise TypeError(f"symbology must be str or int, got {type(symbology).__name__}")


cdef class Color:
    """A color (tagged space; the ABI exposes sRGB construction)."""
    cdef ubc_color *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ubc_color_free(self._h)
            self._h = NULL

    def __init__(self):
        # Color instances wrap an ABI handle created by Color.parse / Color.rgba
        # (via _wrap, which uses __new__ and bypasses this guard). Direct
        # construction would yield a NULL handle, so forbid it.
        raise TypeError("Color is created via Color.parse() or Color.rgba()")

    @staticmethod
    cdef Color _wrap(ubc_color *h):
        cdef Color r = Color.__new__(Color)
        r._h = h
        return r

    @staticmethod
    def parse(str s):
        """Parse a CSS Color 4 string (hex/rgb/oklch/...)."""
        cdef bytes b = s.encode("utf-8")
        cdef ubc_color *h = ubc_color_parse(<const char*>b)
        if h == NULL:
            raise ValueError(f"color parse failed: {s!r}")
        return Color._wrap(h)

    @staticmethod
    def rgba(float r, float g, float b, float a=1.0):
        """sRGB color from straight-alpha floats in [0, 1]."""
        cdef ubc_color *h = ubc_color_rgba(r, g, b, a)
        if h == NULL:
            raise ValueError("color rgba out of gamut / non-finite")
        return Color._wrap(h)


cdef class Options:
    """Render options. The library owns the handle; freed on GC."""
    cdef ubc_options *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ubc_options_free(self._h)
            self._h = NULL

    def __init__(self):
        self._h = ubc_options_new()
        if self._h == NULL:
            raise MemoryError("ubc_options_new returned NULL")

    def module_size(self, float v):
        ubc_options_set_module_size(self._h, v); return self

    def bar_height(self, float v):
        ubc_options_set_bar_height(self._h, v); return self

    def guard_height(self, float v):
        ubc_options_set_guard_height(self._h, v); return self

    def quiet_zone(self, float v):
        ubc_options_set_quiet_zone(self._h, v); return self

    def show_hri(self, bint v=True):
        ubc_options_set_show_hri(self._h, 1 if v else 0); return self

    def foreground(self, Color c not None):
        ubc_options_set_foreground(self._h, c._h); return self

    def background(self, Color c not None):
        ubc_options_set_background(self._h, c._h); return self


cdef class Barcode:
    """An encode result. The library owns the handle; freed on GC."""
    cdef ubc_barcode *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ubc_barcode_free(self._h)
            self._h = NULL

    def __init__(self):
        # Barcode instances wrap an ABI handle created by unibarcode.encode
        # (via _wrap, which uses __new__ and bypasses this guard). Direct
        # construction would yield a NULL handle, so forbid it.
        raise TypeError("Barcode is created via unibarcode.encode()")

    @staticmethod
    cdef Barcode _wrap(ubc_barcode *h):
        cdef Barcode r = Barcode.__new__(Barcode)
        r._h = h
        return r

    @property
    def is_ok(self):
        return ubc_barcode_is_ok(self._h) != 0

    @property
    def symbology(self):
        return ubc_barcode_symbology(self._h)

    @property
    def width(self):
        return ubc_barcode_width(self._h)

    @property
    def height(self):
        return ubc_barcode_height(self._h)

    @property
    def is_2d(self):
        return ubc_barcode_is_2d(self._h) != 0

    @property
    def error(self):
        return _borrow_cstr(ubc_barcode_error(self._h))

    def render_svg(self, Options opts=None):
        """Render to a standalone SVG string (bytes)."""
        cdef ubc_options *oh = NULL if opts is None else opts._h
        cdef unsigned char *out = NULL
        cdef size_t out_len = 0
        rc = ubc_render_svg(self._h, oh, &out, &out_len)
        if rc != 0:
            raise ValueError(f"render_svg failed: {strerror(rc)}")
        try:
            if out == NULL or out_len == 0:
                return b""
            # The buffer is NUL-terminated; return `out_len` bytes.
            return bytes(<unsigned char[:out_len]>out)
        finally:
            ubc_buffer_free(out, out_len)

    def render_png(self, Options opts=None):
        """Render to PNG bytes."""
        cdef ubc_options *oh = NULL if opts is None else opts._h
        cdef unsigned char *out = NULL
        cdef size_t out_len = 0
        rc = ubc_render_png(self._h, oh, &out, &out_len)
        if rc != 0:
            raise ValueError(f"render_png failed: {strerror(rc)}")
        try:
            if out == NULL or out_len == 0:
                return b""
            return bytes(<unsigned char[:out_len]>out)
        finally:
            ubc_buffer_free(out, out_len)


def encode(symbology, str payload):
    """Encode `payload` for `symbology` (name or ordinal). Returns a Barcode.
    Raises ValueError on an unknown symbology; raises TypeError if `payload`
    is None (it is typed `str`). A failed encode returns a Barcode with
    `is_ok == False` rather than raising."""
    cdef int sym = _symbology_ordinal(symbology)
    cdef bytes b = payload.encode("utf-8")
    # The C entry takes a NUL-terminated string, so an embedded NUL would
    # truncate the payload there and encode a shorter one in silence.
    if b"\x00" in b:
        raise ValueError("payload must not contain an embedded NUL")
    cdef ubc_barcode *h = ubc_encode(sym, <const char*>b)
    if h == NULL:
        raise ValueError(f"encode returned NULL (symbology={symbology}, payload={payload!r})")
    return Barcode._wrap(h)