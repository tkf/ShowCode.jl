Base.@kwdef mutable struct CodeVizConfig
    opt = `opt`
    dot = `dot`
    pygmentize = `pygmentize`
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
