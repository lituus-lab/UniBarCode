# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/common — shared EAN/UPC number-set patterns.
##
## The L (odd), G (even) and R (right) 7-module encodings for digits 0..9,
## plus the start/center/end guard patterns, shared by every EAN/UPC encoder
## (EAN-13, EAN-8, UPC-A via EAN-13, UPC-E, EAN-2, EAN-5). Reference:
## ISO/IEC 15420:2009 + GS1 General Specifications. Bit order is MSB first;
## `true` == bar (dark), `false` == space (light).

const
  LCodes* = [
    [false, false, false, true, true, false, true],                  # 0 0001101
    [false, false, true, true, false, false, true],                  # 1 0011001
    [false, false, true, false, false, true, true],                  # 2 0010011
    [false, true, true, true, true, false, true],                    # 3 0111101
    [false, true, false, false, false, true, true],                  # 4 0100011
    [false, true, true, false, false, false, true],                  # 5 0110001
    [false, true, false, true, true, true, true],                    # 6 0101111
    [false, true, true, true, false, true, true],                    # 7 0111011
    [false, true, true, false, true, true, true],                    # 8 0110111
    [false, false, false, true, false, true, true],                  # 9 0001011
  ]

  GCodes* = [
    [false, true, false, false, true, true, true],                   # 0 0100111
    [false, true, true, false, false, true, true],                   # 1 0110011
    [false, false, true, true, false, true, true],                   # 2 0011011
    [false, true, false, false, false, false, true],                 # 3 0100001
    [false, false, true, true, true, false, true],                   # 4 0011101
    [false, true, true, true, false, false, true],                   # 5 0111001
    [false, false, false, false, true, false, true],                 # 6 0000101
    [false, false, true, false, false, false, true],                 # 7 0010001
    [false, false, false, true, false, false, true],                 # 8 0001001
    [false, false, true, false, true, true, true],                   # 9 0010111
  ]

  RCodes* = [
    [true, true, true, false, false, true, false],                   # 0 1110010
    [true, true, false, false, true, true, false],                   # 1 1100110
    [true, true, false, true, true, false, false],                   # 2 1101100
    [true, false, false, false, false, true, false],                 # 3 1000010
    [true, false, true, true, true, false, false],                   # 4 1011100
    [true, false, false, true, true, true, false],                   # 5 1001110
    [true, false, true, false, false, false, false],                 # 6 1010000
    [true, false, false, false, true, false, false],                 # 7 1000100
    [true, false, false, true, false, false, false],                 # 8 1001000
    [true, true, true, false, true, false, false],                   # 9 1110100
  ]

  StartGuard* = [true, false, true]
  CenterGuard* = [false, true, false, true, false]
  EndGuard* = [true, false, true]

  ## EAN-2/EAN-5 add-on guard and inter-digit delineator (ISO/IEC 15420).
  ## Add-ons have no right guard; the delineator sits between adjacent digits.
  AddonGuard* = [true, false, true, true] # 1011
  AddonDelineator* = [false, true] # 01









