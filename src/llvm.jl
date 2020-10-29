"""
    c = CodeX.@llvm f(args...)

LLVM IR explore.

```julia
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
# ... and so on; type `c.` + TAB to see all the list
```
"""
:(@llvm)

"""
    CodeX.from_llvm(ir::AbstractString)

Construct a LLVM IR explore from a snippet of LLVM IR.

For example,

```julia
a = CodeX.@llvm dump_module=true f(...)
b = CodeX.from_llvm(string(a))
```

should be roughly equivalent.
"""
CodeX.from_llvm(ir::AbstractString) =
    CodeLLVM(String(ir), true, ("f?", "Tuple{?}"), nothing)

struct CodeLLVM <: AbstractCode
    ir::String
    user_dump_module::Bool
    args::Any
    kwargs::Any
    cache::Dict{Symbol,Any}
    abspath::Base.RefValue{Union{Nothing,String}}
end

CodeLLVM(ir, user_dump_module, args, kwargs) = CodeLLVM(
    ir,
    user_dump_module,
    args,
    kwargs,
    Dict{Symbol,Any}(),
    Ref{Union{Nothing,String}}(nothing),
)

Base.string(llvm::CodeLLVM) = Fields(llvm).ir
Base.print(io::IO, llvm::CodeLLVM) = print(io, string(llvm))

function Base.abspath(llvm::CodeLLVM)
    p = Fields(llvm).abspath[]
    p === nothing || return p
    p = joinpath(mktempdir(prefix = "jl_codeviz_"), "code.ll")
    write(p, string(llvm))
    Fields(llvm).abspath[] = p
    return p
end

macro llvm(args...)
    gen_call_with_extracted_types_and_kwargs(__module__, CodeX.llvm, args)
end

function CodeX.llvm(args...; dump_module = false, kwargs...)
    @nospecialize
    ir = sprint() do io
        @nospecialize
        code_llvm(io, args...; dump_module = true, kwargs...)
    end
    return CodeLLVM(ir, dump_module, args, kwargs)
end

function Base.summary(io::IO, llvm::CodeLLVM)
    f, t = Fields(llvm).args
    print(io, "CodeLLVM of ", f, " with ", t)
    return
end

function Base.show(io::IO, ::MIME"text/plain", llvm::CodeLLVM)
    @unpack ir, user_dump_module = Fields(llvm)
    summary(io, llvm)
    println(io)
    if !user_dump_module
        ir = sprint(print_main_llvm_ir, ir)
    end
    if get(io, :color, false)
        print_llvm(io, ir)
    else
        print(io, ir)
    end
    return
end

function print_main_llvm_ir(io, ir)
    input = IOBuffer(ir)
    for line in eachline(input)
        if startswith(line, "define")
            println(io, line)
            for line in eachline(input)
                println(io, line)
                if startswith(line, "}")
                    return
                end
            end
        end
    end
end

Base.propertynames(llvm::CodeLLVM) = (
    # conversions to `CodeNative`:
    :native,
    :intel,
    :att,
    # `-dot-*` passes https://llvm.org/docs/Passes.html
    :callgraph,
    :cfg,
    :cfg_only,
    :dom,
    :dom_only,
    :postdom,
    :postdom_only,
    # misc
    :godbolt,
)

# TODO: make getproperty I/O-free; just return a lazy object
Base.getproperty(llvm::CodeLLVM, name::Symbol) =
    get!(Fields(llvm).cache, name) do
        if name in (:native, :intel, :att)
            syntax = name == :native ? :att : name
            CodeNative(llvm, syntax)
        elseif name === :godbolt
            Godbolt(llvm)
        else
            run_opt_dot(llvm, name)
        end
    end::Union{LLVMDot,CodeNative,Godbolt}

function run_opt_dot(llvm::CodeLLVM, name)
    ir = string(llvm)
    dotarg = "-dot-" * replace(string(name), "_" => "-")  # e.g., -dot-cfg
    dumpdir = mktempdir(prefix = "jl_codeviz_")
    cmd = getcmd(:opt)
    cmd = cmd0 = `$cmd $dotarg -`
    cmd = setenv(cmd0; dir = dumpdir)
    # TODO: don't hide handle error messages (if any)

    write_silently(cmd, ir)

    return LLVMDot(llvm, cmd, dumpdir)
end

abstract type AbstractLLVMDot <: AbstractCode end
AbstractLLVMDot(dot::AbstractLLVMDot) = dot
Base.getproperty(dot::AbstractLLVMDot, ext::Symbol) = LLVMDotImage(dot, ".$ext")
dotpath(dot) = abspath(AbstractLLVMDot(dot))
Base.basename(dot::AbstractLLVMDot) = basename(abspath(dot))

struct LLVMDot <: AbstractLLVMDot
    llvm::CodeLLVM
    cmd::Cmd
    dumpdir::String
end

Base.dirname(dot::LLVMDot) = Fields(dot).dumpdir

function Base.abspath(dot::LLVMDot)
    candidates = map(abspath, collect(dot))
    if length(candidates) > 1
        @debug "Ignoring some dot files." candidates[2:end]
    end
    return candidates[1]
end

struct SubLLVMDot <: AbstractLLVMDot
    dot::LLVMDot
    abspath::String
end

Base.abspath(dot::SubLLVMDot) = Fields(dot).abspath
dotpath(dot::SubLLVMDot) = abspath(dot)

function Base.collect(dot::LLVMDot)
    alldots = [
        SubLLVMDot(dot, p)
        for
        p in readdir(dirname(dot); join = true) if
        match(r".*\.jfptr_.*", basename(p)) === nothing && endswith(p, ".dot")
    ]
    sort!(alldots; by = length ∘ abspath)
    return alldots
end

Base.keys(dot::LLVMDot) = keys(pairs(dot))
Base.values(dot::LLVMDot) = values(pairs(dot))

function Base.pairs(dot::LLVMDot)
    defaultpath = abspath(dot)
    prefix, _ = splitext(basename(defaultpath))
    kvs = Dict{String,SubLLVMDot}()
    for dot in collect(dot)
        abspath(dot) == defaultpath && continue
        k, _ = splitext(basename(abspath(dot)))
        kvs[k] = dot
    end
    for k in collect(keys(kvs))
        if startswith(k, prefix)
            knew = k[length(prefix)+1:end]
            if !haskey(kvs, knew)
                kvs[knew] = pop!(kvs, k)
            end
        end
    end
    return kvs
end

stemname(x) = splitext(basename(x))[1]

function Base.getindex(dot::LLVMDot, needle::AbstractString)
    alldots = collect(dot)
    candidates = filter(d -> needle == stemname(d), alldots)
    length(candidates) == 1 && return candidates[1]

    defaultpath = abspath(dot)
    prefix, _ = splitext(basename(defaultpath))
    candidates = filter(d -> prefix * needle == stemname(d), alldots)
    length(candidates) == 1 && return candidates[1]

    candidates = filter(d ->　occursin(needle, stemname(d)), alldots)
    length(candidates) == 1 && return candidates[1]

    error("No unique match found:\n", map(stemname, candidates))
end

function Base.getindex(dot::LLVMDot, pattern::Regex)
    candidates = filter!(d ->　match(pattern, stemname(d)) !== nothing, collect(dot))
    length(candidates) == 1 && return candidates[1]
    error("No unique match found:\n", map(stemname, candidates))
end

struct LLVMDotImage <: AbstractCode
    dot::AbstractLLVMDot
    ext::String

    function LLVMDotImage(dot::AbstractLLVMDot, ext::String)
        @assert startswith(ext, ".")
        return new(dot, ext)
    end
end

AbstractLLVMDot(dotimg::LLVMDotImage) = Fields(dotimg).dot
Base.dirname(dotimg::LLVMDotImage) = dirname(AbstractLLVMDot(dotimg))

function _imagepath(dotimg::LLVMDotImage)
    @unpack dot, ext = Fields(dotimg)
    stem, _ = splitext(dotpath(dot))
    return stem * ext
end

function Base.abspath(dotimg::LLVMDotImage)
    imgpath = _imagepath(dotimg)
    ensure_dot_compile(dotpath(dotimg), imgpath)
    return imgpath
end

function Base.show(io::IO, ::MIME"text/plain", dotimg::LLVMDotImage)
    print(io, "LLVMDotImage at ")
    print(io, abspath(dotimg))
end

function dot_compile(dotpath, imgpath)
    # TODO: don't hide handle error messages (if any)
    _, ext = splitext(imgpath)
    fmt = lstrip(ext, '.')
    cmd = getcmd(:dot)
    cmd = `$cmd -o$imgpath -T$fmt $dotpath`
    @debug "Run: $cmd"
    run(pipeline(cmd, stdout = devnull, stderr = devnull, stdin = devnull))
end

function ensure_dot_compile(dotpath, imgpath)
    isfile(imgpath) || dot_compile(dotpath, imgpath)
    return
end

function showdot(io::IO, ext::AbstractString, dotpath::AbstractString)
    @assert startswith(ext, ".")
    stem, _ = splitext(dotpath)
    imgpath = stem * ext
    ensure_dot_compile(dotpath, imgpath)
    write(io, read(imgpath))
    return
end

Base.show(io::IO, ::MIME"image/png", dot::AbstractLLVMDot) =
    showdot(io, ".png", abspath(dot))
Base.show(io::IO, ::MIME"image/svg+xml", dot::AbstractLLVMDot) =
    showdot(io, ".svg", abspath(dot))
