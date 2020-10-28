"""
    c = CodeX.@native f(args...)
    c = CodeX.@intel f(args...)
    c = (CodeX.@llvm f(args...)).native
    c = (CodeX.@llvm f(args...)).att
    c = (CodeX.@llvm f(args...)).intel

Native code explore.

```julia
c                  # view code in the REPL
display(c)         # (ditto)
edit(c)            # open the code in editor
print(c)           # print the code
abspath(c)         # file path to the text containing the code
```
"""
(:(@native), :(@intel))

"""
    CodeX.from_native(code::AbstractString)

Construct a native code explore from a snippet of ASM.

For example,

```julia
a = CodeX.@native dump_module=true f(...)
b = CodeX.from_native(string(a))
```

should be roughly equivalent.
"""
function CodeX.from_native(code::AbstractString; syntax = :att)
    # TODO: guess syntax?
    return CodeNative(String(code), syntax, true, ("f?", "Tuple{?}"), nothing)
end

struct CodeNative <: AbstractCode
    code::String
    syntax::Symbol
    user_dump_module::Bool
    args::Any
    kwargs::Any
    cache::Dict{Symbol,Any}
    abspath::Base.RefValue{Union{Nothing,String}}
end

CodeNative(args::Vararg{Any,5}) =
    CodeNative(args..., Dict{Symbol,Any}(), Ref{Union{Nothing,String}}(nothing))

Base.string(native::CodeNative) = Fields(native).code
Base.print(io::IO, native::CodeNative) = print(io, string(native))

function Base.abspath(native::CodeNative)
    p = Fields(native).abspath[]
    p === nothing || return p
    p = joinpath(mktempdir(prefix = "jl_codeviz_"), "code.s")
    write(p, string(native))
    Fields(native).abspath[] = p
    return p
end

Base.propertynames(native::CodeNative) = (
    # what else?
    :godbolt,
)

Base.getproperty(native::CodeNative, name::Symbol) =
    if name === :godbolt
        Godbolt(native)
    else
        error("Unknown property: ", name)
    end


function Base.summary(io::IO, native::CodeNative)
    f, t = Fields(native).args
    print(io, "CodeNative of ", f, " with ", t)
    return
end

function Base.show(io::IO, ::MIME"text/plain", native::CodeNative)
    @unpack code = Fields(native)
    summary(io, native)
    println(io)
    if get(io, :color, false)
        print_native(io, code)
    else
        print(io, code)
    end
    return
end

macro native(args...)
    gen_call_with_extracted_types_and_kwargs(__module__, CodeX.native, args)
end

macro intel(args...)
    gen_call_with_extracted_types_and_kwargs(__module__, CodeX.intel, args)
end

function CodeX.native(args...; dump_module = false, syntax = :att, kwargs...)
    if dump_module
        return getproperty(
            CodeX.llvm(args...; dump_module = dump_module, kwargs...),
            syntax,
        )
    end
    @nospecialize
    code = sprint() do io
        @nospecialize
        code_native(io, args...; dump_module = true, syntax = syntax, kwargs...)
    end
    return CodeNative(code, syntax, dump_module, args, kwargs)
end

CodeX.intel(args...; kwargs...) = CodeX.native(args...; syntax = :intel, kwargs...)

function CodeNative(llvm::CodeLLVM, syntax::Symbol)
    @unpack user_dump_module, args, kwargs = Fields(llvm)
    CodeNative(
        llvm_to_native(llvm, `--x86-asm-syntax=$syntax`),
        syntax,
        user_dump_module,
        args,
        kwargs,
    )
end

function llvm_to_native(ir, options = ``)
    cmd = getcmd(:llc)
    cmd = `$cmd $options -o=- --filetype=asm -`
    io = IOBuffer()
    write_silently(cmd, string(ir); stdout = io)
    return String(take!(io))
end
