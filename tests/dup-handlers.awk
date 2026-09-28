# A QML object with the same signal handler (onXChanged:) or property set
# twice, or two properties or functions of the same name, won't load, and with it anything that uses it (the whole shell, for
# the Settings panel).  qmllint doesn't always say so; this does.
# Braces are counted outside strings and comments, block by block.
{
    line = $0
    sub(/\/\/.*$/, "", line)                          # comments
    gsub(/"([^"\\]|\\.)*"/, "\"\"", line)             # strings
    gsub(/'([^'\\]|\\.)*'/, "''", line)
    if (match(line, /^[ \t]*on[A-Z][A-Za-z0-9_]*[ \t]*:/)) {
        name = substr(line, RSTART, RLENGTH); gsub(/[ \t:]/, "", name)
        key = block[depth] SUBSEP name
        if (key in seen) { printf "%s:%d: %s is also at line %d, in the same object\n", FILENAME, FNR, name, seen[key]; bad = 1 }
        else seen[key] = FNR
    }
    # a declaration: property (readonly, required, default...) or function
    if (match(line, /^[ \t]*((readonly|required|default)[ \t]+)*property[ \t]+[^ \t]+[ \t]+[A-Za-z_][A-Za-z0-9_]*/) || match(line, /^[ \t]*function[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
        decl = substr(line, RSTART, RLENGTH); k = split(decl, w, /[ \t]+/); name = w[k]
        key = block[depth] SUBSEP "decl:" name
        if (key in seen) { printf "%s:%d: %s is also declared at line %d, in the same object\n", FILENAME, FNR, name, seen[key]; bad = 1 }
        else seen[key] = FNR
    }
    n = split(line, ch, "")
    for (i = 1; i <= n; i++) {
        if (ch[i] == "{") { depth++; block[depth] = ++blocks }
        else if (ch[i] == "}") depth--
    }
}
ENDFILE { depth = 0; delete seen }
END { exit bad }
