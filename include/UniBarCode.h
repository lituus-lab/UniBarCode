// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNIBARCODE_H
#define UNIBARCODE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNIBARCODE_VERSION_MAJOR 0
#define UNIBARCODE_VERSION_MINOR 1
#define UNIBARCODE_VERSION_PATCH 0
#define UNIBARCODE_VERSION "0.1.0"

#define UNIBARCODE_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNIBARCODE_VERSION_MAJOR > (ma)) || \
   (UNIBARCODE_VERSION_MAJOR == (ma) && UNIBARCODE_VERSION_MINOR > (mi)) || \
   (UNIBARCODE_VERSION_MAJOR == (ma) && UNIBARCODE_VERSION_MINOR == (mi) && \
    UNIBARCODE_VERSION_PATCH >= (pa)))

/* Largest n with unibarcode_fibonacci(n) fitting in long long (int64). */
#define UNIBARCODE_FIB_MAX_N 92

/* Static version string; do not free. */
const char *unibarcode_version(void);

/* fibonacci(n), n clamped to [0, UNIBARCODE_FIB_MAX_N].
 * n < 0 -> 0; n > UNIBARCODE_FIB_MAX_N -> fibonacci(UNIBARCODE_FIB_MAX_N).
 * Never raises. Single-threaded, reentrant. */
long long unibarcode_fibonacci(int n);

#ifdef __cplusplus
}
#endif

#endif /* UNIBARCODE_H */
