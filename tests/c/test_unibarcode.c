// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include "UniBarCode.h"

static int failures = 0;

static void check_int(const char *name, int got, int want) {
  if (got != want) { printf("FAIL %s: got %d want %d\n", name, got, want); failures++; }
  else printf("ok   %s = %d\n", name, got);
}

static void check_str(const char *name, const char *got, const char *want) {
  if (got == NULL || strcmp(got, want) != 0)
    { printf("FAIL %s: got \"%s\" want \"%s\"\n", name, got ? got : "(null)", want); failures++; }
  else printf("ok   %s = \"%s\"\n", name, got);
}

static void check_prefix(const char *name, const unsigned char *buf, size_t len,
                         const char *want, size_t want_len) {
  if (len < want_len || buf == NULL || memcmp(buf, want, want_len) != 0) {
    printf("FAIL %s: bad prefix (len=%zu)\n", name, len); failures++;
  } else {
    printf("ok   %s (len=%zu)\n", name, len);
  }
}

/* Parse the geometric width from an SVG viewBox="0 0 W H" attribute, or -1. */
static int parse_svg_width(const unsigned char *svg) {
  if (svg == NULL) return -1;
  const char *p = strstr((const char *)svg, "viewBox=\"");
  int w = -1;
  if (p && sscanf(p + 9, "%*d %*d %d %*d\"", &w) != 1) return -1;
  return w;
}

int main(void) {
  check_int("ubc_init", ubc_init(), UBC_OK);
  check_str("version", ubc_version(), UNIBARCODE_VERSION);
  check_int("abi_version", ubc_abi_version(), UNIBARCODE_ABI_VERSION);

  /* EAN-13: 12 digits -> 95-module symbol, checksum appended. */
  ubc_barcode *ean = ubc_encode(UBC_SBC_EAN13, "978020137962");
  if (ean == NULL) { printf("FAIL: ubc_encode(EAN-13) returned NULL\n"); failures++; }
  else {
    check_int("ean13 is_ok",   ubc_barcode_is_ok(ean), 1);
    check_int("ean13 width",   ubc_barcode_width(ean), 95);
    check_int("ean13 height",  ubc_barcode_height(ean), 1);
    check_int("ean13 is_2d",   ubc_barcode_is_2d(ean), 0);
    check_int("ean13 symbology", ubc_barcode_symbology(ean), UBC_SBC_EAN13);
    ubc_barcode_free(ean);
  }

  /* EAN-13 + EAN-5 composite: primary 95 modules with a 47-module add-on. */
  ubc_barcode *comp = ubc_encode_composite(UBC_SBC_EAN13, "978020137962",
                                           UBC_SBC_EAN5, "52495");
  if (comp == NULL) { printf("FAIL: ubc_encode_composite returned NULL\n"); failures++; }
  else {
    check_int("composite is_ok", ubc_barcode_is_ok(comp), 1);
    check_int("composite width", ubc_barcode_width(comp), 95);
    check_int("composite is_2d", ubc_barcode_is_2d(comp), 0);
    /* The rendered composite widens geometrically to include the EAN-5
       supplement: its SVG viewBox width exceeds the primary-only one. */
    ubc_barcode *prim = ubc_encode(UBC_SBC_EAN13, "978020137962");
    unsigned char *psvg = NULL; size_t psvg_len = 0;
    unsigned char *csvg = NULL; size_t csvg_len = 0;
    if (ubc_render_svg(prim, NULL, &psvg, &psvg_len) != UBC_OK)
      { printf("FAIL: primary render_svg\n"); failures++; }
    else if (ubc_render_svg(comp, NULL, &csvg, &csvg_len) != UBC_OK)
      { printf("FAIL: composite render_svg\n"); failures++; }
    else {
      check_prefix("composite svg prefix", csvg, csvg_len, "<svg", 4);
      int pw = parse_svg_width(psvg);
      int cw = parse_svg_width(csvg);
      if (pw < 0 || cw < 0)
        { printf("FAIL: svg viewBox width unparseable (pw=%d cw=%d)\n", pw, cw); failures++; }
      else if (cw <= pw)
        { printf("FAIL: composite svg not wider (%d <= %d)\n", cw, pw); failures++; }
      else
        printf("ok   composite svg wider (%d > %d)\n", cw, pw);
    }
    ubc_buffer_free(psvg, psvg_len);
    ubc_buffer_free(csvg, csvg_len);
    ubc_barcode_free(prim);
    ubc_barcode_free(comp);
  }

  /* QR Code: 2-D grid. */
  ubc_barcode *qr = ubc_encode(UBC_SBC_QRCODE, "Hello");
  if (qr == NULL) { printf("FAIL: ubc_encode(QR) returned NULL\n"); failures++; }
  else {
    check_int("qr is_ok",  ubc_barcode_is_ok(qr), 1);
    check_int("qr is_2d",  ubc_barcode_is_2d(qr), 1);
    check_int("qr width",  ubc_barcode_width(qr), 21);
    check_int("qr height", ubc_barcode_height(qr), 21);
    ubc_barcode_free(qr);
  }

  /* Invalid payload: encode returns a handle holding a failed result. */
  ubc_barcode *bad = ubc_encode(UBC_SBC_EAN13, "abc");
  if (bad == NULL) { printf("FAIL: ubc_encode(bad) returned NULL\n"); failures++; }
  else {
    check_int("bad is_ok", ubc_barcode_is_ok(bad), 0);
    if (ubc_barcode_error(bad)[0] == '\0')
      { printf("FAIL: bad error message empty\n"); failures++; }
    else
      printf("ok   bad error = \"%s\"\n", ubc_barcode_error(bad));
    ubc_barcode_free(bad);
  }

  /* Unknown symbology -> NULL. */
  check_int("unknown symbology", ubc_encode(999, "x") == NULL, 1);

  /* SVG render: NUL-terminated buffer, starts with "<svg". */
  ubc_barcode *ean2 = ubc_encode(UBC_SBC_EAN13, "978020137962");
  unsigned char *svg = NULL; size_t svg_len = 0;
  check_int("render_svg", ubc_render_svg(ean2, NULL, &svg, &svg_len), UBC_OK);
  check_prefix("svg prefix", svg, svg_len, "<svg", 4);
  if (svg_len > 0 && svg[svg_len] != 0)
    { printf("FAIL: svg not NUL-terminated\n"); failures++; }
  else if (svg_len > 0)
    printf("ok   svg NUL-terminated\n");
  ubc_buffer_free(svg, svg_len);
  ubc_barcode_free(ean2);

  /* PNG render: starts with the PNG signature. */
  ubc_barcode *ean3 = ubc_encode(UBC_SBC_EAN13, "978020137962");
  unsigned char *png = NULL; size_t png_len = 0;
  check_int("render_png", ubc_render_png(ean3, NULL, &png, &png_len), UBC_OK);
  check_prefix("png prefix", png, png_len, "\x89PNG", 4);
  ubc_buffer_free(png, png_len);
  ubc_barcode_free(ean3);

  /* Options + color handles round-trip and free cleanly. */
  ubc_options *opts = ubc_options_new();
  ubc_color *fg = ubc_color_parse("#000000");
  ubc_color *bg = ubc_color_rgba(1.0f, 1.0f, 1.0f, 1.0f);
  check_int("color parse non-null", fg != NULL, 1);
  check_int("color rgba non-null",  bg != NULL, 1);
  ubc_options_set_module_size(opts, 3.0f);
  ubc_options_set_foreground(opts, fg);
  ubc_options_set_background(opts, bg);
  ubc_color_free(fg);
  ubc_color_free(bg);
  ubc_options_free(opts);

  /* NULL-is-a-no-op frees. */
  ubc_barcode_free(NULL);
  ubc_options_free(NULL);
  ubc_color_free(NULL);
  ubc_buffer_free(NULL, 0);

  if (failures == 0) { printf("\nAll C ABI tests passed.\n"); return 0; }
  printf("\n%d C ABI test(s) FAILED.\n", failures);
  return 1;
}