# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode — multi-symbology barcode encoder with SVG and raster output.
##
## Public surface: the `encode(symbology, payload)` dispatcher, the domain
## types in `common/types`, and the renderers in `render/{svg,raster}`. Each
## symbology encoder is also importable directly as `UniBarCode/symbology/<name>`
## for callers that want to bypass the dispatch.
import UniBarCode/common/[types, digits]
export types, digits

import UniBarCode/symbology/[
  ean13, ean8, upca, code39, code128, itf, qrcode, datamatrix, pdf417, aztec,
  upce, ean2, ean5, microqr, gs1128]
import UniBarCode/render/[options, svg]
export options, svg
# The raster (PNG) backend pulls UniImage, whose DEFLATE codec is not
# JS/WASM-portable (int64/int mismatch on 32-bit targets). It is imported only
# on native targets without -d:ubcNoRaster; web/figma use the SVG backend,
# which needs no raster path.
when not defined(js) and not defined(ubcNoRaster):
  import UniBarCode/render/raster
  export raster

proc encode*(symbology: BarcodeSymbology; payload: string): EncodeResult =
  ## Encode `payload` for `symbology`. Returns an `EncodeResult`; check `.isOk`.
  ## Never raises: validation failures come back as `ekValidation` errors.
  case symbology
  of sbEan13: ean13.encode(payload)
  of sbEan8: ean8.encode(payload)
  of sbUpcA: upca.encode(payload)
  of sbCode39: code39.encode(payload)
  of sbCode128: code128.encode(payload)
  of sbItf: itf.encode(payload)
  of sbQrCode: qrcode.encode(payload)
  of sbDataMatrix: datamatrix.encode(payload)
  of sbPdf417: pdf417.encode(payload)
  of sbAztec: aztec.encode(payload)
  of sbUpcE: upce.encode(payload)
  of sbEan2: ean2.encode(payload)
  of sbEan5: ean5.encode(payload)
  of sbMicroQr: microqr.encode(payload)
  of sbGs1128: gs1128.encode(payload)

proc encodeComposite*(symbology: BarcodeSymbology; payload: string;
                      addon: BarcodeSymbology;
                          addonPayload: string): EncodeResult =
  ## Encode a primary `payload` and attach an EAN-2 or EAN-5 add-on (`addon` with
  ## `addonPayload`) to its right. The primary must be an EAN/UPC family member
  ## (EAN-13/8, UPC-A/E). Returns the primary result with the add-on in
  ## `layout.supplements` on success; an unsupported primary, a non-add-on
  ## `addon`, or an add-on validation failure yields an `ekValidation` error
  ## scoped to the requested primary symbology. Never raises.
  if symbology notin {sbEan13, sbEan8, sbUpcA, sbUpcE}:
    return encodeError(symbology, ekValidation,
      "composite primary must be EAN-13/8, UPC-A or UPC-E")
  if addon notin {sbEan2, sbEan5}:
    return encodeError(symbology, ekValidation,
      "add-on symbology must be EAN-2 or EAN-5")
  let primary = encode(symbology, payload)
  if not primary.isOk: return primary
  let add = encode(addon, addonPayload)
  if not add.isOk:
    return encodeError(symbology, add.error.kind, add.error.message)
  var res = primary
  res.layout.supplements.add(BarcodeSupplement(
    symbology: add.symbology,
    modules: add.modules,
    layout: add.layout))
  res

const UniBarCodeVersion* = "1.0.0"









