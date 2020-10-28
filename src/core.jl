function julia_toolsdir()
    prefix = dirname(dirname(Base.julia_cmd().exec[1]))
    toolsdir = joinpath(prefix, "tools")
    isfile(joinpath(toolsdir, "opt")) && return toolsdir
    return nothing
end

Base.@kwdef mutable struct CodeXConfig
    toolsdir::Union{String,Nothing} = julia_toolsdir()
    opt = nothing
    llc = nothing
    dot = nothing
    pygmentize = nothing
end

getcmd(name::Symbol) = getcmd(CodeX.CONFIG, name)
function getcmd(config::CodeXConfig, name::Symbol)
    cmd = getfield(config, name)
    cmd === nothing || return cmd
    toolsdir = config.toolsdir
    if toolsdir !== nothing
        candidate = joinpath(toolsdir, string(name))
        isfile(candidate) && return `$candidate`
    end
    return `$(string(name))`
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

Base.propertynames(fields::Fields) = propertynames(getfield(fields, :object))
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
    @eval CodeX $Base.@doc $doc CodeX
end
