# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
cdef extern from "UniBarCode.h":
    const char *unibarcode_version()
    long long unibarcode_fibonacci(int n)
    # The domain bound comes from the header rather than being restated here:
    # one copy fewer to drift, and the Python check enforces exactly what the
    # C ABI clamps to.
    int UNIBARCODE_FIB_MAX_N


FIB_MAX_N = UNIBARCODE_FIB_MAX_N


def fibonacci(int n):
    """Raw C call (no domain check). Use unibarcode.fibonacci."""
    return unibarcode_fibonacci(n)


def version():
    return unibarcode_version()
