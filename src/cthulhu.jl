function sc_ircode(b::Cthulhu.Bookmark)
    c = sc_ircode(b.mi; world = b.params.world)
    return @set c.args = (b,)  # so that `c.llvm` works
end

function sc_llvm(b::Cthulhu.Bookmark; kw...)
    s = sprint() do io
        code_llvm(
            io,
            b;
            config = Cthulhu.CthulhuConfig(enable_highlighter = false),
            dump_module = true,
            kw...,
        )
    end
    return ShowCode.from_llvm(s)
end

function sc_native(b::Cthulhu.Bookmark; kw...)
    s = sprint() do io
        code_native(io, b; config = Cthulhu.CthulhuConfig(enable_highlighter = false), kw...)
    end
    return ShowCode.from_native(s)
end
