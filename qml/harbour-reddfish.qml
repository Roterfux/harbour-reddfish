import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6
import "pages"
import "js/store.js" as Store
import "js/reader.js" as Reader

ApplicationWindow {
    id: app

    // Settings (menu page): NSFW posts at all, and if shown, blurred until tapped.
    property bool showNsfw: Store.get("showNsfw", "0") === "1"
    property bool blurNsfw: Store.get("blurNsfw", "1") === "1"
    onShowNsfwChanged: Store.set("showNsfw", showNsfw ? "1" : "0")
    onBlurNsfwChanged: Store.set("blurNsfw", blurNsfw ? "1" : "0")
    // Setting: videos start by themselves on screen; off = tap to play.
    property bool autoplayVideos: Store.get("autoplayVideos", "1") === "1"
    onAutoplayVideosChanged: Store.set("autoplayVideos", autoplayVideos ? "1" : "0")

    // One video player for the whole app; the card on screen borrows it (MediaImage).
    // It plays reddit's MP4 files, not the HLS stream: HLS flooded GStreamer pad-probe
    // assertions and crashed (Qt 5.6 + GStreamer 1.26). The MP4 has no sound, so sound is a
    // second player with reddit's audio file, started at the video's position on unmute.
    // File names differ by age of the post: try each until one loads.
    property alias player: player
    property var playerOwner: null
    property bool soundOn: false
    property string videoBase: ""         // https://v.redd.it/<id>/
    property int videoTry: 0
    property int audioTry: 0
    readonly property var videoFiles: ["CMAF_480.mp4", "DASH_480.mp4", "CMAF_360.mp4", "DASH_360.mp4",
                                       "DASH_240.mp4", "CMAF_720.mp4", "DASH_720.mp4"]
    readonly property var audioFiles: ["CMAF_AUDIO_128.mp4", "DASH_AUDIO_128.mp4", "DASH_audio.mp4",
                                       "CMAF_AUDIO_64.mp4", "DASH_AUDIO_64.mp4"]

    property bool direct: false           // one file with its own sound (redgifs), no audio player

    function playVideo(base) {
        if (base !== videoBase) {
            videoBase = base
            direct = false
            videoTry = 0
            audioTry = 0
            audio.source = ""
            player.muted = true
            player.source = base + videoFiles[0]
        }
        player.play()
        if (soundOn) startAudio()
    }
    function playDirect(url) {
        if (url !== videoBase) {
            videoBase = url
            direct = true
            audio.source = ""
            player.source = url
        }
        player.muted = !soundOn
        player.play()
    }
    function pauseVideo() {
        player.pause()
        audio.pause()
    }
    function setSound(on) {
        soundOn = on
        if (direct) player.muted = !on
        else if (on) startAudio()
        else audio.pause()
    }
    function startAudio() {
        if (direct || audioTry >= audioFiles.length || videoBase === "") return
        if (String(audio.source) === "") audio.source = videoBase + audioFiles[audioTry]
        audio.seek(player.position)
        audio.play()
    }

    MediaPlayer {
        id: player
        autoPlay: true
        muted: true
        onError: if (!app.direct && ++app.videoTry < app.videoFiles.length) {
            source = app.videoBase + app.videoFiles[app.videoTry]; play()
        }
        // No looping: seek(0) at the end crashed GStreamer (idle crash with looped video).
        // The video stops; a tap plays it again from the start.
        onStatusChanged: if (status === MediaPlayer.EndOfMedia) audio.stop()
    }

    // ---- save picture / video (C++ saver, ~/Pictures|Videos/Reddfish) ----

    // "" if the post has nothing to save, else "image" or "video".
    function mediaKind(p) {
        if (!p) return ""
        if (p.hls || p.redgifs) return "video"
        if (p.gallery || p.preview || Reader.isImage(p) || Reader.fullFromThumb(p.thumb)) return "image"
        return ""
    }
    function fileName(url, fallback) {
        var m = /\/([^\/?#]+\.[A-Za-z0-9]{2,4})(?:[?#]|$)/.exec(url)
        return m ? m[1] : fallback
    }
    // galleryIndex: picture shown in a gallery strip (0 if none).
    function saveMedia(p, galleryIndex) {
        if (p.redgifs) {
            redgifsUrl(p.redgifs, function(u) { saver.save([u], true, p.redgifs + ".mp4") })
        } else if (p.hls) {
            var base = Reader.videoBase(p.hls)
            // best quality first for keeping; reddit's file has no sound (sound is a separate file)
            var files = ["CMAF_720.mp4", "DASH_720.mp4"].concat(videoFiles)
            saver.save(files.map(function(f) { return base + f }), true,
                       base.split("/")[3] + ".mp4")
        } else {
            var g = p.gallery ? String(p.gallery).split("|") : []
            var url = g.length ? g[Math.min(galleryIndex || 0, g.length - 1)]
                    : Reader.isImage(p) ? p.url
                    : Reader.fullFromThumb(p.thumb) || p.preview
            saver.save([url], false, fileName(url, p.name + ".jpg"))
        }
        saveNotice.text = "Saving…"
        saveNotice.show()
    }
    Connections {
        target: saver
        onSaved: { saveNotice.text = "Saved to " + path.replace(/^\/home\/[^\/]+\//, "~/"); saveNotice.show() }
        onFailed: { saveNotice.text = "Saving failed: " + error; saveNotice.show() }
    }
    Notice { id: saveNotice }

    // Redgifs: their public API gives a temporary token, then a direct MP4 per id.
    property string redgifsToken: ""
    property var redgifsCache: ({})
    function redgifsUrl(id, cb) {
        if (redgifsCache[id]) { cb(redgifsCache[id]); return }
        var get = function(url, auth, done) {
            var x = new XMLHttpRequest()
            x.open("GET", url)
            if (auth) x.setRequestHeader("Authorization", "Bearer " + auth)
            x.onreadystatechange = function() {
                if (x.readyState !== XMLHttpRequest.DONE) return
                try { done(x.status, JSON.parse(x.responseText)) } catch (e) { done(0, null) }
            }
            x.send()
        }
        var fetchGif = function(retry) {
            get("https://api.redgifs.com/v2/gifs/" + id, redgifsToken, function(status, o) {
                if (status === 401 && retry) { redgifsToken = ""; withToken(function() { fetchGif(false) }); return }
                var u = o && o.gif && o.gif.urls ? (o.gif.urls.sd || o.gif.urls.hd) : ""
                if (u) { redgifsCache[id] = u; cb(u) }
            })
        }
        var withToken = function(next) {
            if (redgifsToken) { next(); return }
            get("https://api.redgifs.com/v2/auth/temporary", "", function(status, o) {
                if (o && o.token) { redgifsToken = o.token; next() }
            })
        }
        withToken(function() { fetchGif(true) })
    }
    MediaPlayer {
        id: audio
        onError: if (++app.audioTry < app.audioFiles.length) {
            source = app.videoBase + app.audioFiles[app.audioTry]; seek(player.position); play()
        }
    }

    // Set by BrowserPage, shown on the cover.
    property string pageTitle: "Reddfish"
    property var browser: null

    // System share menu (same pattern as Feedpond); without Sailfish.Share the link is copied.
    property var shareAction: null
    function share(title, url) {
        url = String(url).replace("://old.reddit.com", "://www.reddit.com")
        if (shareAction === null) {
            try {
                shareAction = Qt.createQmlObject(
                    'import Sailfish.Share 1.0; ShareAction { mimeType: "text/x-url" }', app, "share")
            } catch (error) {
                console.log("No share menu:", error)
                shareAction = false
            }
        }
        if (shareAction) {
            shareAction.title = "Share link"
            shareAction.resources = [{ "type": "text/x-url", "linkTitle": title, "status": url }]
            shareAction.trigger()
        } else {
            Clipboard.text = url
        }
    }

    initialPage: Component { BrowserPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
}
