baremodule CodeX

#=
macro sexpr end
macro lowered end
macro typed end
=#
macro llvm end
macro native end
macro intel end

function llvm end
function native end
function intel end

module Implementations

using ..CodeX: CodeX
import ..CodeX: @llvm, @native, @intel

import DefaultApplication
import HTTP
import JSON
using Base64: base64encode
using InteractiveUtils:
    InteractiveUtils,
    code_llvm,
    code_lowered,
    code_typed,
    gen_call_with_extracted_types_and_kwargs,
    print_llvm,
    print_native
using UnPack: @unpack

include("core.jl")
include("llvm.jl")
include("native.jl")
include("godbolt.jl")
end

const CONFIG = Implementations.CodeXConfig()

end
