<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# The Book

A nimibook table of contents: `index.nim` opens it, and `cleanroom.nim`,
`encode.nim`, `render.nim` and `surfaces.nim` are the chapters. Every code
block is compiled and run when the book is built, so prose that outlives its
API breaks the build rather than quietly misleading a reader.

`build/unigate book` builds the book alone; `build/unigate docs` builds it
together with the API reference `nim doc` generates, into `pages/`. Through the
gate, never `nimble book` directly: nimble exits 0 even when an `exec` inside a
task fails.
