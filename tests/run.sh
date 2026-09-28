#!/bin/sh
# tests/run.sh  (Ether Shell)
# Every check, in one go: on GitHub for each push, or on your own machine.
#
#   tests/run.sh            all of them
#   tests/run.sh --quick    skip building the plugin
#
# A check whose tool isn't installed is skipped (and says so), never failed.
cd "$(dirname "$0")/.." || exit 1
quick=0; [ "${1:-}" = --quick ] && quick=1
failed=0; passed=0; skipped=0
ok()   { passed=$((passed + 1)); printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { failed=$((failed + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
skip() { skipped=$((skipped + 1)); printf '  \033[33mskip\033[0m  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
qtbin() { for p in "$(command -v "$1" 2>/dev/null)" "/usr/lib/qt6/bin/$1" "/usr/lib64/qt6/bin/$1"; do [ -x "$p" ] && { echo "$p"; return; }; done; }

echo "Shell scripts (shellcheck)"
if have shellcheck; then
    for f in install.sh local/bin/* config/ether-greeter/start tests/run.sh; do
        head -1 "$f" | grep -qE '^#!.*(sh|bash)' || continue
        out=$(shellcheck -S warning "$f" 2>&1) && ok "$f" || { bad "$f"; echo "$out" | head -20; }
    done
else skip "shellcheck isn't installed"; fi

echo "QML (qmllint: syntax errors; the Quickshell modules it can't see are fine)"
qmllint=$(qtbin qmllint)
if [ -n "$qmllint" ]; then
    n=0; for f in config/quickshell/*.qml config/ether-greeter/*.qml plugins/*/*.qml; do
        out=$("$qmllint" "$f" 2>&1 | grep -iE "expected token|syntax error|unexpected token|duplicate")
        if [ -n "$out" ]; then bad "$f"; echo "$out" | head -10; else n=$((n + 1)); fi
    done
    [ "$n" -gt 0 ] && ok "$n QML files"
else skip "qmllint isn't installed (Qt's declarative tools)"; fi

echo "Lua (Hyprland configs)"
luac=$(command -v luac5.4 || command -v luac || true)
if [ -n "$luac" ]; then
    for f in config/hypr/hyprland.lua config/ether-greeter/hyprland.lua; do
        out=$("$luac" -p "$f" 2>&1) && ok "$f" || { bad "$f"; echo "$out"; }
    done
else skip "luac isn't installed"; fi

echo "Logic (Node's test runner)"
if have node; then
    out=$(node --test tests/*.test.mjs 2>&1)
    summary=$(echo "$out" | grep -E '^# (pass|fail) ' | tr '\n' ' ')
    if echo "$out" | grep -qE '^# fail 0$'; then ok "tests: $summary"
    else bad "tests: $summary"; echo "$out" | grep -B2 -A12 '^not ok' | head -40; fi
else skip "node isn't installed"; fi

echo "no QML object has the same handler twice (it wouldn't load)"
if out=$(gawk -f tests/dup-handlers.awk config/quickshell/*.qml config/ether-greeter/*.qml plugins/*/*.qml 2>&1); then
    ok "no handler set twice"
else
    bad "a handler set twice: $out"
fi

echo "plugin templates (ether plugin new) make working plugins"
if have node; then
    th=$(mktemp -d)
    mkdir -p "$th/bin"; printf '#!/bin/sh\nexit 1\n' > "$th/bin/pgrep"; chmod +x "$th/bin/pgrep"
    HOME="$th" PATH="$th/bin:$PATH" sh local/bin/ether plugin new t-default >/dev/null 2>&1
    HOME="$th" PATH="$th/bin:$PATH" sh local/bin/ether plugin new t-all --bar --launcher --widget --settings >/dev/null 2>&1
    for id in t-default t-all; do
        d="$th/.config/ether-shell/plugins/$id"
        if [ -f "$d/plugin.json" ] && node --input-type=module -e "
            import { readManifest } from '$PWD/config/quickshell/lib/plugins.mjs'; import { readFileSync, existsSync } from 'node:fs'
            const p = readManifest('$id', readFileSync('$d/plugin.json', 'utf8'), '$th/.config/ether-shell/plugins')
            for (const k of ['bar', 'launcher', 'widget', 'settings']) if (p[k] && !existsSync('$d/' + p[k].file)) process.exit(2)
            process.exit(p.ok ? 0 : 1)"; then
            ok "template $id"
        else bad "template $id doesn't make a working plugin"; fi
        if have qmllint; then for q in "$d"/*.qml; do qmllint "$q" 2>&1 | grep -qiE "syntax|expected token|unexpected" && bad "template $(basename "$q") has a QML mistake"; done; fi
    done
    rm -rf "$th"
else skip "node isn't installed"; fi

echo "Qt's JavaScript engine runs the same modules"
# every module in lib/ must be imported by the check (a new one is easy to forget)
for m in config/quickshell/lib/*.mjs; do
    grep -q "lib/$(basename "$m")\"" tests/qml/modules.qml || bad "tests/qml/modules.qml doesn't import $(basename "$m")"
done
qml=$(qtbin qml)
if [ -n "$qml" ] && have node; then
    qt=$(QT_QPA_PLATFORM=offscreen timeout 20 "$qml" tests/qml/modules.qml 2>&1 | sed -n 's/.*RESULT //p')
    js=$(node --input-type=module -e '
        import * as C from "./config/quickshell/lib/colour.mjs"; import * as T from "./config/quickshell/lib/text.mjs"
        console.log(JSON.stringify({ accents: [["#5d0d09","#1a1110"],["#2a568f","#111318"],["#d66c4c","#fff8f6"],["#808080","#101010"]].map(p => C.readableAccent(p[0], p[1])),
          text: C.textOn("#d66c4c","#1a110f","#f1dfda"), third: C.thirdAccent("#d66c4c","#c9c5a0","#3e79a3","scheme-content",true),
          typo: T.oneTypo("firefox","fierfox"), calc: T.calc("2^10 + sqrt(16)"), fromQt: C.readableAccent("#5d0d09","#1a1110") }))')
    if [ -n "$qt" ] && [ "$qt" = "$js" ]; then ok "Qt and Node agree"; else bad "Qt: ${qt:-nothing}  Node: $js"; fi
else skip "needs Qt's qml tool and node"; fi

echo "The native plugin builds"
if [ "$quick" = 1 ]; then skip "--quick"
elif have cmake; then
    b=$(mktemp -d)
    if out=$(cmake -S native -B "$b" -DCMAKE_BUILD_TYPE=Release -DETHER_QML_DIR="$b/qml" 2>&1 && cmake --build "$b" -j"$(nproc)" 2>&1); then
        w=$(echo "$out" | grep -c "warning:")
        [ "$w" = 0 ] && ok "built, no warnings ($(echo "$out" | grep -E 'Visualiser|Clipboard' | sed 's/^-- //' | tr '\n' ',' | sed 's/,$//'))" \
                     || { bad "built with $w warnings"; echo "$out" | grep -A3 "warning:" | head -30; }
    else bad "build failed"; echo "$out" | grep -E "error|Error" | head -20; fi
    rm -rf "$b"
else skip "cmake isn't installed"; fi

echo
printf '%s passed, %s failed, %s skipped\n' "$passed" "$failed" "$skipped"
[ "$failed" = 0 ]
