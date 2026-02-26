    @testset "Tokenizers" begin
        @testset "Python tokenizer" begin
            chars = collect("def hello(name):")
            tokens = T.tokenize_python(chars)
            @test length(tokens) >= 1
            @test tokens[1].kind == T.tok_keyword  # def

            # String
            tokens = T.tokenize_python(collect("x = \"hello\""))
            kinds = [t.kind for t in tokens]
            @test T.tok_string in kinds

            # Comment
            tokens = T.tokenize_python(collect("# a comment"))
            @test tokens[1].kind == T.tok_comment

            # Number
            tokens = T.tokenize_python(collect("42"))
            @test tokens[1].kind == T.tok_number

            # Hex number
            tokens = T.tokenize_python(collect("0xFF"))
            @test tokens[1].kind == T.tok_number

            # Float
            tokens = T.tokenize_python(collect("3.14e10"))
            @test tokens[1].kind == T.tok_number

            # Bool
            tokens = T.tokenize_python(collect("True"))
            @test tokens[1].kind == T.tok_bool

            # Builtin
            tokens = T.tokenize_python(collect("None"))
            @test tokens[1].kind == T.tok_builtin

            # Type (uppercase start)
            tokens = T.tokenize_python(collect("MyClass"))
            @test tokens[1].kind == T.tok_type

            # Decorator
            tokens = T.tokenize_python(collect("@property"))
            @test tokens[1].kind == T.tok_macro

            # Operator
            tokens = T.tokenize_python(collect("+="))
            kinds = [t.kind for t in tokens]
            @test T.tok_operator in kinds

            # Punctuation
            tokens = T.tokenize_python(collect("()"))
            @test all(t -> t.kind == T.tok_punctuation, tokens)

            # Triple-quoted string
            tokens = T.tokenize_python(collect("\"\"\"docstring\"\"\""))
            @test tokens[1].kind == T.tok_string

            # Single-quoted string
            tokens = T.tokenize_python(collect("'hello'"))
            @test tokens[1].kind == T.tok_string

            # Escape in string
            tokens = T.tokenize_python(collect("\"he\\\"llo\""))
            @test tokens[1].kind == T.tok_string
        end

        @testset "Shell tokenizer" begin
            chars = collect("if [ -f file ]; then echo hi; fi")
            tokens = T.tokenize_shell(chars)
            kinds = [t.kind for t in tokens]
            @test T.tok_keyword in kinds  # if, then, fi
            @test T.tok_builtin in kinds  # echo

            # Comment
            tokens = T.tokenize_shell(collect("# comment"))
            @test tokens[1].kind == T.tok_comment

            # Variable
            tokens = T.tokenize_shell(collect("\$HOME"))
            @test tokens[1].kind == T.tok_symbol

            # ${VAR} form
            tokens = T.tokenize_shell(collect("\${PATH}"))
            @test tokens[1].kind == T.tok_symbol

            # Special variable $?
            tokens = T.tokenize_shell(collect("\$?"))
            @test tokens[1].kind == T.tok_symbol

            # Flags
            tokens = T.tokenize_shell(collect("ls --all -l"))
            kinds = [t.kind for t in tokens]
            @test T.tok_macro in kinds  # flags

            # Strings
            tokens = T.tokenize_shell(collect("echo \"hello\""))
            kinds = [t.kind for t in tokens]
            @test T.tok_string in kinds

            tokens = T.tokenize_shell(collect("echo 'hello'"))
            kinds = [t.kind for t in tokens]
            @test T.tok_string in kinds

            # Numbers
            tokens = T.tokenize_shell(collect("42"))
            @test tokens[1].kind == T.tok_number

            # Operators
            tokens = T.tokenize_shell(collect("echo foo | grep bar"))
            kinds = [t.kind for t in tokens]
            @test T.tok_operator in kinds

            # Punctuation
            tokens = T.tokenize_shell(collect("()"))
            @test all(t -> t.kind == T.tok_punctuation, tokens)
        end

        @testset "TypeScript tokenizer" begin
            chars = collect("const x: number = 42;")
            tokens = T.tokenize_typescript(chars)
            kinds = [t.kind for t in tokens]
            @test T.tok_keyword in kinds  # const
            @test T.tok_number in kinds   # 42

            # Line comment
            tokens = T.tokenize_typescript(collect("// comment"))
            @test tokens[1].kind == T.tok_comment

            # Block comment
            tokens = T.tokenize_typescript(collect("/* block */"))
            @test tokens[1].kind == T.tok_comment

            # Template literal
            tokens = T.tokenize_typescript(collect("`hello \${name}`"))
            kinds = [t.kind for t in tokens]
            @test T.tok_string in kinds

            # Strings
            tokens = T.tokenize_typescript(collect("\"hello\""))
            @test tokens[1].kind == T.tok_string

            tokens = T.tokenize_typescript(collect("'hello'"))
            @test tokens[1].kind == T.tok_string

            # Bool
            tokens = T.tokenize_typescript(collect("true"))
            @test tokens[1].kind == T.tok_bool

            # Builtin
            tokens = T.tokenize_typescript(collect("console"))
            @test tokens[1].kind == T.tok_builtin

            # Builtin type
            tokens = T.tokenize_typescript(collect("Promise"))
            @test tokens[1].kind == T.tok_builtin

            # User type (uppercase, not builtin)
            tokens = T.tokenize_typescript(collect("MyComponent"))
            @test tokens[1].kind == T.tok_type

            # Decorator
            tokens = T.tokenize_typescript(collect("@Component"))
            @test tokens[1].kind == T.tok_macro

            # Arrow
            tokens = T.tokenize_typescript(collect("=>"))
            @test tokens[1].kind == T.tok_operator

            # Hex number
            tokens = T.tokenize_typescript(collect("0xFF"))
            @test tokens[1].kind == T.tok_number

            # Float
            tokens = T.tokenize_typescript(collect("3.14e10"))
            @test tokens[1].kind == T.tok_number

            # BigInt
            tokens = T.tokenize_typescript(collect("42n"))
            @test tokens[1].kind == T.tok_number

            # Punctuation
            tokens = T.tokenize_typescript(collect("(){}"))
            @test all(t -> t.kind == T.tok_punctuation, tokens)

            # $ in identifier
            tokens = T.tokenize_typescript(collect("\$el"))
            @test tokens[1].kind == T.tok_identifier
        end

        @testset "tokenize_code dispatch" begin
            # Supported languages
            for lang in ["julia", "jl", "python", "py", "bash", "sh", "shell",
                         "typescript", "ts", "javascript", "js", "tsx", "jsx"]
                result = T.tokenize_code(lang, collect("x = 1"))
                @test result !== nothing
                @test result isa Vector{T.Token}
            end

            # Unsupported language
            @test T.tokenize_code("rust", collect("fn main()")) === nothing
            @test T.tokenize_code("", collect("hello")) === nothing
        end

        @testset "token_style" begin
            # Just check it returns a Style without error
            for kind in [T.tok_keyword, T.tok_string, T.tok_comment, T.tok_number,
                         T.tok_identifier, T.tok_operator, T.tok_punctuation]
                s = T.token_style(kind)
                @test s isa T.Style
            end
        end
    end
