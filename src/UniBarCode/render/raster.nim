# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/render — raster (PNG) backend.
##
## Fills an `UniImage.Image[uint8]` (sRGBA) via `UniVector.fillPath`: one
## scanline pass over the per-module rectangle path built by `geometry`. The
## raster output is bars/cells only — HRI is an SVG-side concern (no font file
## is loaded here). `toPng` encodes the image through UniImage's PNG encoder.

import UniColor
import UniImage/core as uimg
import UniImage/formats
import UniVector/raster
import ../common/types
import ./options
import ./geometry

proc fillBackground(img: var uimg.Image[uint8]; bg: Color) =
  ## Solid-fill the image with `bg` converted to sRGBA. Out-of-gamut colors
  ## fill with the raw components so the background still round-trips.
  let srgb = bg.to(tagSrgb)
  let c = if srgb.isOk: srgb.get else: bg
  let r = uint8(clamp(c.comp(0), 0'f32, 1'f32) * 255'f32 + 0.5'f32)
  let g = uint8(clamp(c.comp(1), 0'f32, 1'f32) * 255'f32 + 0.5'f32)
  let b = uint8(clamp(c.comp(2), 0'f32, 1'f32) * 255'f32 + 0.5'f32)
  let a = uint8(clamp(c.alpha, 0'f32, 1'f32) * 255'f32 + 0.5'f32)
  var i = 0
  while i < img.data.len:
    img.data[i] = r
    img.data[i+1] = g
    img.data[i+2] = b
    img.data[i+3] = a
    i += 4

proc toImage*(res: EncodeResult;
              opts: RenderOptions = defaultRenderOptions()): uimg.Image[uint8] =
  ## Render `res` to an sRGBA `Image[uint8]`. Returns a zero-sized image when
  ## `res` is an error.
  if not res.isOk: return uimg.Image[uint8]()
  let (w, h) = pixelSize(res, opts, withHri = false)
  result = uimg.newImage[uint8](w, h, uimg.csRgba)
  fillBackground(result, opts.background)
  fillPath(result, modulePath(res, opts), opts.foreground)

proc toPng*(res: EncodeResult;
            opts: RenderOptions = defaultRenderOptions()): seq[byte] =
  ## Render `res` and encode it to a PNG byte string. Empty on error.
  encodeImage(toImage(res, opts), efPng)









