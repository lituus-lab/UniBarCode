# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/render — SVG backend.
##
## Emits a standalone W3C SVG document: an optional background rectangle, the
## bar/cell path (one `<path>` whose `d` string is UniVector's serialization of
## the per-module rectangles), and HRI `<text>` runs for 1-D symbologies. HRI
## uses a generic `monospace` family — no font file is embedded or required, so
## the output is portable and renders with any viewer's default monospace.

import std/strformat
import UniColor
import UniVector/path
import UniVector/svg
import ../common/types
import ./options
import ./geometry

proc escapeXml(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    else: result.add c

proc toSvg*(res: EncodeResult;
            opts: RenderOptions = defaultRenderOptions()): string =
  ## Render `res` to a standalone SVG string. Returns `""` when `res` is an
  ## error. The viewBox matches the raster surface 1:1.
  if not res.isOk: return ""

  let (w, h) = pixelSize(res, opts, withHri = true)
  let d = $(modulePath(res, opts))
  let fg = toSvgColor(opts.foreground)

  result = &"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">"""
  if opts.background.alpha > 0'f32:
    result &= &"""<rect x="0" y="0" width="{w}" height="{h}" fill="{toSvgColor(opts.background)}"/>"""
  result &= &"""<path d="{d}" fill="{fg}"/>"""

  if opts.showHri and res.layout.hri.len > 0 and not res.modules.is2D:
    let fs = opts.moduleSize * 5'f32
    let y = hriBaselineY(res, opts) + fs
    for g in res.layout.hri:
      let x = opts.quietZone + g.moduleCenter.float32 * opts.moduleSize
      result &= &"""<text x="{x}" y="{y}" font-family="monospace" font-size="{fs}" text-anchor="middle" fill="{fg}">{escapeXml(g.text)}</text>"""
    let supOff = supplementModuleOffsets(res)
    for si, s in res.layout.supplements:
      let base = float32(supOff[si])
      for g in s.layout.hri:
        let x = opts.quietZone + (base + g.moduleCenter.float32) *
            opts.moduleSize
        result &= &"""<text x="{x}" y="{y}" font-family="monospace" font-size="{fs}" text-anchor="middle" fill="{fg}">{escapeXml(g.text)}</text>"""

  result &= "</svg>"









