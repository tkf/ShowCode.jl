function CodeX.llvm(b::Cthulhu.Bookmark; kw...)
    s = sprint() do io
        code_llvm(
            io,
            b;
            config = Cthulhu.CthulhuConfig(enable_highlighter = false),
            dump_module = true,
            kw...,
        )
    end
    return CodeX.from_llvm(s)
end

function CodeX.native(b::Cthulhu.Bookmark; kw...)
    s = sprint() do io
        code_native(io, b; config = Cthulhu.CthulhuConfig(enable_highlighter = false), kw...)
    end
    return CodeX.from_native(s)
end
