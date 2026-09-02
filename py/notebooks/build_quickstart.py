# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Author py/notebooks/quickstart.ipynb, then execute it so the committed file
carries real outputs for GitHub to render. Run from the repo root:

    python3 py/notebooks/build_quickstart.py

CI re-executes the notebook against an installed wheel; this script only
regenerates it after an API change."""
import os

import nbformat as nbf
from nbclient import NotebookClient

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "quickstart.ipynb")

CELLS = [
    ("md", """# UniBarCode — Python quickstart

`unibarcode` is a Cython extension over the UniBarCode C ABI, shipped as a
self-contained wheel: the native library travels inside the package, so
installing it needs neither Nim nor a compiler.

```
pip install lituus-unibarcode
```

CI executes this notebook against the wheel the release actually publishes, so
an output below that stops matching fails the build."""),
    ("md", "## The API"),
    ("code", """import unibarcode

unibarcode.version(), unibarcode.__version__"""),
    ("md", "Encode a payload by symbology name (or ordinal). The result carries module dimensions and render methods."),
    ("code", """bc = unibarcode.encode("ean13", "978020137962")
bc.is_ok, bc.width, bc.height, bc.is_2d"""),
    ("md", "2-D symbologies produce a grid."),
    ("code", """qr = unibarcode.encode("qr", "Hello")
qr.is_2d, qr.width, qr.height"""),
    ("md", """## Validation

A bad payload returns a result with `is_ok == False` and an error message,
rather than raising — the caller decides how to handle it."""),
    ("code", """bad = unibarcode.encode("ean13", "abc")
bad.is_ok, bad.error"""),
    ("md", "An unknown symbology raises immediately."),
    ("code", """try:
    unibarcode.encode("nope", "x")
except ValueError as exc:
    print("ValueError:", exc)"""),
    ("md", """## Render

`render_png` and `render_svg` both return bytes -- the SVG is a standalone document, not a `str`. Options control module size, bar height, colors, and the HRI text strip."""),
    ("code", """png = bc.render_png()
png[:4]"""),
    ("code", """opts = unibarcode.Options().module_size(3).bar_height(120).show_hri(False)
svg = bc.render_svg(opts)
svg[:20]"""),
    ("md", "Colors parse any CSS Color 4 string."),
    ("code", """opts = unibarcode.Options().foreground(unibarcode.Color.parse("#3366cc"))
bc.render_png(opts)[:4]"""),
    ("md", """## The C ABI underneath

The same entry points are reachable from anything that speaks C. No exception
ever unwinds across the ABI boundary — failures map to `UBC_*` status codes:

```c
ubc_barcode *h = ubc_encode(UBC_SBC_EAN13, "978020137962");
ubc_render_png(h, NULL, &out, &len);   /* UBC_OK */
```

See `include/UniBarCode.h`, and the book for the full picture."""),
]


def main():
    nb = nbf.v4.new_notebook()
    nb.cells = [
        nbf.v4.new_markdown_cell(src) if kind == "md" else nbf.v4.new_code_cell(src)
        for kind, src in CELLS
    ]
    nb.metadata["kernelspec"] = {
        "display_name": "Python 3",
        "language": "python",
        "name": "python3",
    }
    # Execute from the repo root, never from py/: there, `import unibarcode`
    # would resolve to the py/unibarcode source tree instead of the installed
    # package, and the notebook would stop testing what it claims to test.
    NotebookClient(nb, timeout=120, kernel_name="python3",
                   resources={"metadata": {"path": ROOT}}).execute()
    with open(OUT, "w", encoding="utf-8") as f:
        nbf.write(nb, f)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
