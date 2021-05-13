function julia_toolsdir()
    prefix = dirname(dirname(Base.julia_cmd().exec[1]))
    toolsdir = joinpath(prefix, "tools")
    isfile(joinpath(toolsdir, "opt")) && return toolsdir
    return nothing
end

Base.@kwdef mutable struct ShowCodeConfig
    toolsdir::Union{String,Nothing} = julia_toolsdir()
    opt = nothing
    llc = nothing
    dot = nothing
    pygmentize = nothing
end

getcmd(name::Symbol) = getcmd(ShowCode.CONFIG, name)
function getcmd(config::ShowCodeConfig, name::Symbol)
    cmd = getfield(config, name)
    cmd === nothing || return cmd
    toolsdir = config.toolsdir
    if toolsdir !== nothing
        candidate = joinpath(toolsdir, string(name))
        isfile(candidate) && return `$candidate`
    end
    try
        return getfield(LLVM_jll, name)()::Base.AbstractCmd
    catch
    end
    try
        return getfield(LLVM_jll, name)(identity)::Base.AbstractCmd
    catch
    end
    prog = string(string(name))
    if Sys.which(prog) === nothing && config === ShowCode.CONFIG
        msg = (
            "Program `$name` not found. If it exists outside the `\$PATH, " *
            "set `ShowConfig.CONFIG.$name`."
        )
        if name in (:opt, :llc)
            msg *= (
                " You can also set `ShowConfig.CONFIG.toolsdir` to `usr/tools` of your" *
                "Julia's build directory (if any)."
            )
        end
        @error "$msg"
    end
    return `$prog`
end


abstract type AbstractCode end

function Base.show(io::IO, ::MIME"text/plain", code::AbstractCode)
    T = nameof(typeof(code))
    print(io, T, "(...)")
    return
end

InteractiveUtils.edit(code::AbstractCode) = InteractiveUtils.edit(abspath(code))

struct Fields{T}
    object::T
end

Base.propertynames(::Fields{T}) where {T} = fieldnames(T)
Base.getproperty(fields::Fields, name::Symbol) = getfield(getfield(fields, :object), name)

function write_silently(cmd, input; stdout = devnull)
    errio = IOBuffer()
    proc = open(pipeline(cmd, stderr = errio, stdout = stdout), write = true)
    try
        write(proc, input)
    finally
        close(proc)
    end
    wait(proc)
    if proc.exitcode != 0
        cmd0 = setenv(cmd)
        error(
            "Command $cmd0 (cwd: $(cmd.dir)) failed with code $(proc.exitcode) and error:\n",
            String(take!(errio)),
        )
    end
    return proc
end

function finalize_module()
    doc = read(joinpath(dirname(@__DIR__), "README.md"), String)
    @eval ShowCode $Base.@doc $doc ShowCode
end
