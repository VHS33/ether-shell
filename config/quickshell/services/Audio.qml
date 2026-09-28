pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Sound: the speakers or headphones in use (sink) and the microphone
// (source), kept live for the whole shell (PwObjectTracker: without it their
// volume and mute aren't read).  Use it anywhere as Audio.sink.audio.volume,
// Audio.source.audio.muted... (import qs.services).  Nothing here goes over
// the network.
Singleton {
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
}
