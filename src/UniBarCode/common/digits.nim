# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniBarCode/common — shared digit-validation helpers for the numeric
## symbologies (EAN/UPC/ITF). Pure functions, no side effects.
import contracts

func isAllDigits*(s: string): bool {.inline.} =
  ## True iff `s` is non-empty and every char is ASCII '0'..'9'.
  if s.len == 0:
    return false
  for c in s:
    if c < '0' or c > '9':
      return false
  true

func digitValue*(c: char): int {.inline, contractual.} =
  ## Precondition: `c` in '0'..'9'.
  require:
    c >= '0' and c <= '9'
  body:
    ord(c) - ord('0')









