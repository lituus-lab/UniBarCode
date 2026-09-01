# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/render — geometry bridge from `EncodeResult` to a `UniVector.Path`.
##
## Builds one rectangle per dark module (1-D) or dark cell (2-D) in pixel
## coordinates, and computes the total pixel size of the render. Both the SVG
## and raster backends consume this so the module->pixel mapping is defined
## once. Guard-bar extension (EAN/UPC) is applied from `layout.guardModules`.

import UniVector/path
import ../common/types
import ./options

proc guardSet(res: EncodeResult): set[int16] =
  for g in res.layout.guardModules:
    if g >= 0 and g <= high(int16).int: result.incl(int16(g))

const AddonGapModules* = 7
  ## Separation between a primary EAN/UPC symbol and its add-on, in modules
  ## (ISO/IEC 15420 allows 5..12; 7 sits mid-range and matches common encoders).

proc supplementModuleOffsets*(res: EncodeResult): seq[int] =
  ## X offset (in modules, from the primary's module 0) of each add-on in
  ## `res.layout.supplements`. Each add-on sits `AddonGapModules` to the right
  ## of the preceding symbol; add-ons have no supplements of their own.
  var off = res.modules.width + AddonGapModules
  for s in res.layout.supplements:
    result.add(off)
    off += s.modules.width + AddonGapModules

proc modulePath*(res: EncodeResult; opts: RenderOptions): Path =
  ## A `Path` of filled rectangles covering every dark module/cell, in pixels.
  ## Add-ons (EAN-2/EAN-5) are drawn to the right of the primary at
  ## `opts.barHeight`; they carry no long guards.
  var p = newPath()
  if res.modules.is2D:
    let gw = res.modules.gridWidth
    let gh = res.modules.gridHeight
    for r in 0 ..< gh:
      for c in 0 ..< gw:
        if res.modules.grid[r][c]:
          p.rect(opts.quietZone + float32(c) * opts.moduleSize,
                 opts.quietZone + float32(r) * opts.moduleSize,
                 opts.moduleSize, opts.moduleSize)
  else:
    let gs = guardSet(res)
    let gh = if opts.guardHeight > 0'f32: opts.guardHeight else: opts.barHeight
    for i, dark in res.modules.bars:
      if dark:
        let h = if int16(i) in gs: gh else: opts.barHeight
        p.rect(opts.quietZone + float32(i) * opts.moduleSize,
               opts.quietZone, opts.moduleSize, h)
    let supOff = supplementModuleOffsets(res)
    for si, s in res.layout.supplements:
      let base = float32(supOff[si])
      for j, dark in s.modules.bars:
        if dark:
          p.rect(opts.quietZone + (base + float32(j)) * opts.moduleSize,
                 opts.quietZone, opts.moduleSize, opts.barHeight)
  p

const HriStripModules = 5'f32 ## HRI text strip height, in module units.

proc pixelSize*(res: EncodeResult; opts: RenderOptions;
                withHri: bool): tuple[w, h: int] =
  ## Total pixel dimensions of the render. `withHri` reserves a text strip
  ## below the bars (SVG); the raster backend passes false (bars/cells only).
  ## The width grows by every add-on plus its gap.
  if res.modules.is2D:
    let side = opts.quietZone * 2'f32 +
               float32(res.modules.gridWidth) * opts.moduleSize
    let h = opts.quietZone * 2'f32 +
            float32(res.modules.gridHeight) * opts.moduleSize
    result = (int(side + 0.5'f32), int(h + 0.5'f32))
  else:
    let gh = if opts.guardHeight > 0'f32: opts.guardHeight else: opts.barHeight
    var w = opts.quietZone * 2'f32 + float32(res.modules.width) *
        opts.moduleSize
    for s in res.layout.supplements:
      w += float32(AddonGapModules + s.modules.width) * opts.moduleSize
    var h = opts.quietZone * 2'f32 + gh
    if withHri and opts.showHri and res.layout.hri.len > 0:
      h += opts.moduleSize * HriStripModules
    result = (int(w + 0.5'f32), int(h + 0.5'f32))

proc hriBaselineY*(res: EncodeResult; opts: RenderOptions): float32 =
  ## Y pixel coordinate of the HRI text baseline (top of the text strip).
  let gh = if opts.guardHeight > 0'f32: opts.guardHeight else: opts.barHeight
  opts.quietZone + gh + opts.moduleSize * 2'f32









