# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import pytest
import unibarcode


def test_version():
    assert unibarcode.version() == "1.0.0"
    assert unibarcode.__version__ == "1.0.0"
    assert unibarcode.abi_version() == 1


def test_encode_ean13():
    bc = unibarcode.encode("ean13", "978020137962")
    assert bc.is_ok
    assert bc.width == 95
    assert bc.height == 1
    assert bc.is_2d is False
    assert bc.symbology == 0


def test_encode_by_ordinal():
    bc = unibarcode.encode(0, "978020137962")
    assert bc.is_ok
    assert bc.width == 95


def test_encode_qr_is_2d():
    bc = unibarcode.encode("qr", "Hello")
    assert bc.is_ok
    assert bc.is_2d is True
    assert bc.width == 21
    assert bc.height == 21


def test_encode_invalid_payload():
    bc = unibarcode.encode("ean13", "abc")
    assert bc.is_ok is False
    assert bc.error != ""


def test_unknown_symbology_raises():
    with pytest.raises(ValueError):
        unibarcode.encode("nope", "x")


def test_render_png_signature():
    bc = unibarcode.encode("ean13", "978020137962")
    png = bc.render_png()
    assert png[:4] == b"\x89PNG"


def test_render_svg_prefix():
    bc = unibarcode.encode("ean13", "978020137962")
    svg = bc.render_svg()
    assert svg.startswith(b"<svg")
    assert b"</svg>" in svg
    assert b"<text" in svg  # HRI on by default


def test_render_svg_no_hri():
    bc = unibarcode.encode("ean13", "978020137962")
    opts = unibarcode.Options().show_hri(False)
    svg = bc.render_svg(opts)
    assert b"<text" not in svg


def test_options_and_color():
    opts = unibarcode.Options().module_size(3).bar_height(100)
    opts.foreground(unibarcode.Color.parse("#000000"))
    opts.background(unibarcode.Color.rgba(1.0, 1.0, 1.0, 1.0))
    bc = unibarcode.encode("ean13", "978020137962")
    png = bc.render_png(opts)
    assert png[:4] == b"\x89PNG"


def test_render_qr_png():
    bc = unibarcode.encode("qr", "Hello")
    png = bc.render_png()
    assert png[:4] == b"\x89PNG"
    assert len(png) > 0