baremodule CodeViz

#=
macro sexpr end
macro lowered end
macro typed end
=#
macro llvm end

function llvm end

module Implementations

using ..CodeViz: CodeViz
import ..CodeViz: @llvm

using InteractiveUtils:
    InteractiveUtils,
    code_llvm,
    code_lowered,
    code_typed,
    gen_call_with_extracted_types_and_kwargs,
    print_llvm
using UnPack: @unpack

include("core.jl")
include("llvm.jl")
end

const CONFIG = Implementations.CodeVizConfig()

end
