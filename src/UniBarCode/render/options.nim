# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/render — rendering options shared by the SVG and raster backends.
##
## `RenderOptions` maps logical module units (from `BarcodeModules`) to pixels.
## It carries no symbology-specific knowledge: the encoder already computed
## guard modules and HRI placements into `BarcodeLayout`, so the renderer only
## scales and colors. Foreground/background are `UniColor.Color` values in any
## tagged space; the backends convert to sRGB for emission.

import UniColor

type
  RenderOptions* = object
    ## Pixel mapping and colors for one render.
    moduleSize*: float32  ## pixels per module (1-D bar/space and 2-D cell)
    barHeight*: float32   ## 1-D bar height in pixels
    guardHeight*: float32 ## 1-D guard-bar height (<= 0 means use barHeight)
    quietZone*: float32   ## quiet zone in pixels, applied on every side
    foreground*: Color    ## bar / cell color
    background*: Color    ## background fill (alpha 0 = transparent / none)
    showHri*: bool        ## emit human-readable text (SVG only)

proc defaultRenderOptions*(): RenderOptions =
  ## Black bars on white, 2 px modules, 80 px bar height, 22 px quiet zone,
  ## guards 90 px, HRI on. A safe baseline for screen and print.
  let fg = color(tagSrgb, 0'f32, 0'f32, 0'f32, 1'f32)
  let bg = color(tagSrgb, 1'f32, 1'f32, 1'f32, 1'f32)
  RenderOptions(
    moduleSize: 2'f32,
    barHeight: 80'f32,
    guardHeight: 90'f32,
    # Eleven modules at the default moduleSize. EAN-13 requires eleven on the
      # left and seven on the right, UPC-A nine on each; ten pixels was five
      # modules, under every one of them. The field is in pixels, so a caller
      # changing moduleSize must scale this with it.
    quietZone: 22'f32,
    foreground: if fg.isOk: fg.get else: Color(),
    background: if bg.isOk: bg.get else: Color(),
    showHri: true,
  )









