pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The AI assistant: the providers and their models (Settings > AI
// assistant), your API keys (one file per provider in ~/.config/ether/ai/,
// readable only by you; never in settings.json), the conversation, and
// sending it with the reply streaming
// in.  Use it anywhere as Assistant.aiMessages, .aiSend(text)... (import
// qs.services).
//
// Over the network: when you send a message, the conversation so far and
// your key, to the provider you chose (and nowhere else).
Singleton {
    id: assistantSvc

    readonly property var aiProviders: ({
        anthropic: { name: "Anthropic", product: "Claude", model: "claude-sonnet-5",
                     keyUrl: "console.anthropic.com" },
        gemini:    { name: "Google", product: "Gemini", model: "gemini-2.5-flash",
                     keyUrl: "aistudio.google.com" },
        openai:    { name: "OpenAI", product: "ChatGPT", model: "gpt-4.1-mini",
                     keyUrl: "platform.openai.com" }
    })
    readonly property string aiProvider: aiProviders[Config.cfg.aiProvider] ? Config.cfg.aiProvider : "anthropic"
    function aiModelFor(p) { return Config.cfg["aiModel_" + p] || aiProviders[p].model }
    readonly property string aiModel: aiModelFor(aiProvider)
    readonly property string aiSystem:
        "You are the assistant built into Ether Shell, a desktop shell on the user's Arch Linux " +
        "computer running Hyprland. Be concise and practical. Use Markdown for lists and code. " +
        "The user's shell is fish."

    // which providers have a key saved
    property var aiKeys: ({})
    function refreshAiKeys() { aiKeyList.running = true }
    Process {
        id: aiKeyList
        running: true
        // (the project was called Aether; its folder is moved across once)
        command: ["sh", "-c", "c=\"$HOME/.config\"; " +
            "[ -d \"$c/aether\" ] && [ ! -e \"$c/ether\" ] && mv \"$c/aether\" \"$c/ether\"; " +
            "ls \"$c/ether/ai\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const k = {}
                for (const f of text.split("\n")) if (f.endsWith(".key")) k[f.slice(0, -4)] = true
                assistantSvc.aiKeys = k
            }
        }
    }
    property string aiKeyPending: ""
    Process {
        id: aiKeyWrite
        stdinEnabled: true
        onStarted: { write(assistantSvc.aiKeyPending); assistantSvc.aiKeyPending = ""; stdinEnabled = false }
        onExited: { stdinEnabled = true; assistantSvc.refreshAiKeys() }
    }
    function saveAiKey(p, key) {
        key = (key || "").trim()
        if (!aiProviders[p] || key === "") return
        aiKeyPending = key
        aiKeyWrite.command = ["sh", "-c",
            'umask 077; d="$HOME/.config/ether/ai"; mkdir -p "$d"; cat > "$d/$1.key"', "sh", p]
        aiKeyWrite.running = true
    }
    Process { id: aiKeyRemove; onExited: assistantSvc.refreshAiKeys() }
    function removeAiKey(p) {
        if (!aiProviders[p]) return
        aiKeyRemove.command = ["sh", "-c", 'rm -f "$HOME/.config/ether/ai/$1.key"', "sh", p]
        aiKeyRemove.running = true
    }

    // the conversation: plain values; the reply being written is kept apart
    // so the list doesn't rebuild on every word
    property var aiMessages: []          // { role: "user" | "assistant", text, error }
    property string aiStreaming: ""
    property bool aiBusy: false
    property string aiRaw: ""            // anything that wasn't a stream event (errors)
    function aiNew() {
        if (aiBusy) aiStop()
        aiMessages = []
        aiStreaming = ""
    }
    function aiStop() {
        if (!aiBusy) return
        aiProc.running = false
    }
    function aiBody() {
        const p = aiProvider, msgs = aiMessages.filter(m => !m.error)
        if (p === "gemini")
            return JSON.stringify({
                systemInstruction: { parts: [{ text: aiSystem }] },
                contents: msgs.map(m => ({ role: m.role === "assistant" ? "model" : "user",
                                           parts: [{ text: m.text }] })) })
        if (p === "openai")
            return JSON.stringify({ model: aiModel, stream: true,
                messages: [{ role: "system", content: aiSystem }]
                          .concat(msgs.map(m => ({ role: m.role, content: m.text }))) })
        return JSON.stringify({ model: aiModel, max_tokens: 4096, stream: true, system: aiSystem,
                                messages: msgs.map(m => ({ role: m.role, content: m.text })) })
    }
    function aiSend(text) {
        text = (text || "").trim()
        if (text === "" || aiBusy) return
        aiMessages = aiMessages.concat([{ role: "user", text: text }])
        aiStreaming = ""
        aiRaw = ""
        aiBusy = true
        aiPendingBody = aiBody()
        aiProc.command = ["sh", "-c",
            'p="$1"; model="$2"; k=$(cat "$HOME/.config/ether/ai/$p.key" 2>/dev/null); ' +
            '[ -n "$k" ] || { echo ETHER_NOKEY; exit 0; }; ' +
            'h=$(mktemp); trap \'rm -f "$h"\' EXIT; ' +
            'case "$p" in ' +
            '  anthropic) printf "x-api-key: %s\\nanthropic-version: 2023-06-01\\ncontent-type: application/json\\n" "$k" > "$h"; ' +
            '             url="https://api.anthropic.com/v1/messages";; ' +
            '  openai)    printf "Authorization: Bearer %s\\ncontent-type: application/json\\n" "$k" > "$h"; ' +
            '             url="https://api.openai.com/v1/chat/completions";; ' +
            '  gemini)    printf "x-goog-api-key: %s\\ncontent-type: application/json\\n" "$k" > "$h"; ' +
            '             url="https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse";; ' +
            'esac; ' +
            'curl -sN --max-time 180 -H @"$h" --data-binary @- "$url"',
            "sh", aiProvider, /^[\w.:-]+$/.test(aiModel) ? aiModel : aiProviders[aiProvider].model]
        aiProc.running = true
    }
    property string aiPendingBody: ""
    Process {
        id: aiProc
        stdinEnabled: true
        onStarted: { write(assistantSvc.aiPendingBody); assistantSvc.aiPendingBody = ""; stdinEnabled = false }
        stdout: SplitParser {
            onRead: raw => {
                // the blank line between streamed events can arrive stuck to
                // the front of the next line ("\ndata: ..."), depending on
                // how the reply is split in transit; some servers end lines
                // with \r\n too
                const line = raw.replace(/^[\r\n]+/, "").replace(/\r$/, "")
                if (line === "ETHER_NOKEY") {
                    assistantSvc.aiRaw = "ETHER_NOKEY"
                    return
                }
                if (!line.startsWith("data:")) {
                    if (line.trim() !== "" && !line.startsWith("event:")) assistantSvc.aiRaw += line + "\n"
                    return
                }
                const payload = line.slice(5).trim()
                if (payload === "" || payload === "[DONE]") return
                try {
                    const j = JSON.parse(payload)
                    let d = ""
                    if (assistantSvc.aiProvider === "anthropic") {
                        if (j.type === "content_block_delta" && j.delta) d = j.delta.text || ""
                        else if (j.type === "error") assistantSvc.aiRaw += payload
                    } else if (assistantSvc.aiProvider === "openai") {
                        d = j.choices && j.choices[0] && j.choices[0].delta ? (j.choices[0].delta.content || "") : ""
                        if (j.error) assistantSvc.aiRaw += payload
                    } else {
                        const parts = j.candidates && j.candidates[0] && j.candidates[0].content
                                      ? (j.candidates[0].content.parts || []) : []
                        d = parts.map(p => p.text || "").join("")
                        if (j.error) assistantSvc.aiRaw += payload
                    }
                    if (d) assistantSvc.aiStreaming += d
                } catch (e) {}
            }
        }
        onExited: {
            stdinEnabled = true
            let msg = null
            if (assistantSvc.aiStreaming !== "") {
                msg = { role: "assistant", text: assistantSvc.aiStreaming }
            } else if (assistantSvc.aiRaw === "ETHER_NOKEY") {
                msg = { role: "assistant", error: true,
                        text: "No API key saved for " + assistantSvc.aiProviders[assistantSvc.aiProvider].name
                              + ". Add one in Settings, under AI assistant." }
            } else {
                let why = ""
                try {
                    const j = JSON.parse(assistantSvc.aiRaw.trim())
                    why = (j.error && (j.error.message || j.error)) || j.message || ""
                } catch (e) {
                    why = assistantSvc.aiRaw.trim().slice(0, 300)
                }
                msg = { role: "assistant", error: true,
                        text: why ? "The request failed: " + why
                                  : "No reply came back. Check your connection and API key." }
            }
            assistantSvc.aiMessages = assistantSvc.aiMessages.concat([msg])
            assistantSvc.aiStreaming = ""
            assistantSvc.aiBusy = false
        }
    }
}
