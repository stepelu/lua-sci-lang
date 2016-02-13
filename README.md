SciLua-Lang: Syntax extensions to LuaJIT for scientific computing
=================================================================

Based on the [LuaJIT Language Toolkit](https://github.com/franko/luajit-lang-toolkit) this executable introduces extensions to the LuaJIT syntax for algebra operations.

## Features

- algebra expressions constructed via empty bracket `[]` indexing
- element-wise operations via plain Lua operators (`+-*/^%`)
- matrix multiplication via `**`
- matrix exponentiation via `^^`
- transposition via `` ` ``
- efficient implementation minimizes required allocations and loops
- support for assignments

```lua
-- Replicate rand_mat_stat from Julia's benchmark suite:
local function randmatstat(t)
  local n = 5
  local v, w = alg.vec(t), alg.vec(t)
  for i=1,t do
      local a, b, c, d = randn(n, n), randn(n, n), randn(n, n), randn(n, n)
      local P = alg.join(a..b..c..d)
      local Q = alg.join(a..b, c..d)
      v[i] = alg.trace((P[]`**P[])^^4) -- Matrix transpose, product and power.
      w[i] = alg.trace((Q[]`**Q[])^^4) -- Matrix transpose, product and power.
  end
  return sqrt(stat.var(v))/stat.mean(v), sqrt(stat.var(w))/stat.mean(w)
end
```

## Install

This module is included in the [ULua](http://ulua.io) distribution, to install it use:
```
upkg add sci-lang
```

Alternatively, manually install this module making sure that all dependencies listed in the `require` section of [`__meta.lua`](__meta.lua) are installed as well (dependencies starting with `clib_` are standard C dynamic libraries).

## Documentation

Refer to the [official documentation](http://scilua.org).