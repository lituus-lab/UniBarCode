// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include <stdio.h>
#include "UniBarCode.h"

int main(void) {
  printf("UniBarCode %s\n", unibarcode_version());
  int ns[] = {0, 1, 10, 20, 50, 90, UNIBARCODE_FIB_MAX_N};
  for (size_t i = 0; i < sizeof(ns) / sizeof(ns[0]); i++)
    printf("fib(%d) = %lld\n", ns[i], unibarcode_fibonacci(ns[i]));
  return 0;
}
