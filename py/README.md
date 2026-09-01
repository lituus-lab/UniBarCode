<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# unibarcode — Python binding

```bash
nimble pyLib                                    # native lib for this platform
(cd py && python3 setup.py build_ext --inplace) # build the Cython extension
(cd py && python3 -m pytest -q)                 # test
```

`nimble pyLib` builds the shared lib on Linux/macOS and the MSVC static lib on
Windows. The commands above assume a POSIX shell (`bash`/`zsh`); on Windows run
them in Git Bash or WSL — `python3`, `&&`, and the `(cd …)` subshell are not
cmd.exe/PowerShell syntax.

```python
import unibarcode
unibarcode.version()       # "1.0.0"
unibarcode.encode("ean13", "978020137962")  # -> Barcode
```
