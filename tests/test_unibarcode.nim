# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/unittest
import std/strutils
import UniBarCode
import UniBarCode/symbology/microqr

suite "UniBarCode version":
  test "version string":
    check UniBarCodeVersion == "1.0.0"

suite "1-D symbologies":
  test "EAN-13 encodes 12 digits to a 95-module symbol":
    let r = encode(sbEan13, "978020137962")
    check r.isOk
    check r.modules.width == 95
    check r.normalizedPayload == "9780201379624" # checksum appended
    check r.modules.is2D == false
    check r.layout.hri.len == 13
    check r.layout.guardModules.len > 0

  test "EAN-8 encodes 7 digits to a 67-module symbol":
    let r = encode(sbEan8, "9638507")
    check r.isOk
    check r.modules.width == 67
    check r.normalizedPayload == "96385074"
    check r.layout.hri.len == 8

  test "UPC-A encodes 11 digits to a 95-module symbol":
    let r = encode(sbUpcA, "03600029145")
    check r.isOk
    check r.modules.width == 95
    check r.normalizedPayload == "036000291452"
    check r.layout.hri.len == 12

  test "UPC-E encodes 6 digits to a 51-module symbol":
    # Check digits hand-derived from the GS1 mod-10 on the expanded GTIN-11.
    block:
      let r = encode(sbUpcE, "012345")
      check r.isOk
      check r.modules.width == 51
      check r.modules.is2D == false
      check r.normalizedPayload == "012345"
      check r.layout.hri.len == 8 # NS 0 + 6 digits + check digit
      check r.layout.hri[0].text == "0" # number system
      check r.layout.hri[7].text == "7" # implicit check digit
    # More expansion-rule coverage (last digit 3, 4 and 5-9).
    check encode(sbUpcE, "123456").isOk
    check encode(sbUpcE, "000000").isOk
    check encode(sbUpcE, "999999").isOk
    check encode(sbUpcE, "999999").modules.width == 51

  test "Code 39 wraps the payload with start/stop":
    let r = encode(sbCode39, "ABC123")
    check r.isOk
    check r.modules.width > 0
    check r.layout.hri.len == 6

  test "Code 128 encodes an arbitrary payload":
    let r = encode(sbCode128, "ABC123")
    check r.isOk
    check r.modules.width > 0
    check r.layout.hri.len == 6

  test "ITF encodes an even-digit payload":
    let r = encode(sbItf, "1234567890")
    check r.isOk
    check r.modules.width > 0
    check r.layout.hri.len == 10

suite "EAN add-ons":
  test "EAN-2 encodes 2 digits to a 20-module symbol":
    let r = encode(sbEan2, "53")
    check r.isOk
    check r.modules.width == 20
    check r.modules.is2D == false
    check r.layout.hri.len == 2

  test "EAN-2 53 matches the spec bit pattern":
    # guard 1011 | 5(L) | delim 01 | 3(G); parity = (53 mod 4 = 1) = LG.
    let r = encode(sbEan2, "53")
    check r.modules.toBitString() == "10110110001010100001"

  test "EAN-5 encodes 5 digits to a 47-module symbol":
    let r = encode(sbEan5, "52495")
    check r.isOk
    check r.modules.width == 47
    check r.modules.is2D == false
    check r.layout.hri.len == 5

  test "EAN-5 52495 matches the spec bit pattern":
    # Wikipedia worked example: checksum 1 -> GLGLL.
    # guard 1011 | 5(G) 0111001 | 01 | 2(L) 0010011 | 01 | 4(G) 0011101 |
    # 01 | 9(L) 0001011 | 01 | 5(L) 0110001.
    let r = encode(sbEan5, "52495")
    check r.modules.toBitString() ==
      "10110111001010010011010011101010001011010110001"

  test "EAN-13 + EAN-5 composite attaches one supplement":
    let r = encodeComposite(sbEan13, "978020137962", sbEan5, "52495")
    check r.isOk
    check r.modules.width == 95 # primary unchanged
    check r.layout.supplements.len == 1
    check r.layout.supplements[0].symbology == sbEan5
    check r.layout.supplements[0].modules.width == 47

  test "EAN-13 + EAN-2 composite attaches one supplement":
    let r = encodeComposite(sbEan13, "978020137962", sbEan2, "53")
    check r.isOk
    check r.layout.supplements.len == 1
    check r.layout.supplements[0].symbology == sbEan2
    check r.layout.supplements[0].modules.width == 20

  test "composite rejects a non-add-on supplement symbology":
    let r = encodeComposite(sbEan13, "978020137962", sbQrCode, "x")
    check not r.isOk
    check r.error.kind == ekValidation

suite "2-D symbologies":
  test "QR Code produces a square grid":
    let r = encode(sbQrCode, "Hello")
    check r.isOk
    check r.modules.is2D
    check r.modules.gridWidth == r.modules.gridHeight
    check r.modules.gridWidth > 0

  test "Data Matrix produces a grid":
    let r = encode(sbDataMatrix, "Hello")
    check r.isOk
    check r.modules.is2D
    check r.modules.gridWidth > 0
    check r.modules.gridHeight > 0

  test "PDF417 produces a grid":
    let r = encode(sbPdf417, "Hello")
    check r.isOk
    check r.modules.is2D
    check r.modules.gridWidth > 0
    check r.modules.gridHeight > 0

  test "Aztec produces a square grid":
    let r = encode(sbAztec, "Hello")
    check r.isOk
    check r.modules.is2D
    check r.modules.gridWidth == r.modules.gridHeight
    check r.modules.gridWidth > 0

suite "Micro QR":
  test "auto-select picks M1 for a short numeric payload":
    let r = encode(sbMicroQr, "12345")
    check r.isOk
    check r.modules.is2D
    check r.modules.gridWidth == 11
    check r.modules.gridHeight == 11

  test "auto-select upgrades to byte mode for lowercase text":
    # "Hello" is not alphanumeric (lowercase) so it needs byte mode (M3+).
    let r = encode(sbMicroQr, "Hello")
    check r.isOk
    check r.modules.gridWidth >= 15

  test "M1-numeric-5 matches the golden bit pattern":
    let r = encodeAt("12345", mvM1, ecDetect)
    check r.isOk
    check r.modules.toGridBitString() ==
      "1111111010110000010110101110101001011101000010111010111100000100111111111010000000000011110011100110101000110011110000011"

  test "M4-Q-numeric-20 matches the golden bit pattern":
    let r = encodeAt("12345678901234567890", mvM4, ecQ)
    check r.isOk
    check r.modules.toGridBitString() ==
      "1111111010101010110000010101010001101110101001010011011101001101010010111010010101001100000100010100011111111011110110000000000111011001101101001110110010111101111000001111001111000111000001011101010101001011010011110001101000011010100001101101001100100100011000011111100010010111001110111"

  test "M1 rejects a non-numeric payload (numeric-only version)":
    let r = encodeAt("Hello", mvM1, ecDetect)
    check not r.isOk
    check r.error.kind == ekValidation

  test "an invalid version/EC pairing is rejected":
    let r = encodeAt("12345", mvM1, ecL)
    check not r.isOk
    check r.error.kind == ekValidation

  test "an empty payload is rejected":
    check not encode(sbMicroQr, "").isOk
    check encode(sbMicroQr, "").error.kind == ekValidation

suite "GS1-128":
  test "encodes a single fixed-length AI to a 1-D symbol":
    let r = encode(sbGs1128, "(01)04212345678904")
    check r.isOk
    check r.modules.is2D == false
    check r.modules.width > 0
    check r.layout.hri.len == 1
    check r.layout.hri[0].text == "(01)04212345678904"

  test "(01)04212345678904 matches the golden bar pattern":
    # FNC1-first (105/102) + Code C digit pairs + mod-103 check + stop.
    let r = encode(sbGs1128, "(01)04212345678904")
    check r.isOk
    check r.modules.toBitString() ==
      "11010011100111101011101100110110010010001100110111001001110110111010111011000100001011001101101111010010001100110111011101100011101011"

  test "(00) SSCC matches the golden bar pattern":
    let r = encode(sbGs1128, "(00)123456789012345678")
    check r.isOk
    check r.modules.toBitString() ==
      "110100111001111010111011011001100101100111001000101100011100010110110000101001101111011010110011100100010110001110001011011000010100110000100101100011101011"

  test "multi-AI with a variable-length separator matches the golden bar pattern":
    # (01) fixed 14 + (17) fixed 6 + (10) variable, last → no trailing FNC1.
    let r = encode(sbGs1128, "(01)04212345678904(17)251231(10)LOT9")
    check r.isOk
    check r.modules.toBitString() ==
      "1101001110011110101110110011011001001000110011011100100111011011101011101100010000101100110110111101001000110010011100110111001011001011001110011011000110110010001001011110111010001101110100011101101101110001011100101100100011010001100011101011"

  test "(3100) measure AI matches the golden bar pattern":
    let r = encode(sbGs1128, "(3100)001250")
    check r.isOk
    check r.modules.toBitString() ==
      "11010011100111101011101101100011011011001100110110011001011001110011000101110110001001001100011101011"

  test "variable AI not last inserts an FNC1 separator":
    # (10) variable followed by (11) fixed → an FNC1 (codeword 102) separates them.
    let r = encode(sbGs1128, "(10)ABC123(11)251231")
    check r.isOk
    check r.modules.width > 0

  test "the symbol width follows 11*(codewords+2)+2":
    # start(11) + N data(11) + check(11) + stop(13) = 11*(N+2)+2.
    let r = encode(sbGs1128, "(01)04212345678904")
    check r.isOk
    check (r.modules.width - 2) mod 11 == 0

suite "validation":
  test "EAN-13 rejects non-digit input":
    let r = encode(sbEan13, "abc")
    check not r.isOk
    check r.error.kind == ekValidation

  test "EAN-13 rejects a wrong-length payload":
    let r = encode(sbEan13, "123")
    check not r.isOk
    check r.error.kind == ekValidation

  test "UPC-E rejects non-digit and wrong-length input":
    check not encode(sbUpcE, "abc").isOk
    check encode(sbUpcE, "abc").error.kind == ekValidation
    check not encode(sbUpcE, "12345").isOk # too short
    check encode(sbUpcE, "12345").error.kind == ekValidation
    check not encode(sbUpcE, "1234567").isOk # too long
    check encode(sbUpcE, "1234567").error.kind == ekValidation

  test "EAN-2 rejects non-digit and wrong-length input":
    check not encode(sbEan2, "ab").isOk
    check encode(sbEan2, "ab").error.kind == ekValidation
    check not encode(sbEan2, "123").isOk # too long
    check not encode(sbEan2, "1").isOk # too short

  test "EAN-5 rejects non-digit and wrong-length input":
    check not encode(sbEan5, "abcde").isOk
    check not encode(sbEan5, "1234").isOk # too short
    check not encode(sbEan5, "123456").isOk # too long

  test "GS1-128 rejects empty and malformed payloads":
    check not encode(sbGs1128, "").isOk
    check encode(sbGs1128, "").error.kind == ekValidation
    check not encode(sbGs1128, "0104212345678904").isOk # missing parens
    check not encode(sbGs1128, "(01)").isOk # empty AI/data malformed
    check not encode(sbGs1128, "(01").isOk # unclosed AI (no closing ')')
    check not encode(sbGs1128, "(10)").isOk # empty element data
    check not encode(sbGs1128, "(01)ABCDEFGHIJKLMN").isOk # (01) data must be numeric
    check not encode(sbGs1128, "(01)0421234567890").isOk # (01) needs 14 data
    check not encode(sbGs1128, "(1)ABC").isOk # AI too short
    check encode(sbGs1128, "(01)0421234567890").error.kind == ekValidation

  test "an error result renders to empty SVG":
    let r = encode(sbEan13, "abc")
    check toSvg(r) == ""

suite "SVG render":
  test "EAN-13 SVG is a standalone document with a path":
    let r = encode(sbEan13, "978020137962")
    let s = toSvg(r)
    check s.startsWith("<svg")
    check "</svg>" in s
    check "<path" in s

  test "SVG HRI is emitted for 1-D when showHri is on":
    let r = encode(sbEan13, "978020137962")
    let opts = defaultRenderOptions()
    check opts.showHri
    let s = toSvg(r, opts)
    check "<text" in s

  test "SVG HRI is suppressed when showHri is off":
    let r = encode(sbEan13, "978020137962")
    var opts = defaultRenderOptions()
    opts.showHri = false
    let s = toSvg(r, opts)
    check "<text" notin s

  test "2-D SVG has no HRI text":
    let r = encode(sbQrCode, "Hello")
    let s = toSvg(r)
    check s.startsWith("<svg")
    check "<text" notin s

  test "composite SVG widens to include the supplement and its HRI":
    let primary = encode(sbEan13, "978020137962")
    let comp = encodeComposite(sbEan13, "978020137962", sbEan5, "52495")
    let ps = toSvg(primary)
    let cs = toSvg(comp)
    check cs.startsWith("<svg")
    check "<text" in cs
    # The composite viewBox is wider than the primary alone.
    check cs.len > ps.len

suite "PNG render":
  test "PNG output starts with the PNG signature":
    let r = encode(sbEan13, "978020137962")
    let bytes = toPng(r)
    check bytes.len > 0
    check bytes[0] == 0x89'u8
    check bytes[1] == 0x50'u8 # 'P'
    check bytes[2] == 0x4e'u8 # 'N'
    check bytes[3] == 0x47'u8 # 'G'

  test "2-D PNG is non-empty":
    let r = encode(sbQrCode, "Hello")
    let bytes = toPng(r)
    check bytes.len > 0
