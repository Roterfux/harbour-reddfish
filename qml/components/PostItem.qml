import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/reader.js" as Reader

// One post card in the native feed, laid out like Infinity's card view:
// meta line, title, big media, action row.
ListItem {
    id: item
    contentHeight: card.height + Theme.paddingMedium

    signal vote(string which)
    signal openSub(string name)
    signal openPost()
    signal openUser(string name)
    signal copyDebug()
    signal needMedia()                    // on screen without picture/video, but the site can expand it
    onClicked: openPost()
    // Up to 3 screens below the visible area: fetch missing media before the card shows up.
    readonly property bool nearView: {
        var v = ListView.view
        if (!v) return false
        return y + height > v.contentY && y < v.contentY + 4 * v.height
    }

    function checkMedia() { if (nearView && !bigImage && model.hasExpando && !model.expandTried) needMedia() }
    onNearViewChanged: checkMedia()
    Component.onCompleted: checkMedia()
    property bool showSubreddit: true
    property bool autoplay: false

    // Video plays only while the card's middle is on screen.
    readonly property bool inView: {
        var v = ListView.view
        if (!v) return false
        var mid = y + height / 2
        return mid > v.contentY && mid < v.contentY + v.height
    }
    // Start video only after the card stayed on screen a moment: creating and dropping video
    // pipelines while flicking fast is what crashed (suspected).
    property bool settled: false
    onInViewChanged: if (!inView) settled = false
    Timer {
        interval: 400
        running: item.inView && !item.settled
        onTriggered: item.settled = true
    }

    readonly property bool bigImage: media.visible
    readonly property bool sideThumb: !bigImage && model.thumb !== "" && !model.nsfw
    // (inside the Repeater below, `model` means the Repeater's own model, so read post fields here)
    readonly property bool isNsfw: model.nsfw
    readonly property var tagList: [model.nsfw ? "NSFW" : "", model.flair, bigImage || model.isSelf ? "" : model.domain]
                                   .filter(function(s) { return s !== "" })

    menu: ContextMenu {
        MenuItem {
            text: "Share"
            onClicked: app.share(model.title, model.permalink)
        }
        MenuItem {
            visible: app.mediaKind(model) !== ""
            text: app.mediaKind(model) === "video" ? "Save video" : "Save image"
            onClicked: app.saveMedia(model, media.galleryIndex)
        }
        MenuItem {
            text: "Copy debug info"
            onClicked: item.copyDebug()
        }
        MenuItem {
            text: "Go to r/" + model.subreddit
            onClicked: item.openSub(model.subreddit)
        }
        MenuItem {
            visible: model.author !== "" && model.author !== "[deleted]"
            text: "Go to u/" + model.author
            onClicked: item.openUser(model.author)
        }
        MenuItem {
            visible: !model.isSelf
            text: "Open link in browser"
            onClicked: Qt.openUrlExternally(model.url)
        }
    }

    Rectangle {
        anchors.fill: card
        radius: Theme.paddingMedium
        color: Theme.rgba(Theme.highlightBackgroundColor, Theme.colorScheme === Theme.DarkOnLight ? 0.12 : 0.08)
    }

    Column {
        id: card
        x: Theme.paddingSmall
        y: Theme.paddingSmall
        width: parent.width - 2 * x
        spacing: Theme.paddingSmall

        Item { width: 1; height: Theme.paddingSmall }

        Label {
            x: Theme.paddingLarge
            width: parent.width - 2 * x
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            textFormat: Text.StyledText
            text: (item.showSubreddit ? "<font color='" + Theme.highlightColor + "'><b>r/" + model.subreddit
                                        + "</b></font> · " : "")
                  + "u/" + model.author + " · " + Reader.ago(model.time)
                  + (model.stickied ? " · 📌" : "")
        }

        Item {
            x: Theme.paddingLarge
            width: parent.width - 2 * x
            height: Math.max(title.height, item.sideThumb ? thumb.height : 0)

            Label {
                id: title
                width: parent.width - (item.sideThumb ? thumb.width + Theme.paddingMedium : 0)
                text: model.title
                wrapMode: Text.Wrap
                maximumLineCount: 5
                truncationMode: TruncationMode.Elide
                font.pixelSize: Theme.fontSizeMedium
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }

            // Bigger side thumbnail for link posts (reddit only gives small thumbs for these).
            Image {
                id: thumb
                visible: item.sideThumb
                anchors.right: parent.right
                source: visible ? model.thumb : ""
                width: parent.width * 0.4     // shortcut: reddit sends only 140px here, so it's soft
                height: width * 0.5625        // fixed box: no jump when it loads
                smooth: true
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true
            }
        }

        // Tags as small chips: NSFW (red), flair, link domain.
        Flow {
            x: Theme.paddingLarge
            width: parent.width - 2 * x
            spacing: Theme.paddingSmall
            visible: item.tagList.length > 0
            Repeater {
                model: item.tagList
                Rectangle {
                    readonly property bool nsfw: index === 0 && item.isNsfw
                    width: Math.min(tag.implicitWidth + 2 * Theme.paddingSmall, card.width - 2 * Theme.paddingLarge)
                    height: tag.implicitHeight + Theme.paddingSmall / 2
                    radius: height / 2
                    color: nsfw ? Theme.rgba("#e0303a", 0.25) : Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                    Label {
                        id: tag
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 2 * Theme.paddingSmall)
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeTiny
                        color: parent.nsfw ? (Theme.colorScheme === Theme.DarkOnLight ? "#b0101a" : "#ff6a70")
                                           : Theme.highlightColor
                        text: modelData
                    }
                }
            }
        }

        MediaImage {
            id: media
            post: model
            autoplay: item.autoplay && item.settled
        }

        VoteBar {
            likes: model.likes
            score: model.score
            comments: model.comments
            onVote: item.vote(which)
            onOpenComments: item.openPost()
            onShare: app.share(model.title, model.permalink)
        }
    }
}
