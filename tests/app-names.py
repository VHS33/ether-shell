#!/usr/bin/env python3
# Every app.<name> the shell's other files use must exist on shell.qml (a
# property, function, signal or id).  A missing one loads fine and fails
# only when that line runs, so no other check sees it; moving code into
# services/ (with forwards left in shell.qml) makes it easy to miss one.
import re, glob, sys, os
q = os.path.join(os.path.dirname(__file__), "..", "config", "quickshell")
s = open(os.path.join(q, "shell.qml")).read()
defined = set(re.findall(r"^\s*(?:readonly\s+)?(?:required\s+)?property\s+[\w<>.]+\s+(\w+)", s, re.M)) \
        | set(re.findall(r"^\s*function\s+(\w+)", s, re.M)) \
        | set(re.findall(r"^\s*signal\s+(\w+)", s, re.M)) | set(re.findall(r"\bid:\s*(\w+)", s))
builtin = {"width", "height", "x", "y", "visible", "opacity", "children", "data", "parent", "objectName", "state", "enabled"}
missing = {}
for f in sorted(glob.glob(os.path.join(q, "*.qml")) + glob.glob(os.path.join(q, "modules", "*", "*.qml"))):
    if f.endswith("shell.qml"): continue
    for n in re.findall(r"\bapp\.(\w+)", open(f).read()):
        if n not in defined and n not in builtin: missing.setdefault(n, set()).add(os.path.basename(f))
for n, fs in sorted(missing.items()): print("app.%s (used in %s) isn't on the shell" % (n, ", ".join(sorted(fs))))

# A service's id must not be reused as a local name inside it: in that
# function, "svc.x" would then mean the local, not the service (step 161's
# `const b = ...` in Brightness, whose id was b).
shadowed = []
for f in sorted(glob.glob(os.path.join(q, "services", "*.qml")) + glob.glob(os.path.join(q, "common", "*.qml"))):
    t = open(f).read()
    m = re.search(r"^Singleton \{\n\s*id: (\w+)", t, re.M)
    if not m: continue
    i = m.group(1)
    for x in re.finditer(r"(?:\b(?:const|let|var)\s+%s\b|[(,]\s*%s\s*[,)]\s*(?:=>|\{)|\b%s\s*=>)" % (i, i, i), t):
        shadowed.append("%s:%d reuses the service's id %s as a local name" % (os.path.basename(f), t.count("\n", 0, x.start()) + 1, i))
for s_ in shadowed: print(s_)

# Components from the shell's own folders must be importable where they're
# used: the main folder's need `import qs` from a subfolder, and a module
# folder's need `import qs.modules.<name>` from anywhere else. Without it
# the file can't load (and with it, often, the whole shell).
def types_in(d): return {os.path.basename(f)[:-4]: d for f in glob.glob(os.path.join(q, d, "*.qml")) if os.path.basename(f)[0].isupper()}
where = types_in("")
for d in glob.glob(os.path.join(q, "modules", "*")) + glob.glob(os.path.join(q, "common", "*")):
    if os.path.isdir(d): where.update(types_in(os.path.relpath(d, q)))
unimported = []
for f in sorted(glob.glob(os.path.join(q, "*.qml")) + glob.glob(os.path.join(q, "modules", "*", "*.qml")) + glob.glob(os.path.join(q, "common", "*", "*.qml"))):
    t = open(f).read(); here = os.path.relpath(os.path.dirname(f), q); here = "" if here == "." else here
    imports = set(re.findall(r"^import\s+(qs(?:\.[\w.]+)?)\s*$", t, re.M))
    code = "\n".join("" if l.strip().startswith("//") else l for l in t.split("\n"))
    inline = set(re.findall(r"^\s*component\s+(\w+)\s*:", code, re.M))     # its own components
    for name in sorted(set(re.findall(r"(?<![\w.])([A-Z]\w*)\s*\{", code)) - inline):
        d = where.get(name)
        if d is None or d == here or name == os.path.basename(f)[:-4]: continue
        need = "qs" if d == "" else "qs." + d.replace(os.sep, ".")
        if need not in imports: unimported.append("%s uses %s but doesn't import %s" % (os.path.relpath(f, q), name, need))
for u in unimported: print(u)

# Relative paths (import "../lib/x.mjs", Qt.resolvedUrl("emoji.json")) are
# relative to the file that has them, so moving a file can leave one
# pointing nowhere: that fails only when it's used (emoji search, say).
broken = []
for f in sorted(glob.glob(os.path.join(q, "*.qml")) + glob.glob(os.path.join(q, "*", "*.qml")) + glob.glob(os.path.join(q, "modules", "*", "*.qml")) + glob.glob(os.path.join(q, "common", "*", "*.qml"))):
    t = open(f).read()
    loaded = re.findall(r'\bsource\s*:\s*"([^"+]+\.qml)"', t) + re.findall(r'Qt\.createComponent\(\s*"([^"+]+\.qml)"\s*\)', t)
    for rel in re.findall(r'^import\s+"([^"]+)"', t, re.M) + re.findall(r'Qt\.resolvedUrl\(\s*"([^"]+)"\s*\)', t) + loaded:
        if "://" in rel: continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(f), rel))):
            broken.append("%s: \"%s\" isn't there" % (os.path.relpath(f, q), rel))
for b in broken: print(b)

# A component given `name: name` (PageGlass { win: win }): newer Qt can read
# the right-hand name as the component's own property, not the id around
# it, and the component then gets nothing (step 171: Settings pages lost
# the shell, with white cards and 0% everywhere). Give the property
# another name.
selfbound = []
for f in sorted(glob.glob(os.path.join(q, "*.qml")) + glob.glob(os.path.join(q, "*", "*.qml")) + glob.glob(os.path.join(q, "*", "*", "*.qml"))):
    for i, l in enumerate(open(f).read().split("\n"), 1):
        if l.strip().startswith("//"): continue
        for m in re.finditer(r"\b[A-Z]\w*\s*\{([^{}]*)", l):
            for b in re.finditer(r"(?:^|[;{\s])([a-z]\w*)\s*:\s*\1\s*(?=;|$|\})", m.group(1)):
                selfbound.append("%s:%d binds %s: %s" % (os.path.relpath(f, q), i, b.group(1), b.group(1)))
for b_ in selfbound: print(b_)
sys.exit(1 if (missing or shadowed or unimported or broken or selfbound) else 0)
