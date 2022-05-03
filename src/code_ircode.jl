# https://github.com/JuliaLabs/brutus/blob/9d87d7aa543090ab6e8b98dc7413476c107a7075/Brutus/src/Brutus.jl#L98-L146

function get_methodinstance(@nospecialize(sig);
                            world=Base.get_world_counter(),
                            interp=Core.Compiler.NativeInterpreter(world))
    ms = Base._methods_by_ftype(sig, 1, Base.get_world_counter())
    @assert length(ms) == 1
    m = ms[1]
    mi = ccall(:jl_specializations_get_linfo,
               Ref{Core.MethodInstance}, (Any, Any, Any),
               m[3], m[1], m[2])
    return mi
end

function code_ircode_by_signature(@nospecialize(sig);
                                  world=Base.get_world_counter(),
                                  interp=Core.Compiler.NativeInterpreter(world))
    return [code_ircode(ccall(:jl_specializations_get_linfo,
                              Ref{Core.MethodInstance},
                              (Any, Any, Any),
                              data[3], data[1], data[2]);
                        world=world, interp=interp)
            for data in Base._methods_by_ftype(sig, -1, world)]
end

function code_ircode(@nospecialize(f), @nospecialize(types=Tuple);
                     world=Base.get_world_counter(),
                     interp=Core.Compiler.NativeInterpreter(world))
    return [code_ircode(mi; world=world, interp=interp)
            for mi in Base.method_instances(f, types, world)]
end

function code_ircode(mi::Core.Compiler.MethodInstance;
                     world=Base.get_world_counter(),
                     interp=Core.Compiler.NativeInterpreter(world))
    ccall(:jl_typeinf_begin, Cvoid, ())
    result = Core.Compiler.InferenceResult(mi)
    frame = @static if hasmethod(
        Core.Compiler.InferenceState,
        (Core.Compiler.InferenceResult, Bool, Core.Compiler.AbstractInterpreter),
    )
        Core.Compiler.InferenceState(result, #=cached=# false, interp)
    else
        Core.Compiler.InferenceState(result, #=cache=# :no, interp)
    end
    frame === nothing && return nothing
    nargs = Int((mi.def::Method).nargs)
    if Core.Compiler.typeinf(interp, frame)
        opt_params = Core.Compiler.OptimizationParams(interp)
        opt = Core.Compiler.OptimizationState(frame, opt_params, interp)
        ir = @static if hasmethod(
            Core.Compiler.run_passes,
            (Core.CodeInfo, Int, Core.Compiler.OptimizationState),
        )
            Core.Compiler.run_passes(opt.src, nargs - 1, opt)
        else
            Core.Compiler.run_passes(opt.src, opt, result)
        end
        opt.src.inferred = true
    end
    ccall(:jl_typeinf_end, Cvoid, ())
    frame.inferred || return nothing
    # TODO(yhls): Fix this upstream
    resize!(ir.argtypes, nargs)
    return ir => Core.Compiler.widenconst(result.result)
end
