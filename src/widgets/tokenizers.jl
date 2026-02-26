# ═══════════════════════════════════════════════════════════════════════
# tokenizers.jl ── Language tokenizers for Python, Shell, TypeScript/JS
#
# These reuse the Token/TokenKind types from codeeditor.jl.
# Used by MarkdownPane (syntax-highlighted code blocks) and potentially
# by CodeEditor for multi-language support.
# ═══════════════════════════════════════════════════════════════════════

# ── Public style mapping (wraps the private _token_style) ──────────

"""
    token_style(kind::TokenKind) → Style

Return the theme-derived style for a given token kind. Uses the current theme's
color slots: keywords → primary, strings → success, comments → text_dim, etc.
"""
token_style(kind::TokenKind) = _token_style(kind)

# ── Python tokenizer ────────────────────────────────────────────────

const _PY_KEYWORDS = Set([
    "and", "as", "assert", "async", "await", "break", "class", "continue",
    "def", "del", "elif", "else", "except", "finally", "for", "from",
    "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
    "or", "pass", "raise", "return", "try", "while", "with", "yield",
])
const _PY_BOOLS = Set(["True", "False"])
const _PY_BUILTINS = Set(["None", "self", "cls", "print", "len", "range",
    "type", "int", "str", "float", "list", "dict", "set", "tuple",
    "isinstance", "super", "enumerate", "zip", "map", "filter", "sorted",
    "open", "input", "any", "all", "abs", "min", "max", "sum",
    "Exception", "ValueError", "TypeError", "KeyError", "IndexError",
    "RuntimeError", "StopIteration", "AttributeError", "ImportError",
    "OSError", "FileNotFoundError", "NotImplementedError",
])
const _PY_OPS = Set("=+-*/<>!&|^~%@:")

function tokenize_python(chars::Vector{Char})::Vector{Token}
    tokens = Token[]
    n = length(chars)
    i = 1
    while i <= n
        c = chars[i]
        (c == ' ' || c == '\t') && (i += 1; continue)

        # Comment
        if c == '#'
            push!(tokens, Token(i, n, tok_comment))
            break
        end

        # Decorator
        if c == '@' && (i == 1 || chars[i-1] == ' ' || chars[i-1] == '\t')
            start = i; i += 1
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_' || chars[i] == '.')
                i += 1
            end
            push!(tokens, Token(start, i - 1, tok_macro))
            continue
        end

        # Strings (single, double, triple-quoted)
        if c == '"' || c == '\''
            start = i; q = c
            if i + 2 <= n && chars[i+1] == q && chars[i+2] == q
                i += 3
                while i <= n
                    if chars[i] == q && i + 2 <= n && chars[i+1] == q && chars[i+2] == q
                        i += 3; break
                    end
                    chars[i] == '\\' && i + 1 <= n && (i += 1)
                    i += 1
                end
            else
                i += 1
                while i <= n && chars[i] != q
                    chars[i] == '\\' && i + 1 <= n && (i += 1)
                    i += 1
                end
                i <= n && (i += 1)
            end
            push!(tokens, Token(start, i - 1, tok_string))
            continue
        end

        # Numbers
        if isdigit(c)
            start = i
            if c == '0' && i + 1 <= n && chars[i+1] in ('x', 'X', 'o', 'O', 'b', 'B')
                i += 2
                while i <= n && (isdigit(chars[i]) || chars[i] in ('a','b','c','d','e','f','A','B','C','D','E','F','_'))
                    i += 1
                end
            else
                while i <= n && (isdigit(chars[i]) || chars[i] == '_'); i += 1; end
                if i <= n && chars[i] == '.'
                    i += 1
                    while i <= n && (isdigit(chars[i]) || chars[i] == '_'); i += 1; end
                end
                if i <= n && chars[i] in ('e', 'E')
                    i += 1
                    i <= n && chars[i] in ('+', '-') && (i += 1)
                    while i <= n && isdigit(chars[i]); i += 1; end
                end
            end
            push!(tokens, Token(start, i - 1, tok_number))
            continue
        end

        # Identifiers / keywords
        if isletter(c) || c == '_'
            start = i; i += 1
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_')
                i += 1
            end
            word = String(chars[start:i-1])
            kind = if word in _PY_KEYWORDS
                tok_keyword
            elseif word in _PY_BOOLS
                tok_bool
            elseif word in _PY_BUILTINS
                tok_builtin
            elseif !isempty(word) && isuppercase(word[1])
                tok_type
            else
                tok_identifier
            end
            push!(tokens, Token(start, i - 1, kind))
            continue
        end

        # Operators
        if c in _PY_OPS
            push!(tokens, Token(i, i, tok_operator))
            i += 1; continue
        end

        # Punctuation
        if c in ('(', ')', '[', ']', '{', '}', ',', '.', ';')
            push!(tokens, Token(i, i, tok_punctuation))
            i += 1; continue
        end

        push!(tokens, Token(i, i, tok_identifier))
        i += 1
    end
    tokens
end

# ── Shell tokenizer ─────────────────────────────────────────────────

const _SH_KEYWORDS = Set([
    "if", "then", "else", "elif", "fi", "for", "do", "done", "while",
    "until", "case", "esac", "in", "function", "select", "return",
    "local", "export", "readonly", "declare", "typeset", "unset",
    "shift", "exit", "exec", "eval", "source", "trap",
])
const _SH_BUILTINS = Set([
    "echo", "printf", "cd", "pwd", "test", "read", "set",
    "true", "false", "grep", "sed", "awk", "cat", "ls", "rm", "cp", "mv",
    "mkdir", "chmod", "chown", "find", "xargs", "sort", "uniq", "wc",
    "head", "tail", "cut", "tr", "tee", "diff", "tar", "curl", "wget",
    "git", "docker", "make", "pip", "npm", "julia", "python",
])

function tokenize_shell(chars::Vector{Char})::Vector{Token}
    tokens = Token[]
    n = length(chars)
    i = 1
    while i <= n
        c = chars[i]
        (c == ' ' || c == '\t') && (i += 1; continue)

        # Comment
        if c == '#'
            push!(tokens, Token(i, n, tok_comment))
            break
        end

        # Double-quoted string
        if c == '"'
            start = i; i += 1
            while i <= n && chars[i] != '"'
                chars[i] == '\\' && i + 1 <= n && (i += 1)
                i += 1
            end
            i <= n && (i += 1)
            push!(tokens, Token(start, i - 1, tok_string))
            continue
        end

        # Single-quoted string
        if c == '\''
            start = i; i += 1
            while i <= n && chars[i] != '\''; i += 1; end
            i <= n && (i += 1)
            push!(tokens, Token(start, i - 1, tok_string))
            continue
        end

        # Variable $VAR or ${VAR}
        if c == '$'
            start = i; i += 1
            if i <= n && chars[i] == '{'
                i += 1
                while i <= n && chars[i] != '}'; i += 1; end
                i <= n && (i += 1)
            elseif i <= n && (isletter(chars[i]) || chars[i] == '_')
                while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_')
                    i += 1
                end
            elseif i <= n && chars[i] in ('?', '$', '!', '#', '@', '*', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
                i += 1
            end
            push!(tokens, Token(start, i - 1, tok_symbol))
            continue
        end

        # Numbers
        if isdigit(c)
            start = i
            while i <= n && isdigit(chars[i]); i += 1; end
            push!(tokens, Token(start, i - 1, tok_number))
            continue
        end

        # Flags: -flag or --flag
        if c == '-' && i + 1 <= n && (isletter(chars[i+1]) || chars[i+1] == '-')
            start = i; i += 1
            i <= n && chars[i] == '-' && (i += 1)
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '-' || chars[i] == '_')
                i += 1
            end
            push!(tokens, Token(start, i - 1, tok_macro))
            continue
        end

        # Identifiers / keywords
        if isletter(c) || c == '_'
            start = i; i += 1
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_' || chars[i] == '-')
                i += 1
            end
            word = String(chars[start:i-1])
            kind = if word in _SH_KEYWORDS
                tok_keyword
            elseif word in _SH_BUILTINS
                tok_builtin
            else
                tok_identifier
            end
            push!(tokens, Token(start, i - 1, kind))
            continue
        end

        # Operators: |, ||, &&, ;, >, >>, <, <<
        if c in ('|', '&', ';', '>', '<')
            start = i; i += 1
            if i <= n && chars[i] == c; i += 1; end
            push!(tokens, Token(start, i - 1, tok_operator))
            continue
        end

        # Punctuation
        if c in ('(', ')', '[', ']', '{', '}', '=')
            push!(tokens, Token(i, i, tok_punctuation))
            i += 1; continue
        end

        push!(tokens, Token(i, i, tok_identifier))
        i += 1
    end
    tokens
end

# ── TypeScript / JavaScript tokenizer ────────────────────────────────

const _TS_KEYWORDS = Set([
    "async", "await", "break", "case", "catch", "class", "const",
    "continue", "debugger", "default", "delete", "do", "else", "enum",
    "export", "extends", "finally", "for", "function", "if", "import",
    "in", "instanceof", "let", "new", "of", "return", "super", "switch",
    "throw", "try", "typeof", "var", "void", "while", "with", "yield",
    # TS-specific
    "abstract", "as", "declare", "from", "get", "implements", "interface",
    "is", "keyof", "module", "namespace", "override", "private",
    "protected", "public", "readonly", "require", "set", "static", "type",
])
const _TS_BOOLS = Set(["true", "false"])
const _TS_BUILTINS = Set(["undefined", "null", "NaN", "Infinity",
    "console", "this", "globalThis", "window", "document",
    "Promise", "Array", "Object", "Map", "Set", "RegExp",
    "Error", "TypeError", "RangeError", "JSON", "Math", "Date",
    "String", "Number", "Boolean", "Symbol", "BigInt",
    "string", "number", "boolean", "any", "unknown", "never", "object",
])
const _TS_OPS = Set("=+-*/<>!&|^~%?:")

function tokenize_typescript(chars::Vector{Char})::Vector{Token}
    tokens = Token[]
    n = length(chars)
    i = 1
    while i <= n
        c = chars[i]
        (c == ' ' || c == '\t') && (i += 1; continue)

        # Line comment
        if c == '/' && i + 1 <= n && chars[i+1] == '/'
            push!(tokens, Token(i, n, tok_comment))
            break
        end

        # Block comment (single line only)
        if c == '/' && i + 1 <= n && chars[i+1] == '*'
            start = i; i += 2
            while i + 1 <= n
                if chars[i] == '*' && chars[i+1] == '/'
                    i += 2; break
                end
                i += 1
            end
            i > n && (i = n + 1)
            push!(tokens, Token(start, i - 1, tok_comment))
            continue
        end

        # Template literal
        if c == '`'
            start = i; i += 1
            while i <= n && chars[i] != '`'
                chars[i] == '\\' && i + 1 <= n && (i += 1)
                i += 1
            end
            i <= n && (i += 1)
            push!(tokens, Token(start, i - 1, tok_string))
            continue
        end

        # Strings
        if c == '"' || c == '\''
            start = i; q = c; i += 1
            while i <= n && chars[i] != q
                chars[i] == '\\' && i + 1 <= n && (i += 1)
                i += 1
            end
            i <= n && (i += 1)
            push!(tokens, Token(start, i - 1, tok_string))
            continue
        end

        # Decorator
        if c == '@'
            start = i; i += 1
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_')
                i += 1
            end
            push!(tokens, Token(start, i - 1, tok_macro))
            continue
        end

        # Numbers
        if isdigit(c)
            start = i
            if c == '0' && i + 1 <= n && chars[i+1] in ('x', 'X', 'o', 'O', 'b', 'B')
                i += 2
                while i <= n && (isdigit(chars[i]) || chars[i] in ('a','b','c','d','e','f','A','B','C','D','E','F','_'))
                    i += 1
                end
            else
                while i <= n && (isdigit(chars[i]) || chars[i] == '_'); i += 1; end
                if i <= n && chars[i] == '.'
                    i += 1
                    while i <= n && (isdigit(chars[i]) || chars[i] == '_'); i += 1; end
                end
                if i <= n && chars[i] in ('e', 'E')
                    i += 1
                    i <= n && chars[i] in ('+', '-') && (i += 1)
                    while i <= n && isdigit(chars[i]); i += 1; end
                end
            end
            i <= n && chars[i] == 'n' && (i += 1)  # BigInt
            push!(tokens, Token(start, i - 1, tok_number))
            continue
        end

        # Identifiers / keywords
        if isletter(c) || c == '_' || c == '$'
            start = i; i += 1
            while i <= n && (isletter(chars[i]) || isdigit(chars[i]) || chars[i] == '_' || chars[i] == '$')
                i += 1
            end
            word = String(chars[start:i-1])
            kind = if word in _TS_KEYWORDS
                tok_keyword
            elseif word in _TS_BOOLS
                tok_bool
            elseif word in _TS_BUILTINS
                tok_builtin
            elseif !isempty(word) && isuppercase(word[1])
                tok_type
            else
                tok_identifier
            end
            push!(tokens, Token(start, i - 1, kind))
            continue
        end

        # Arrow =>
        if c == '=' && i + 1 <= n && chars[i+1] == '>'
            push!(tokens, Token(i, i + 1, tok_operator))
            i += 2; continue
        end

        # Operators
        if c in _TS_OPS
            push!(tokens, Token(i, i, tok_operator))
            i += 1; continue
        end

        # Punctuation
        if c in ('(', ')', '[', ']', '{', '}', ',', '.', ';')
            push!(tokens, Token(i, i, tok_punctuation))
            i += 1; continue
        end

        push!(tokens, Token(i, i, tok_identifier))
        i += 1
    end
    tokens
end

# ── Dispatch: language string → tokenizer ────────────────────────────

const _CODE_TOKENIZERS = Dict{String, Function}(
    "julia"      => tokenize_line,
    "jl"         => tokenize_line,
    "python"     => tokenize_python,
    "py"         => tokenize_python,
    "bash"       => tokenize_shell,
    "sh"         => tokenize_shell,
    "shell"      => tokenize_shell,
    "zsh"        => tokenize_shell,
    "console"    => tokenize_shell,
    "typescript" => tokenize_typescript,
    "ts"         => tokenize_typescript,
    "javascript" => tokenize_typescript,
    "js"         => tokenize_typescript,
    "tsx"        => tokenize_typescript,
    "jsx"        => tokenize_typescript,
)

"""
    tokenize_code(lang::AbstractString, chars::Vector{Char}) → Union{Vector{Token}, Nothing}

Tokenize a line of code in the given language. Returns `nothing` if the
language is not supported. Supported languages: julia, python, bash/sh,
typescript/javascript.
"""
function tokenize_code(lang::AbstractString, chars::Vector{Char})
    tokenizer = get(_CODE_TOKENIZERS, lowercase(strip(string(lang))), nothing)
    tokenizer === nothing && return nothing
    tokenizer(chars)
end
