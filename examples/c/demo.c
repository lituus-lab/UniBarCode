// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include <stdio.h>
#include <string.h>
#include "UniBarCode.h"

static int write_file(const char *path, const unsigned char *buf, size_t len) {
  FILE *f = fopen(path, "wb");
  if (f == NULL) { printf("FAIL: cannot open %s for writing\n", path); return 1; }
  /* A short write and a failed close are both silent otherwise: the buffered
     bytes reach the disk at fclose, so that is where a full filesystem
     reports itself. */
  if (len > 0 && fwrite(buf, 1, len, f) != len) {
    printf("FAIL: short write to %s\n", path);
    fclose(f);
    return 1;
  }
  if (fclose(f) != 0) { printf("FAIL: cannot close %s\n", path); return 1; }
  return 0;
}

int main(void) {
  ubc_init();
  printf("UniBarCode %s (ABI %d)\n", ubc_version(), ubc_abi_version());

  /* EAN-13 -> PNG. */
  ubc_barcode *ean = ubc_encode(UBC_SBC_EAN13, "978020137962");
  if (ean == NULL || !ubc_barcode_is_ok(ean)) {
    printf("FAIL: EAN-13 encode failed\n");
    ubc_barcode_free(ean);
    return 1;
  }
  printf("EAN-13: %d modules, is_2d=%d\n",
         ubc_barcode_width(ean), ubc_barcode_is_2d(ean));
  unsigned char *png = NULL; size_t png_len = 0;
  if (ubc_render_png(ean, NULL, &png, &png_len) != UBC_OK) {
    /* Report it in the exit status too: the demo runs as a CI gate, and
       printing FAIL while returning 0 let a broken renderer pass. */
    printf("FAIL: render_png failed\n");
    ubc_barcode_free(ean);
    return 1;
  } else {
    if (write_file("demo.png", png, png_len) != 0) {
      ubc_buffer_free(png, png_len);
      ubc_barcode_free(ean);
      return 1;
    }
    printf("wrote demo.png (%zu bytes)\n", png_len);
  }
  ubc_buffer_free(png, png_len);
  ubc_barcode_free(ean);

  /* QR Code -> SVG. */
  ubc_barcode *qr = ubc_encode(UBC_SBC_QRCODE, "Hello");
  if (qr == NULL || !ubc_barcode_is_ok(qr)) {
    printf("FAIL: QR encode failed\n");
    ubc_barcode_free(qr);
    return 1;
  }
  printf("QR: %dx%d modules\n", ubc_barcode_width(qr), ubc_barcode_height(qr));
  unsigned char *svg = NULL; size_t svg_len = 0;
  if (ubc_render_svg(qr, NULL, &svg, &svg_len) != UBC_OK) {
    /* Report it in the exit status too: the demo runs as a CI gate, and
       printing FAIL while returning 0 let a broken renderer pass. */
    printf("FAIL: render_svg failed\n");
    ubc_barcode_free(qr);
    return 1;
  } else {
    if (write_file("demo.svg", svg, svg_len) != 0) {
      ubc_buffer_free(svg, svg_len);
      ubc_barcode_free(qr);
      return 1;
    }
    printf("wrote demo.svg (%zu bytes)\n", svg_len);
  }
  ubc_buffer_free(svg, svg_len);
  ubc_barcode_free(qr);

  return 0;
}
