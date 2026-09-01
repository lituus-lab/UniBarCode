# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/strutils
import nimib, nimibook
import lituus_theme
import UniBarCode

nbInit(theme = useNimibook)
useLituus()
nb.title = "C and Python"

nbText: """
## The C ABI

The same surface, reachable from anything that speaks C. The header is
hand-written and kept in sync with `src/UniBarCode/c_api.nim`; `tests/c` links
one against the other on every CI run, so a drift is caught rather than
shipped. Handles are opaque; buffers from `ubc_render_svg` / `ubc_render_png`
are freed with `ubc_buffer_free`. No Nim exception or Defect crosses the ABI —
failures map to `UBC_*` status codes.

```c
ubc_barcode *h = ubc_encode(UBC_SBC_EAN13, "978020137962");
unsigned char *out = NULL;
size_t len = 0;
if (ubc_render_png(h, NULL, &out, &len) == UBC_OK) {
  /* ... use out[0..len) ... */
  ubc_buffer_free(out, len);
}
ubc_barcode_free(h);
```

## The Python surface

A Cython extension over the C ABI, shipped as a self-contained wheel: the
library travels inside the package, so installing it needs neither Nim nor a
compiler.

```python
import unibarcode
bc = unibarcode.encode("ean13", "978020137962")
bc.width                      # 95
bc.render_png()[:4]           # b'\\x89PNG'
```

`py/notebooks/quickstart.ipynb` runs these calls against an installed wheel and
renders on GitHub directly.
"""

nbSave
