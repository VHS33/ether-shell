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
    n=0; for f in config/quickshell/*.qml config/quickshell/services/*.qml config/quickshell/common/*.qml config/ether-greeter/*.qml plugins/*/*.qml; do
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

echo "ether perf reads /proc right (a pretend one)"
fp=$(mktemp -d); pp="$fp/4242"
mkdir -p "$pp/task/4242" "$pp/task/4250" "$pp/task/4251"
echo "5000.00 1.00" > "$fp/uptime"
# memory: 100 MB Qt, 60 MB NVIDIA, 30 MB working memory, 4 MB fonts, 2 MB
# Ether's plugin (196 MB); started at 1,000 s, now 5,000 s: 1h 6m ago
{
    printf '7f00-7f01 r-xp 0 0:1 1 /usr/lib/libQt6Quick.so.6\nPss: 102400 kB\n'
    printf '7f02-7f03 r-xp 0 0:1 2 /usr/lib/libnvidia-glcore.so.580\nPss: 51200 kB\n'
    printf '7f04-7f05 rw-s 0 0:1 3 /dev/nvidiactl\nPss: 10240 kB\n'
    printf '7f06-7f07 rw-p 0 0:0 0 [heap]\nPss: 20480 kB\n'
    printf '7f08-7f09 rw-p 0 0:0 0 \nPss: 10240 kB\n'
    printf '7f0a-7f0b r--p 0 0:1 4 /usr/share/fonts/inter/Inter Variable.ttf\nPss: 4096 kB\n'
    printf '7f0c-7f0d r-xp 0 0:1 5 /home/u/.local/lib/ether-shell/qml/Ether/Native/libethernative.so\nPss: 2048 kB\n'
} > "$pp/smaps"
# threads: stat (name in brackets, with a space in one) and wake-ups
stat() { echo "$1 ($2) S 1 1 1 0 -1 0 0 0 0 0 $3 $4 0 0 20 0 1 0 100000 0 0"; }
setthreads() {
    stat 4242 quickshell "$1" 0 > "$pp/task/4242/stat"; printf 'voluntary_ctxt_switches:\t%s\n' "$2" > "$pp/task/4242/status"
    stat 4250 QSGRenderThread "$3" 0 > "$pp/task/4250/stat"; printf 'voluntary_ctxt_switches:\t%s\n' "$4" > "$pp/task/4250/status"
    stat 4251 "Thread (pooled)" 0 0 > "$pp/task/4251/stat"; printf 'voluntary_ctxt_switches:\t0\n' > "$pp/task/4251/status"
}
setthreads 1000 5000 500 2000
cp "$pp/task/4242/stat" "$pp/stat"
# half a second in: 0.1 s of main-thread time and 0.05 s of drawing (ticks
# are hundredths), 100 and 300 wake-ups; over 2 s that's 5 % and 2.5 %
( sleep 0.5; setthreads 1010 5100 505 2300 ) &
out=$(ETHER_PROC="$fp" ETHER_PID=4242 sh local/bin/ether perf 2 2>&1)
wait
want='Total +196 MB
Qt \(the toolkit\) +100 MB
graphics driver +60 MB
working memory +30 MB
fonts +4 MB
Ether native plugin +2 MB
CPU +7.5 % of one core
Wake-ups +200 a second
main \(QML, JavaScript\) +5.0 % +50 wake-ups
drawing +2.5 % +150 wake-ups
running for 1h 6m'
missing=$(printf '%s\n' "$want" | while IFS= read -r w; do printf '%s\n' "$out" | grep -Eq "$w" || echo "$w"; done)
if [ -z "$missing" ]; then ok "memory by kind, CPU and wake-ups by thread"
else bad "ether perf got these wrong: $(echo "$missing" | tr '\n' ';')"; echo "$out" | head -30; fi
printf '%s\n' "$out" | grep -q "Thread" && bad "ether perf showed an idle thread as busy"
rm -rf "$fp"

echo "no QML object has the same handler twice (it wouldn't load)"
if out=$(gawk -f tests/dup-handlers.awk config/quickshell/*.qml config/quickshell/services/*.qml config/quickshell/common/*.qml config/ether-greeter/*.qml plugins/*/*.qml 2>&1); then
    ok "no handler set twice"
else
    bad "a handler set twice: $out"
fi

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
