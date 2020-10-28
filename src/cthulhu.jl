function CodeX.llvm(b::Cthulhu.Bookmark)
    s = sprint() do io
        code_llvm(
            io,
            b;
            config = Cthulhu.CthulhuConfig(enable_highlighter = false),
            dump_module = true,
        )
    end
    return CodeX.from_llvm(s)
end

function CodeX.native(b::Cthulhu.Bookmark)
    s = sprint() do io
        code_native(io, b; config = Cthulhu.CthulhuConfig(enable_highlighter = false))
    end
    return CodeX.from_native(s)
end
