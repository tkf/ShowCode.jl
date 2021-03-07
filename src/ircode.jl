"""
    c = @sc_ircode f(args...)

Julia SSA IR explore.

```julia
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

Since visualizers such as `c.cfg` and `c.cfg_only` work via the standard
`show` mechanism, they interoperable well with other packages like FileIO.jl
and DisplayAs.jl.

```julia
using FileIO
save("PATH/TO/IMAGE.png", c.cfg_only)
save("PATH/TO/IMAGE.svg", c.cfg_only)
save("PATH/TO/IMAGE.pdf", c.cfg_only)

using DisplayAs
c.cfg_only |> DisplayAs.SVG
```
"""
:(@sc_ircode)

struct IRCodeView <: AbstractCode
    ir::Core.Compiler.IRCode
    f::Any
    atype::Any
    rtype::Union{Type,Nothing}
    args::Any
    kwargs::Any
end

macro sc_ircode(args...)
    gen_call_with_extracted_types_and_kwargs(__module__, sc_ircode, args)
end

function sc_ircode(f, argument_type; kwargs...)
    @nospecialize
    # TODO: handle multiple returns?
    (ir, rtype), = code_ircode(f, argument_type; kwargs...)
    args = (f, argument_type)
    return IRCodeView(ir, f, argument_type, rtype, args, kwargs)
end

function sc_ircode(mi::Core.Compiler.MethodInstance; kwargs...)
    @nospecialize
    mth = mi.def
    if mth isa Method
        ftype = Base.tuple_type_head(mth.sig)
        if Base.issingletontype(ftype)
            f = ftype.instance
        else
            f = ftype  # ?
        end
        atype = Base.tuple_type_tail(mth.sig)
    else
        f = "f?"
        atype = "Tuple{?}"
    end

    args = (mi,)
    ir, rtype = code_ircode(args...; kwargs...)
    return IRCodeView(ir, f, atype, rtype, args, kwargs)
end

function Base.summary(io::IO, llvm::IRCodeView)
    @unpack f, atype = Fields(llvm)
    print(io, "IRCodeView of ", f, " with ", atype)
    return
end

function Base.show(io::IO, ::MIME"text/plain", ircv::IRCodeView)
    @unpack ir, rtype = Fields(ircv)
    summary(io, ircv)
    println(io)
    show(io, MIME"text/plain"(), ir)
    print(io, "⇒ ", rtype)
    println(io)
    return
end

Base.propertynames(::IRCodeView) = (
    :ir,
    :rtype,
    # explores:
    :llvm,
    :native,
    :intel,
    :att,
    # visualizers:
    :cfg,
    :cfg_only,
    :dom,
    :dom_only,
)

function Base.getproperty(ircv::IRCodeView, name::Symbol)
    @unpack args = Fields(ircv)
    if name === :llvm
        return sc_llvm(args...)
    elseif name === :native || name === :att
        return sc_native(args...)
    elseif name === :intel
        return sc_intel(args...)
    elseif name === :cfg
        return IRCodeCFGDot(ircv, true)
    elseif name === :cfg_only
        return IRCodeCFGDot(ircv, false)
    elseif name === :dom
        return IRCodeDomTree(ircv, true)
    elseif name === :dom_only
        return IRCodeDomTree(ircv, false)
    end
    return getfield(ircv, name)
end

abstract type AbstractLazyDot <: AbstractCode end

function dot_to_iobuffer(dot)
    io = IOBuffer()
    print_dot(io, dot)
    seekstart(io)
    return io
end

function run_dot(output::IO, input::IO, options)
    cmd = getcmd(:dot)
    cmd = `$cmd -Gfontname=monospace -Nfontname=monospace -Efontname=monospace $options`
    @debug "Run: $cmd"
    run(pipeline(cmd, stdout = output, stderr = stderr, stdin = input))
    return
end

# https://www.iana.org/assignments/media-types/text/vnd.graphviz
Base.show(io::IO, ::MIME"text/vnd.graphviz", dot::AbstractLazyDot) = print_dot(io, dot)

Base.show(io::IO, ::MIME"image/png", dot::AbstractLazyDot) =
    run_dot(io, dot_to_iobuffer(dot), `-Tpng`)
Base.show(io::IO, ::MIME"image/svg+xml", dot::AbstractLazyDot) =
    run_dot(io, dot_to_iobuffer(dot), `-Tsvg`)
Base.show(io::IO, ::MIME"application/pdf", dot::AbstractLazyDot) =
    run_dot(io, dot_to_iobuffer(dot), `-Tpdf`)

struct IRCodeCFGDot <: AbstractLazyDot
    ircv::IRCodeView
    include_code::Bool
end

function escape_dot_label(io::IO, str)
    for c in str
        if c in "\\{}<>|\"\n"
            # https://graphviz.org/doc/info/attrs.html#k:escString
            print(io, '\\', c)
        else
            print(io, c)
        end
    end
end

function Base.summary(io::IO, dot::IRCodeCFGDot)
    @unpack ircv = Fields(dot)
    @unpack f, atype = Fields(ircv)
    print(io, "CFG of $f on $atype")
end

print_dot(dot) = print_dot(stdout, dot)
function print_dot(io::IO, dot::IRCodeCFGDot)
    @unpack ircv, include_code = Fields(dot)
    @unpack ir = Fields(ircv)

    function bblabel(i)
        inst = ir.stmts.inst[ir.cfg.blocks[i].stmts[end]]
        if inst isa Core.ReturnNode
            if isdefined(inst, :val)
                return "$(i)⏎"
            else
                return "$(i)⚠"
            end
        end
        return string(i)
    end

    graphname = summary(dot)
    print(io, "digraph \"")
    escape_dot_label(io, graphname)
    println(io, "\" {")
    indented(args...) = print(io, "    ", args...)
    indented("label=\"")
    escape_dot_label(io, graphname)
    println(io, "\";")
    for (i, bb) in enumerate(ir.cfg.blocks)
        indented(i, " [shape=record")

        # Print code
        if include_code
            print(io, ", label=\"{$(bblabel(i)):\\l")
        else
            print(io, ", label=\"{$(bblabel(i))}\", tooltip=\"")
        end
        for s in bb.stmts
            escape_dot_label(io, string(ir.stmts.inst[s]))
            print(io, "\\l")
        end
        if include_code
            print(io, "}\"")
        else
            print(io, '"')
        end
        println(io, "];")

        # Print edges
        for s in bb.succs
            indented(i, " -> ", s, ";\n")
        end
    end
    println(io, '}')
end

struct IRCodeDomTree <: AbstractLazyDot
    ircv::IRCodeView
    include_code::Bool
    domtree::Core.Compiler.DomTree
end

function IRCodeDomTree(ircv::IRCodeView, include_code::Bool)
    @unpack ir = Fields(ircv)
    domtree = Core.Compiler.construct_domtree(ir.cfg.blocks)
    return IRCodeDomTree(ircv, include_code, domtree)
end

function Base.summary(io::IO, d::IRCodeDomTree)
    @unpack f, atype = Fields(Fields(d).ircv)
    print(io, "Dominator tree for $f on $atype")
end

# https://github.com/JuliaDebug/Cthulhu.jl/issues/26
AbstractTrees.treekind(::IRCodeDomTree) = AbstractTrees.IndexedTree()
AbstractTrees.childindices(d::IRCodeDomTree, i::Int) = d[i].children
AbstractTrees.childindices(::IRCodeDomTree, ::IRCodeDomTree) = (1,)
AbstractTrees.parentlinks(::IRCodeDomTree) = AbstractTrees.StoredParents()
AbstractTrees.printnode(io::IO, i::Int, ::IRCodeDomTree) = print(io, i)
Base.getindex(d::IRCodeDomTree, i) = Fields(d).domtree.nodes[i]

function Base.show(io::IO, ::MIME"text/plain", d::IRCodeDomTree)
    summary(io, d)
    println(io)
    AbstractTrees.print_tree(io, 1; roottree = d)
end

function print_dot(io::IO, dot::IRCodeDomTree)
    @unpack ircv, domtree, include_code = Fields(dot)
    @unpack ir = Fields(ircv)

    graphname = summary(dot)
    print(io, "digraph \"")
    escape_dot_label(io, graphname)
    println(io, "\" {")
    indented(args...) = print(io, "    ", args...)
    indented("label=\"")
    escape_dot_label(io, graphname)
    println(io, "\";")

    @assert length(domtree.nodes) == length(ir.cfg.blocks)
    for (i, (node, bb)) in enumerate(zip(domtree.nodes, ir.cfg.blocks))
        indented(i, " [shape=record")

        # Print code
        if include_code
            print(io, ", label=\"{$i:\\l")
        else
            print(io, ", label=\"{$i}\", tooltip=\"")
        end
        for s in bb.stmts
            escape_dot_label(io, string(ir.stmts.inst[s]))
            print(io, "\\l")
        end
        if include_code
            print(io, "}\"")
        else
            print(io, '"')
        end
        println(io, "];")

        # Print edges
        for s in node.children
            indented(i, " -> ", s, ";\n")
        end
    end
    println(io, '}')
end
