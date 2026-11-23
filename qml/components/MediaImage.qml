import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6
import "../js/reader.js" as Reader

// Full-width media of a post: reddit's preview picture (or the full image), and for reddit
// videos the app's shared player while `autoplay` is true. Tap the video for sound.
Item {
    id: media
    property var post: null
    property real maxHeightRatio: 1.25
    property bool autoplay: false

    // NSFW: blurred until tapped; video starts only after that.
    property bool revealed: false
    readonly property bool hidden: post !== null && post.nsfw && app.blurNsfw && !revealed

    readonly property string src: !post ? ""
                                : post.preview ? post.preview
                                : Reader.isImage(post) ? post.url
                                : Reader.fullFromThumb(post.thumb)
    readonly property string videoUrl: post && !hidden ? Reader.videoBase(post.hls) : ""
    readonly property string redgifsId: post && !hidden && post.redgifs ? post.redgifs : ""
    readonly property bool hasVideo: videoUrl !== "" || redgifsId !== ""
    // `autoplay` = on screen and allowed; with the setting off, a tap (manual) starts it.
    property bool manual: false
    readonly property bool wanted: autoplay && hasVideo && (app.autoplayVideos || manual)
    onWantedChanged: wanted ? claim() : release()
    onAutoplayChanged: if (!autoplay) manual = false
    readonly property bool owns: app.playerOwner === media
    readonly property bool playing: owns && app.player.playbackState === MediaPlayer.PlayingState
    // Box shape is fixed before anything loads (no jumping cards): the size reddit's HTML states,
    // else 4:3 with the picture fitted inside.
    readonly property bool knownShape: post !== null && post.ratio > 0
    readonly property real aspect: knownShape ? post.ratio : 0.75
    readonly property real ratioCap: hasVideo ? Math.max(maxHeightRatio, 1.8) : maxHeightRatio
    // Reddit-hosted media the site loads only on expand: keep the box from the start.
    readonly property bool reserved: post !== null && post.hasExpando === true && post.thumb !== ""
                                     && /(^|\.)redd\.it$|^reddit\.com$/.test(post.domain)

    Component.onCompleted: if (wanted) claim()
    Component.onDestruction: release()

    function claim() {
        if (!hasVideo) return
        app.playerOwner = media
        if (videoUrl !== "") {
            app.playVideo(videoUrl)
        } else {
            app.redgifsUrl(redgifsId, function(u) {
                if (media.wanted && app.playerOwner === media) app.playDirect(u)
            })
        }
    }
    function release() {
        if (app.playerOwner !== media) return
        app.pauseVideo()            // pause, not stop: no pipeline teardown on the UI thread
        app.playerOwner = null
    }

    visible: src !== "" || (post !== null && (post.hls !== "" || post.redgifs !== "")) || reserved
    width: parent ? parent.width : 0
    height: visible ? width * Math.min(aspect, ratioCap) : 0

    // The feed's small thumbnail (usually cached already) stands in until the big picture is there.
    Image {
        anchors.fill: parent
        visible: img.status !== Image.Ready && !media.playing && !media.hidden
        source: media.post && !media.hidden ? media.post.thumb : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        clip: true
        asynchronous: true
    }

    // NSFW cover: the picture decoded at 16 px and stretched = blur, no effects module needed.
    Image {
        id: blur
        anchors.fill: parent
        visible: media.hidden
        source: media.hidden ? (media.src || media.post.thumb) : ""
        sourceSize.width: 16
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        Rectangle { anchors.fill: parent; color: Theme.rgba("black", 0.35) }
        Label {
            anchors.centerIn: parent
            text: "NSFW · tap to show"
            color: "white"
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    Image {
        id: img
        anchors.fill: parent
        visible: !media.hidden
        source: media.hidden ? "" : media.src
        sourceSize.width: media.width
        fillMode: media.knownShape ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        clip: true
        asynchronous: true
    }

    // Gallery: swipe through all pictures; the first picture (img) gives the box its shape.
    readonly property var galleryUrls: post && post.gallery ? String(post.gallery).split("|") : []
    readonly property int galleryIndex: strip.visible ? strip.currentIndex : 0
    ListView {
        id: strip
        anchors.fill: parent
        visible: media.galleryUrls.length > 1 && !media.hidden
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        model: visible ? media.galleryUrls : []
        delegate: Image {
            width: strip.width
            height: strip.height
            source: modelData
            sourceSize.width: strip.width
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            Rectangle { anchors.fill: parent; z: -1; color: "black" }
        }
        Rectangle {
            anchors { right: parent.right; top: parent.top; margins: Theme.paddingMedium }
            width: count.width + 2 * Theme.paddingMedium
            height: count.height + Theme.paddingSmall
            radius: height / 2
            color: Theme.rgba("black", 0.5)
            Label {
                id: count
                anchors.centerIn: parent
                font.pixelSize: Theme.fontSizeExtraSmall
                color: "white"
                text: (strip.currentIndex + 1) + "/" + media.galleryUrls.length
            }
        }
    }

    VideoOutput {
        id: out
        anchors.fill: parent
        source: media.owns ? app.player : null
        fillMode: VideoOutput.PreserveAspectFit   // box is fixed; real frame may differ a bit
        visible: media.playing
        Rectangle { anchors.fill: parent; z: -1; color: "black" }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: (img.status === Image.Loading && media.src !== "")
                 || (media.owns && app.player.status === MediaPlayer.Loading)
    }

    // ▶ on a video that isn't playing (tap to play when autoplay is off), or one we can't play.
    Rectangle {
        visible: media.post !== null && !media.hidden && !media.playing
                 && (media.hasVideo ? !media.wanted || (media.owns && app.player.status === MediaPlayer.EndOfMedia)
                                    : media.post.isVideo)
        anchors.centerIn: parent
        width: Theme.itemSizeMedium
        height: width
        radius: width / 2
        color: Theme.rgba("black", 0.5)
        Icon {
            anchors.centerIn: parent
            source: "image://theme/icon-m-play"
        }
    }

    // Sound on/off.
    Rectangle {
        visible: media.playing
        anchors { right: parent.right; bottom: parent.bottom; margins: Theme.paddingMedium }
        width: Theme.iconSizeMedium
        height: width
        radius: width / 2
        color: Theme.rgba("black", 0.5)
        Icon {
            anchors.centerIn: parent
            width: Theme.iconSizeSmallPlus
            height: width
            source: app.soundOn ? "image://theme/icon-m-speaker" : "image://theme/icon-m-speaker-mute"
        }
    }

    // Tap: show NSFW media, or toggle sound of a playing video (instead of opening the post).
    // shortcut: "revealed" is per card instance, so it resets when the card scrolls far away.
    MouseArea {
        anchors.fill: parent
        enabled: media.playing || media.hidden || (media.hasVideo && media.autoplay)
        onClicked: {
            if (media.hidden) media.revealed = true
            else if (media.playing) app.setSound(!app.soundOn)
            else { media.manual = true; if (media.wanted) media.claim() }   // start, or replay after the end
        }
    }
}
