import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/reader.js" as Reader

// One comment (or "load more" row) in the native post view.
ListItem {
    id: item
    visible: !model.hidden
    contentHeight: model.hidden ? 0 : col.height + Theme.paddingMedium * 2
    menu: model.isMore ? null : voteMenu

    signal vote(string which)
    signal link(string url)

    property int indent: Math.min(model.depth, 8) * Theme.paddingLarge

    Component {
        id: voteMenu
        ContextMenu {
            MenuItem {
                text: model.likes === 1 ? "Remove upvote" : "Upvote"
                onClicked: item.vote("up")
            }
            MenuItem {
                text: model.likes === -1 ? "Remove downvote" : "Downvote"
                onClicked: item.vote("down")
            }
        }
    }

    Rectangle {
        visible: model.depth > 0
        x: Theme.horizontalPageMargin + item.indent - Theme.paddingMedium
        y: Theme.paddingSmall
        width: 2
        height: parent.height - 2 * Theme.paddingSmall
        color: Theme.highlightColor
        opacity: 0.3
    }

    Column {
        id: col
        x: Theme.horizontalPageMargin + item.indent
        y: Theme.paddingMedium
        width: parent.width - x - Theme.horizontalPageMargin
        spacing: Theme.paddingSmall / 2

        Label {
            visible: model.isMore
            width: parent.width
            wrapMode: Text.Wrap
            text: model.body || "load more comments"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
        }

        Label {
            visible: !model.isMore
            width: parent.width
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: model.submitter ? Theme.highlightColor : Theme.secondaryColor
            text: "u/" + model.author
                  + (model.scoreHidden ? "" : "  ·  " + (model.likes === 1 ? "▲" : (model.likes === -1 ? "▼" : ""))
                                              + Reader.num(model.score))
                  + "  ·  " + Reader.ago(model.time)
                  + (model.collapsed ? "  [+]" : "")
        }

        Label {
            visible: !model.isMore && !model.collapsed
            width: parent.width
            text: model.body
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.primaryColor
            linkColor: Theme.highlightColor
            onLinkActivated: item.link(link)
        }
    }
}
