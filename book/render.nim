# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/strutils
import nimib, nimibook
import lituus_theme
import UniBarCode

nbInit(theme = useNimibook)
useLituus()
nb.title = "Rendering"

nbText: """
## Render

The SVG backend emits a standalone document; HRI text uses a generic
`monospace` family — no font file is embedded, so the output is portable. The
raster backend draws bars/cells only through `UniVector.fillPath` onto an
`UniImage.Image[uint8]` and encodes PNG via UniImage.
"""

nbText: """
The symbol is the EAN-13 from *Encoding*. Each chapter is its own program, so
it is encoded again here rather than carried over:
"""

nbCode:
  let r = encode(sbEan13, "978020137962")

nbCode:
  let svg = toSvg(r)
  echo "svg starts with <svg: ", svg.startsWith("<svg")
  let png = toPng(r)
  echo "png bytes = ", png.len, " signature = ", png[0], " ", png[1], " ", png[
      2], " ", png[3]

nbText: """
"""

nbSave
