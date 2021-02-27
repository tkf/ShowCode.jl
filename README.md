# ShowCode: Show code in various ways

## Overview

ShowCode.jl provides interfaces like `@code_llvm` and `@code_native`:

```julia
c = @sc_ircode f(args...)
c = @sc_llvm f(args...)
c = @sc_native f(args...)
c = @sc_intel f(args...)
```

## Julia SSA IR

```julia
c = @sc_ircode f(args...)

c                  # view IR in the REPL
display(c)         # (ditto)

c.cfg              # control-flow graph (CFG) visualizer
c.cfg_only         # CFG without IR in node label
c.dom              # dominator tree visualizer
c.dom_only         # dominator tree without IR in node label
display(c.cfg)     # display CFG

c.llvm             # create LLVM IR explore
c.native           # create native code explore
c.att              # (ditto)
c.intel            # create native code explore in intel syntax
edit(c.native)
abspath(c.native)
```

... and so on; type `c.` + TAB to see the full list.

## LLVM IR

```julia
c = @sc_llvm f(args...)

c                  # view IR in the REPL
display(c)         # (ditto)
edit(c)            # open the IR in editor
print(c)           # print the IR
abspath(c)         # file path to the text containing the IR

c.native           # create native code explore
c.att              # (ditto)
c.intel            # create native code explore in intel syntax
eidt(c.native)
abspath(c.native)

c.cfg              # control-flow graph (CFG) visualizer
display(c.cfg)     # display CFG
edit(c.cfg.png)    # open PNG file in your editor
edit(c.cfg.svg)    # same for SVG
abspath(c.cfg.png) # file path to the PNG image
c.cfg_only
c.dom
```

... and so on.  Type `c.` + TAB to see all the list.  All `-dot-*`
options in
[`opt` command line interface](https://llvm.org/docs/Passes.html) are
supported.

## Native Code

```julia
c = @sc_native f(args...)
c = @sc_intel f(args...)  # short hand for syntax=:intel

c                  # view code in the REPL
display(c)         # (ditto)
edit(c)            # open the code in editor
print(c)           # print the code
abspath(c)         # file path to the text containing the code
```

## Post to [`godbolt.org`](https://godbolt.org/) (Compiler Explore)

**WARNING**: For code with non-trivial length, `post_godbolt(ce)` and `ce()`
*post* the code to godbolt.org and there is no way to delete the code as of
writing.

```julia
ce = (@sc_llvm ...).godbolt
ce = (@sc_native ...).godbolt

post_godbolt(ce)  # post the code to godbolt.org
string(ce)        # get godbolt URL
ce()              # open the URL in browser
```

## Cthulhu integration

During Cthulhu's descent session, you can press <kbd>b</kbd> to
"bookmark" the method you are browsing.  This is stored in the global
variable `Cthulhu.BOOKMARKS`.  This can be converted to code explores
by:

```julia
c = sc_ircode(Cthulhu.BOOKMARKS[end])
c = sc_llvm(Cthulhu.BOOKMARKS[end])
c = sc_native(Cthulhu.BOOKMARKS[end])
```
