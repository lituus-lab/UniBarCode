# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# UniBarCode — multi-symbology barcode encoder for the lituus-lab Uni* family.

version       = "1.0.0"
author        = "lituus-lab"
description   = "Multi-symbology barcode encoder (Nim + C-ABI + Python) for the lituus-lab Uni* family"
license       = "Apache-2.0"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "https://github.com/lbartoletti/NimContracts#main"
# The three engines this repo compiles against. Declared, not reached by a
# relative path into a sibling checkout: nothing else installs them, and CI
# checks out one repository.
requires "https://github.com/lituus-lab/UniVector#main"
requires "https://github.com/lituus-lab/UniImage#main"
requires "https://github.com/lituus-lab/UniColor#main"

# nimble 0.22 exits 0 even when an `exec` inside a task fails, so a task's exit
# code says nothing about whether its body ran. Each task writes a marker as
# its last statement; `tools/gate.nim` removes the marker, runs the task, and
# fails if it is not there afterwards. `nimble canary` proves the gate still
# bites -- if that one ever passes, every other green result is worthless.
const gateExe =
  when defined(windows): "build/unigate.exe" else: "build/unigate"

template done(task: string) =
  mkDir "build/.gate"
  writeFile("build/.gate/" & task & ".ok", "")

proc gate(task: string): string =
  ## `exec gate("test")` -- builds the tool on first use.
  if not fileExists(gateExe):
    exec "nim c --hints:off -o:" & gateExe & " tools/gate.nim"
  gateExe & " " & task

task canary, "Must fail: proves the gate still catches a broken build":
  # No `done` here on purpose: the exec below raises, so the marker is never
  # written and the gate reports the failure nimble swallowed.
  exec "nim c -r --hints:off --path:src -o:build/canary tests/canary_broken.nim"

task lint, "Fail if nimpretty would reformat a source":
  exec "nim c -r --hints:off -o:build/lint_tool tools/lint.nim"
  done "lint"

task checkVGraph, "Fail on an import that climbs the layers in vgraph.cfg":
  exec "nim c -r --hints:off -o:build/vgraph_tool tools/vgraph.nim"
  done "checkVGraph"

const bookDeps = [
  "https://github.com/pietroppeter/nimib#v0.4.1",
  "https://github.com/pietroppeter/nimibook#v0.4.0",
  "https://github.com/lituus-lab/lituus-theme#v0.2.0",
]
taskRequires "docsDeps", bookDeps[0], bookDeps[1], bookDeps[2]
taskRequires "book", bookDeps[0], bookDeps[1], bookDeps[2]
taskRequires "docs", bookDeps[0], bookDeps[1], bookDeps[2]

task docsDeps, "Install the docs toolchain (nimib + nimibook + theme)":
  echo "nimib, nimibook and lituus-theme installed."
  done "docsDeps"

task bookInit, "Scaffold a chapter added to the table of contents":
  withDir "book":
    exec "nim c -r --hints:off -o:../build/nbook nbook.nim init"
  done "bookInit"

task book, "Build the multi-chapter book (needs nimib + nimibook)":
  withDir "book":
    exec "nim c -r --hints:off -o:../build/nbook nbook.nim clean"
    # `init` before `build`, on every run: it is what creates `__site/assets`,
    # which is not tracked, so a fresh clone has none and every page ships
    # referencing a stylesheet and a script that are not there.
    exec "nim c -r --hints:off -o:../build/nbook nbook.nim init"
    exec "nim c -r --hints:off -o:../build/nbook nbook.nim build"
  done "book"

task docs, "API reference + book into pages/ — what CI publishes":
  rmDir "pages"
  exec gate("book")
  cpDir "book/__site", "pages"
  rmFile "pages/book.json"
  # `--path:src` so the umbrella's own imports resolve against this checkout
  # rather than falling through to whatever version is installed.
  exec "nim doc --index:on --outdir:pages/api --project --hints:off " &
       "--path:src src/UniBarCode.nim"
  # ...and the reference wears the same theme. `nim doc` has no stylesheet
  # option, so the palette is appended to the one it just wrote.
  exec "nim c -r --hints:off --outdir:build tools/theme_api.nim " &
       "pages/api/nimdoc.out.css"
  done "docs"

task test, "Nim tests (debug, contracts active)":
  exec "nim c -r --path:src -o:build/test_unibarcode tests/test_unibarcode.nim"
  exec "nim c -r --path:src -o:build/test_version tests/test_version.nim"
  done "test"

task testRelease, "Nim tests (release, contracts compiled away)":
  exec "nim c -r -d:release --path:src -o:build/test_unibarcode_rel tests/test_unibarcode.nim"
  exec "nim c -r -d:release --path:src -o:build/test_version_rel tests/test_version.nim"
  done "testRelease"

task testCi, "Nim tests (CI subset, debug)":
  exec "nim c -r --path:src -o:build/test_unibarcode tests/test_unibarcode.nim"
  exec "nim c -r --path:src -o:build/test_version tests/test_version.nim"
  done "testCi"

task testCiRelease, "Nim tests (CI subset, release)":
  exec "nim c -r -d:release --path:src -o:build/test_unibarcode_rel tests/test_unibarcode.nim"
  exec "nim c -r -d:release --path:src -o:build/test_version_rel tests/test_version.nim"
  done "testCiRelease"

task testAll, "debug + release + C ABI":
  exec gate("test")
  exec gate("testRelease")
  exec gate("ctest")
  done "testAll"

task example, "Nim demo":
  exec "nim c -r --path:src -o:build/demo examples/demo.nim"
  done "example"

task unibarcode, "CLI: encode a payload to PNG/SVG (run with --help for flags)":
  # `--help` and not a bare run: with no arguments the CLI is being misused and
  # says so with a non-zero exit, which is correct behaviour and a failed task.
  exec "nim c -r --path:src -o:build/unibarcode bin/unibarcode_cli.nim --help"
  done "unibarcode"

task wasm, "Compile the C ABI to WebAssembly via Emscripten (needs emsdk) -> dist/":
  exec "bash scripts/build_wasm.sh"
  done "wasm"

# Nim takes `-o:` literally and appends no platform extension.
const
  sharedLib =
    when defined(windows): "libUniBarCode.dll"
    elif defined(macosx): "libUniBarCode.dylib"
    else: "libUniBarCode.so"
  staticLib = "libUniBarCode.a"  # MinGW `ar` on Windows, so `.a` everywhere.

  # @rpath install_name, so the copy bundled in the wheel is found at import.
  macArgs =
    when defined(macosx): " --passL:\"-Wl,-install_name,@rpath/" & sharedLib & "\""
    else: ""

task clib, "C shared library":
  exec "nim c --app:lib -d:ubcNoAutoInit --noMain --mm:arc -d:release -o:" & sharedLib & macArgs &
       " src/UniBarCode/c_api.nim"
  done "clib"

task clibStatic, "C static library":
  exec "nim c --app:staticlib -d:ubcNoAutoInit --noMain --mm:arc -d:release -o:" & staticLib &
       " src/UniBarCode/c_api.nim"
  done "clibStatic"

task clibMsvc, "C static library, MSVC ABI (Windows Python extension)":
  # CPython on Windows is MSVC-built and cannot link MinGW output.
  when defined(windows):
    exec "nim c --cc:vcc --app:staticlib -d:ubcNoAutoInit --noMain --mm:arc -d:release" &
         " -o:UniBarCode.lib src/UniBarCode/c_api.nim"
  else:
    # `vccexe` exists only on Windows. Saying so beats failing: the task is
    # part of the suite everywhere, and there is no artifact to produce here.
    echo "clibMsvc: Windows-only task; no artifact on this host."
  done "clibMsvc"

# Nim's MinGW toolchain names it mingw32-make.
let makeExe = if findExe("mingw32-make").len > 0: "mingw32-make" else: "make"

# `make -C`, not `cd dir && make`: nimble's exec runs no shell on Windows.
task ctest, "C ABI tests":
  exec gate("clibStatic")
  exec makeExe & " -C tests/c"
  done "ctest"

task cexample, "C demo":
  exec gate("clibStatic")
  exec makeExe & " -C examples/c"
  done "cexample"

task pyDeps, "Install Python build deps (setuptools, Cython, pytest) if missing":
  exec "python3 -m pip install --break-system-packages --quiet setuptools wheel \"Cython>=3.0.0\" pytest"
  # Ubuntu ships a setuptools that predates PEP 639 and cannot parse the SPDX
  # licence pyproject.toml declares. pip refuses to uninstall a distro- or
  # brew-managed package, so install over it rather than --upgrade it.
  # packaging comes with it: setuptools 77 reads packaging.licenses, which the
  # distro's older copy does not have, and it shadows the vendored one.
  exec "python3 -m pip install --break-system-packages --quiet --ignore-installed \"setuptools>=77\" \"packaging>=24.2\""
  done "pyDeps"

# The extension links the vcc static lib on Windows, the shared lib elsewhere.
task pyLib, "Build the library the Python extension links against":
  when defined(windows):
    exec gate("clibMsvc")
  else:
    exec gate("clib")
  done "pyLib"

task pyNotebookDeps, "Install notebook build deps (nbformat, nbclient, ipykernel) if missing":
  exec "python3 -m pip install --break-system-packages --quiet nbformat nbclient ipykernel"
  done "pyNotebookDeps"

task buildCython, "Cython extension in-place":
  exec gate("pyLib")
  exec gate("pyDeps")
  # nimscript `cd` (lib/system/nimscript.nim) changes the VM cwd for the next
  # exec without a shell, so the task works under nimble's no-shell exec on Windows.
  cd "py"
  exec "python3 setup.py build_ext --inplace"
  cd ".."
  done "buildCython"

task pyTest, "Cython extension + pytest":
  exec gate("buildCython")
  cd "py"
  exec "python3 -m pytest -q"
  cd ".."
  done "pyTest"

task pyWheel, "wheel":
  exec gate("pyLib")
  exec gate("pyDeps")
  cd "py"
  exec "python3 setup.py bdist_wheel"
  cd ".."
  done "pyWheel"

task coverage, "LCOV + HTML coverage report for the Nim sources (needs lcov)":
  # gcov and lcov driven directly, no coco. Linux and macOS only.
  # --debugger:native attributes lines to the .nim sources, not the generated C.
  # --include keeps stdlib out of the capture, where lcov 2.x aborts on Nim's
  # codegen.
  # `mismatch` is the one suppression, and it is not optional: lcov 2.x checks
  # its own end line for a function against gcov's, and Nim's generated
  # destructors disagree -- a closure environment, a seq, NimContracts'
  # PostConditionDefect. Removing one only advances lcov to the next, so there
  # is no source-level fix. Every other lcov error still fails the build.
  let cache = "build/covcache"
  rmDir cache
  rmDir "coverage"
  exec "nim c --path:src --nimcache:" & cache &
       " --debugger:native --passC:--coverage --passL:--coverage" &
       " -o:build/test_coverage tests/test_unibarcode.nim"
  exec "./build/test_coverage"
  exec "lcov --capture --directory " & cache & " --base-directory ." &
       " --include \"*/src/UniBarCode/*\" --output-file lcov.info --quiet --ignore-errors mismatch"
  # gcov can attribute a final generated expression to EOF + 1; `range` is
  # genhtml's filter for that compiler artefact, and it wants the matching
  # category allowance before applying it. lcov 2.0 -- the one ubuntu-latest
  # installs -- rejects `range` as a category outright, and does not make the
  # check that needs it; 2.5 does both. Measured on each, not assumed.
  let genhtmlRange =
    if gorgeEx("genhtml --version").output.contains("LCOV version 2.0"): ""
    else: " --filter range --ignore-errors range"
  exec "genhtml lcov.info" & genhtmlRange &
       " --output-directory coverage --legend --quiet"
  exec "lcov --summary lcov.info"
  done "coverage"
