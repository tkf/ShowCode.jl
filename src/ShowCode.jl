baremodule ShowCode

export @sc_ircode, @sc_llvm, @sc_native, @sc_intel, sc_ircode, sc_llvm, sc_native, sc_intel

#=
macro sc_sexpr end
macro sc_lowered end
macro sc_typed end
=#
macro sc_ircode end
macro sc_llvm end
macro sc_native end
macro sc_intel end

function sc_ircode end
function sc_llvm end
function sc_native end
function sc_intel end

function from_llvm end
function from_native end

module Implementations

using ..ShowCode: ShowCode
import ..ShowCode:
    @sc_ircode, @sc_llvm, @sc_native, @sc_intel, sc_ircode, sc_llvm, sc_native, sc_intel

import AbstractTrees
import DefaultApplication
import HTTP
import JSON
using Base64: base64encode
using InteractiveUtils:
    InteractiveUtils,
    code_llvm,
    code_lowered,
    code_native,
    code_typed,
    gen_call_with_extracted_types_and_kwargs,
    print_llvm,
    print_native
using Requires: @require
using UnPack: @unpack

include("core.jl")
include("code_ircode.jl")
include("ircode.jl")
include("llvm.jl")
include("native.jl")
include("godbolt.jl")

function __init__()
    @require Cthulhu="f68482b8-f384-11e8-15f7-abe071a5a75f" include("cthulhu.jl")
end

end

const CONFIG = Implementations.ShowCodeConfig()

Implementations.finalize_module()

end
