// models.mjs  (Ether Shell)
// Lists for Repeaters that update in place.  Given a plain list, a Repeater
// destroys and recreates every item at each change; Quickshell's ScriptModel
// keeps the items that are still there, matched by a key (objectProp).  The
// key must be unique, or ScriptModel's behaviour is undefined, so this gives
// every item one: what identifies it, with repeats numbered ("chrome",
// "chrome#1"...).
//
//   model: ScriptModel { values: Models.keyed(list, x => x.id); objectProp: "_key" }
//
// (Object.assign, not { ...x }: Qt's JavaScript engine doesn't read spread.)
export function keyed(list, keyOf) {
    const seen = {}
    const out = []
    for (const v of (list || [])) {
        let k = String(keyOf(v))
        if (seen[k] === undefined) seen[k] = 0
        else { seen[k] += 1; k = k + "#" + seen[k] }
        out.push(Object.assign({}, v, { _key: k }))
    }
    return out
}
