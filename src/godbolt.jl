"""
    post_godbolt(c.godbolt)

Post code snippet in [Compiler Explore](godbolt.org).

**WARNING**: When the code is posted to godbolt.org there is no way to delete
the code as of writing.

# Examples

```julia
c = @sc_llvm sum((1, 2, 3))
ce = post_godbolt(c.godbolt)         # post the code
string(ce)                           # get the URL
ce()                                 # post it and then open the URL
```
"""
post_godbolt

# ce - Compiler Explore
# cec - Compiler Explore Client

abstract type GodboltBase end

struct Godbolt <: GodboltBase
    code::Any
    cache::Dict{String,Any}
end

Godbolt(code) = Godbolt(code, Dict{String,Any}())

Base.propertynames(::Godbolt) = (:mca,)
Base.getproperty(ce::Godbolt, compiler::Symbol) = getproperty(ce, string(compiler))
Base.getproperty(ce::Godbolt, compiler::AbstractString) =
    get!(Fields(ce).cache, compiler) do
        _getproperty(ce, compiler)
    end::GodboltClient

function _getproperty(ce::Godbolt, compiler::AbstractString)
    compiler == "_default" && return default_client(ce)
    @unpack code = Fields(ce)
    compiler = get(Dict("mca" => "llvm-mcatrunk"), compiler, compiler)
    language = godbolt_language(code)
    return GodboltClient(; code, language, compiler)
end

godbolt_language(::CodeLLVM) = "llvm"
godbolt_language(::CodeNative) = "assembly"

function default_client(ce::Godbolt)
    @unpack code = Fields(ce)
    if code isa CodeNative
        return GodboltClient(; code, language = "analysis", compiler = "llvm-mcatrunk")
    elseif code isa CodeLLVM
        return ce.llctrunk
    else
        error("No default client for ", code)
    end
end

Base.@kwdef struct GodboltClient <: GodboltBase
    code::Any

    # `id` of https://godbolt.org/api/languages
    language::String

    # `id` of https://godbolt.org/api/compilers
    compiler::String

    options::Cmd = ``

    url::Base.RefValue{Union{Nothing,String}} = Ref{Union{Nothing,String}}(nothing)
end
# https://github.com/compiler-explorer/compiler-explorer/blob/master/docs/API.md

function clientstate(cec::GodboltClient)
    # cec - Compiler Explore Client
    @unpack code, language, compiler, options = cec
    options_str = join(options, " ")  # TODO: quote
    return Dict(
        "sessions" => [Dict(
            "language" => language,
            "source" => string(code),
            "compilers" => [Dict("id" => compiler, "options" => options_str)],
        )],
    )
end

function post_godbolt(ce::Godbolt)
    post_godbolt(GodboltClient(ce))
    return ce
end

function post_godbolt(cec::GodboltClient)
    @unpack url = Fields(cec)
    url[] === nothing || return cec
    url[] = godbolt_url(cec)
    return cec
end

get_url(cec::GodboltClient) = Fields(cec).url[]
Base.string(cec::GodboltClient) = something(get_url(cec), "?? not posted ??")
# TODO: maybe don't overload `string`?

function godbolt_url(cec::GodboltClient)
    url = godbolt_base64url(cec)
    # Use URL shortener for URL longer than 2000 characters
    # https://stackoverflow.com/a/417184
    if length(url) > 2000
        url = godbolt_shorturl(cec)
    end
    return url
end

function godbolt_base64url(cec::GodboltClient)
    s = base64encode(JSON.print, clientstate(cec))
    return "https://godbolt.org/clientstate/$s"
end

function godbolt_shorturl(cec::GodboltClient)
    response = HTTP.post(
        "https://godbolt.org/shortener",
        ["Content-Type" => "application/json", "Accept" => "application/json"],
        JSON.json(clientstate(cec)),
    )
    msg = JSON.parse(String(response.body))
    return msg["url"]
end

function (cec::GodboltClient)()
    url = get_url(post_godbolt(cec))::AbstractString
    DefaultApplication.open(url; wait = false)
    return
end

GodboltClient(cec::GodboltClient) = cec
GodboltClient(ce::Godbolt) = ce._default

(ce::GodboltBase)() = GodboltClient(ce)()
Base.string(ce::GodboltBase) = string(GodboltClient(ce))
Base.print(io::IO, ce::GodboltBase) = print(io, string(ce))

function Base.summary(io::IO, ce::GodboltBase)
    print(io, nameof(typeof(ce)), " (interface for opening URL at godbolt.org)")
end

function Base.show(io::IO, ::MIME"text/plain", ce::GodboltBase)
    summary(io, ce)
    println(io)
    print(io, GodboltClient(ce))
end
