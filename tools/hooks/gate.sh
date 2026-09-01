#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# Run a nimble task through the failure gate, compiling the gate first when
# there is none. build/ is not tracked, so on a fresh clone the hooks pointed
# at build/unigate directly and the first commit died on a missing executable.
set -euo pipefail
GATE=build/unigate
[ "${OS:-}" = Windows_NT ] && GATE=build/unigate.exe
[ -x "$GATE" ] || nim c --hints:off -o:"$GATE" tools/gate.nim
exec "$GATE" "$@"
