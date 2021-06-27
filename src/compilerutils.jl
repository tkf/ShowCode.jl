module CompilerUtils

using Core.Compiler:
    CodeInfo,
    NativeInterpreter,
    OptimizationParams,
    OptimizationState,
    compact!,
    convert_to_ircode,
    copy,
    copy_exprargs,
    slot2reg

fallback_insert_new_nodes(ir) = compact!(copy(ir), true)

const insert_new_nodes = try
    Core.Compiler.insert_new_nodes
catch
    fallback_insert_new_nodes
end

function is_intermediate_value_type(t)
    @nospecialize t
    return t isa Union{Core.Compiler.DelayedTyp,Core.Compiler.NotFound}
end

function ircode_from_codeinfo(ci::CodeInfo)
    # Making a copy here, as, e.g., `convert_to_ircode` mutates `ci`:
    ci = copy(ci)

    for (i, t) in pairs(ci.ssavaluetypes)
        if is_intermediate_value_type(t)
            ci.ssavaluetypes[i] = Any
        end
    end

    linfo = ci.parent  # MethodInstance
    interp = NativeInterpreter()
    params = OptimizationParams(interp)
    opt = OptimizationState(linfo, copy(ci), params, interp)
    nargs = Int(opt.nargs) - 1
    preserve_coverage = false
    code = copy_exprargs(ci.code)
    ir = convert_to_ircode(ci, code, preserve_coverage, nargs, opt)
    ir = slot2reg(ir, ci, nargs, opt)
    ir = insert_new_nodes(ir)
    return ir
end

end  # module
