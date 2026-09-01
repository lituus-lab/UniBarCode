# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""unibarcode — Python binding over the UniBarCode C library."""
from ._core import (
    Barcode,
    Color,
    Options,
    abi_version,
    encode,
    init,
    strerror,
    version,
)

init()

__version__ = version()


__all__ = [
    "Barcode",
    "Color",
    "Options",
    "__version__",
    "abi_version",
    "encode",
    "init",
    "strerror",
    "version",
]