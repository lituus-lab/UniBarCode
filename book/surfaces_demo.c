/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 lituus-lab */
/* Run by book/surfaces.nim during the book build; its output is the page's. */
#include <stdio.h>
#include "UniBarCode.h"

int main(void) {
  printf("unibarcode_version()            = %s\n", unibarcode_version());
  printf("unibarcode_fibonacci(10)        = %lld\n", unibarcode_fibonacci(10));
  printf("unibarcode_fibonacci(-1)        = %lld   (clamped, not an error)\n",
         unibarcode_fibonacci(-1));
  printf("unibarcode_fibonacci(200)       = %lld   (clamped to n = %d)\n",
         unibarcode_fibonacci(200), UNIBARCODE_FIB_MAX_N);
  return 0;
}
