// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNIBARCODE_H
#define UNIBARCODE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNIBARCODE_VERSION_MAJOR 1
#define UNIBARCODE_VERSION_MINOR 0
#define UNIBARCODE_VERSION_PATCH 0
#define UNIBARCODE_VERSION "1.0.0"

#define UNIBARCODE_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNIBARCODE_VERSION_MAJOR > (ma)) || \
   (UNIBARCODE_VERSION_MAJOR == (ma) && UNIBARCODE_VERSION_MINOR > (mi)) || \
   (UNIBARCODE_VERSION_MAJOR == (ma) && UNIBARCODE_VERSION_MINOR == (mi) && \
    (UNIBARCODE_VERSION_PATCH >= (pa))))

#define UNIBARCODE_ABI_VERSION 1

/* BarcodeSymbology ordinals (keep in sync with src/UniBarCode/common/types.nim). */
#define UBC_SBC_EAN13       0
#define UBC_SBC_EAN8        1
#define UBC_SBC_UPC_A       2
#define UBC_SBC_CODE39      3
#define UBC_SBC_CODE128     4
#define UBC_SBC_ITF         5
#define UBC_SBC_QRCODE      6
#define UBC_SBC_DATAMATRIX  7
#define UBC_SBC_PDF417      8
#define UBC_SBC_AZTEC       9
#define UBC_SBC_UPC_E       10
#define UBC_SBC_EAN2        11
#define UBC_SBC_EAN5        12
#define UBC_SBC_MICROQR     13
#define UBC_SBC_GS1128      14

typedef enum {
  UBC_OK = 0,
  UBC_ERR_FORMAT = 2,
  UBC_ERR_UNSUP = 4,
  UBC_ERR_MEM = 8
} ubc_status;

/* Opaque, library-owned handles. NULL is a no-op for every `_free`. */
typedef struct ubc_barcode ubc_barcode;
typedef struct ubc_options ubc_options;
typedef struct ubc_color   ubc_color;

/* Idempotent NimMain bootstrap. Call once before any other ubc_* entry.
 * Never raises. Single-threaded, reentrant. */
int ubc_init(void);

/* ABI version of this lib (matches UNIBARCODE_ABI_VERSION). */
int ubc_abi_version(void);

/* Static version string; do not free. */
const char *ubc_version(void);

/* Static message for an ubc_* status code. */
const char *ubc_strerror(int code);

/* ------------------------------ barcode ----------------------------------- */

/* Encode `payload` with `symbology` (a UBC_SBC_* ordinal). NULL on a nil
 * payload, unknown symbology, or encode error. The handle holds the result
 * even on a validation error — check ubc_barcode_is_ok. Free with
 * ubc_barcode_free. */
ubc_barcode *ubc_encode(int symbology, const char *payload);

/* 1 if the encode succeeded, 0 otherwise (NULL handle -> 0). */
int ubc_barcode_is_ok(ubc_barcode *h);

/* Symbology ordinal of the result (-1 on a NULL handle). */
int ubc_barcode_symbology(ubc_barcode *h);

/* Module width (1-D: bar count; 2-D: grid columns) and height (1-D: 1; 2-D:
 * grid rows). 0 on a NULL handle or failed encode. */
int ubc_barcode_width(ubc_barcode *h);
int ubc_barcode_height(ubc_barcode *h);

/* 1 if the symbology is 2-D, 0 otherwise (NULL handle -> 0). */
int ubc_barcode_is_2d(ubc_barcode *h);

/* Static message for the result's error kind ("" when ok or NULL handle). */
const char *ubc_barcode_error(ubc_barcode *h);

void ubc_barcode_free(ubc_barcode *h);

/* Encode a primary `payload` with an EAN-2/EAN-5 add-on (`addon` = UBC_SBC_EAN2
 * or UBC_SBC_EAN5) attached to its right. NULL on a nil payload/addon,
 * out-of-range symbology, or encode error. The handle holds the result even on
 * a validation error — check ubc_barcode_is_ok. Free with ubc_barcode_free. */
ubc_barcode *ubc_encode_composite(int symbology, const char *payload,
                                  int addon, const char *addon_payload);

/* ------------------------------ options ----------------------------------- */

/* Default render options (black on white, module 2px, HRI on). NULL on
 * allocation failure. */
ubc_options *ubc_options_new(void);

void ubc_options_set_module_size(ubc_options *h, float v);
void ubc_options_set_bar_height(ubc_options *h, float v);
void ubc_options_set_guard_height(ubc_options *h, float v);
void ubc_options_set_quiet_zone(ubc_options *h, float v);
void ubc_options_set_show_hri(ubc_options *h, int v);
void ubc_options_set_foreground(ubc_options *h, ubc_color *c);
void ubc_options_set_background(ubc_options *h, ubc_color *c);

void ubc_options_free(ubc_options *h);

/* ------------------------------- color ------------------------------------ */

/* Parse a CSS Color 4 string (hex/rgb/oklch/...). NULL on a nil string or
 * unparseable input. */
ubc_color *ubc_color_parse(const char *s);

/* An sRGB color from straight-alpha floats in [0, 1]. NULL on out-of-gamut. */
ubc_color *ubc_color_rgba(float r, float g, float b, float a);

void ubc_color_free(ubc_color *c);

/* ------------------------------- render ----------------------------------- */

/* Render the barcode to a standalone SVG string. On success allocates
 * *outData as a NUL-terminated buffer (free with ubc_buffer_free) and sets
 * *outLen to the string length (excluding the NUL). `opts` may be NULL. */
int ubc_render_svg(ubc_barcode *h, ubc_options *opts,
                   uint8_t **outData, size_t *outLen);

/* Render the barcode to a PNG byte string. On success allocates *outData
 * (free with ubc_buffer_free) and sets *outLen. `opts` may be NULL.
 * Declared only when the library is built with the raster backend; define
 * UNIBARCODE_NO_RASTER (i.e. build with -d:ubcNoRaster) to omit it so the
 * header and the library stay in sync. */
#ifndef UNIBARCODE_NO_RASTER
int ubc_render_png(ubc_barcode *h, ubc_options *opts,
                   uint8_t **outData, size_t *outLen);
#endif

/* ------------------------------- buffer ----------------------------------- */

/* Free a buffer returned by ubc_render_svg / ubc_render_png. NULL is a no-op.
 * `len` is ignored. */
void ubc_buffer_free(void *p, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* UNIBARCODE_H */