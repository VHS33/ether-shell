import QtQuick
import QtMultimedia

// A moving wallpaper, playing over its still (Backdrop): a video or animated
// GIF, looping, silent (no sound stream at all), cropped to fill the screen
// like a picture.  It fades in once its first frame is up, and holds still
// whenever `playing` is false (Backdrop decides: fullscreen apps, games,
// the lock screen, battery, Settings > Wallpaper > Moving wallpapers).
// Its own file, loaded only for a moving wallpaper: without Qt Multimedia
// (qt6-multimedia) it fails to load alone, and the still stays.
Item {
    id: live
    property string source: ""              // the file
    property bool playing: true
    property int fade: 500
    // up: its first frame is showing
    readonly property bool up: player.mediaStatus === MediaPlayer.BufferedMedia
                               || player.mediaStatus === MediaPlayer.EndOfMedia
                               || (player.playbackState !== MediaPlayer.StoppedState && player.mediaStatus === MediaPlayer.LoadedMedia)

    opacity: up ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: live.fade } }

    MediaPlayer {
        id: player
        source: live.source ? "file://" + live.source.split("/").map(encodeURIComponent).join("/") : ""
        loops: MediaPlayer.Infinite
        videoOutput: out
        // no audioOutput: a wallpaper makes no sound, and opens no stream
        onSourceChanged: if (live.playing) play()
        onErrorOccurred: (error, text) => console.log("moving wallpaper: " + text)
    }
    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }
    onPlayingChanged: playing ? player.play() : player.pause()
    Component.onCompleted: if (playing) player.play()
}
