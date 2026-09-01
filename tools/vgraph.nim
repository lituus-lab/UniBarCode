# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Enforces the dependency directions declared in vgraph.cfg (ADR-0001):
## no module imports a higher layer, no `requires` names an undeclared engine.
## Line-based scan of import/from/include, which covers the forms Nim sources
## actually use; a macro-built import would slip past it.
import std/[os, strformat, strutils]

const
  Cfg = "vgraph.cfg"
  Nimble = "UniBarCode.nimble"

proc section(name: string): seq[string] =
  ## Entries under `[name]`, in file order.
  var inside = false
  for line in readFile(Cfg).splitLines:
    let entry = line.split('#')[0].strip
    if entry.len == 0: continue
    if entry.startsWith('[') and entry.endsWith(']'):
      inside = entry[1 ..< ^1] == name
    elif inside:
      result.add entry

proc layerOf(path: string, order: seq[string]): int =
  ## Index of the layer owning `path`, or -1 when unconstrained.
  let parts = path.relativePath("src").split({DirSep, AltSep})
  for i, name in order:
    for part in parts:
      if part == name or part == name & ".nim":
        return i
  -1

proc layerOfModule(modulePath: string, order: seq[string]): int =
  ## Index of the layer owning an imported module path, or -1. Matches a layer
  ## name against any path component, so `UniBarCode/spaces/oklab` resolves to
  ## the `spaces` layer and a bare `c_api` to the `c_api` layer.
  let parts = modulePath.split({'/', '\\'})
  for i, name in order:
    for part in parts:
      if part == name or part == name & ".nim":
        return i
  -1

proc splitCommas(s: string): seq[string] =
  ## Split on commas at bracket depth 0, so `std/[os, strutils]` stays one
  ## token while `a, b` splits in two.
  var depth = 0
  var cur = ""
  for ch in s:
    if ch == '[': inc depth; cur.add(ch)
    elif ch == ']': dec depth; cur.add(ch)
    elif ch == ',' and depth == 0:
      if cur.strip.len > 0: result.add(cur)
      cur = ""
    else: cur.add(ch)
  if cur.strip.len > 0: result.add(cur)

proc expandBrackets(token: string): seq[string] =
  ## Expand a bracketed import group preserving the directory prefix:
  ## `UniBarCode/common/[types, digits]` -> `UniBarCode/common/types`,
  ## `UniBarCode/common/digits`. Depth-aware so nested brackets survive.
  let bi = token.find('[')
  if bi < 0:
    result.add(token.strip)
    return
  let prefix = token[0 ..< bi].strip
  var depth = 1
  var j = bi + 1
  var inner = ""
  while j < token.len and depth > 0:
    if token[j] == '[': inc depth; inner.add(token[j])
    elif token[j] == ']': dec depth
    else: inner.add(token[j])
    inc j
  for sub in splitCommas(inner):
    let m = sub.strip
    if m.len == 0: continue
    for expanded in expandBrackets(prefix & m):
      result.add(expanded)

iterator importedModules(path: string): string =
  ## Full slash-separated path of every module the file pulls in. Directory
  ## components are preserved so a directory layer (`spaces`) can be resolved.
  for raw in readFile(path).splitLines:
    let line = raw.split('#')[0].strip
    var body = ""
    if line.startsWith("import "): body = line[7 .. ^1]
    elif line.startsWith("include "): body = line[8 .. ^1]
    elif line.startsWith("from "): body = line[5 .. ^1].split(" import ")[0]
    else: continue
    # `std/[os, strutils]` -> `std/os`, `std/strutils` (prefix preserved);
    # top-level commas separate independent modules.
    for token in splitCommas(body):
      for module in expandBrackets(token):
        if module.len > 0:
          yield module

proc packageName(spec: string): string =
  ## `nim >= 2.0.0` -> nim; `https://host/user/NimContracts#branch` -> NimContracts.
  result = spec
  for sep in [" ", ">", "<", "=", "#"]:
    result = result.split(sep)[0]
  result = result.split({'/', '\\'})[^1]

iterator requiredPackages(path: string): string =
  ## Package name of every `requires` line.
  for raw in readFile(path).splitLines:
    let line = raw.strip
    if not line.startsWith("requires"): continue
    let a = line.find('"')
    let b = line.find('"', a + 1)
    if a >= 0 and b > a:
      let name = packageName(line[a + 1 ..< b])
      if name.len > 0:
        yield name

proc main() =
  if not fileExists(Cfg):
    quit(&"vgraph: {Cfg} not found", 1)
  let order = section("layers")

  var violations: seq[string]

  var checked = 0
  for path in walkDirRec("src"):
    if not path.endsWith(".nim"): continue
    let own = layerOf(path, order)
    if own < 0: continue
    inc checked
    for module in importedModules(path):
      let other = layerOfModule(module, order)
      if other > own:
        violations.add &"{path}: imports {module} ({order[other]}) from {order[own]}"

  # Family DAG: only engines listed under [engines] may appear in `requires`.
  let allowed = section("engines")
  var engines = 0
  if fileExists(Nimble):
    for package in requiredPackages(Nimble):
      if not package.startsWith("Uni"): continue
      inc engines
      if package notin allowed:
        violations.add &"{Nimble}: requires {package}, absent from [engines]"

  if violations.len > 0:
    echo "vgraph: violations found:"
    for v in violations:
      echo "  ", v
    quit(1)
  echo &"vgraph: {checked} modules respect {order.join(\" < \")}; " &
       &"{engines} engine deps declared"

main()
