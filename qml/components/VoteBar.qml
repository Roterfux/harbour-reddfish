import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/reader.js" as Reader

// Infinity-style action row: ▲ score ▼ on the left, share + comment count on the right.
Item {
    id: bar
    property int likes: 0
    property int score: 0
    property int comments: 0
    signal vote(string which)
    signal openComments()
    signal share()

    width: parent ? parent.width : 0
    height: Theme.itemSizeExtraSmall

    // darker shades on light ambiences, so they stay readable
    readonly property bool light: Theme.colorScheme === Theme.DarkOnLight
    readonly property color upColor: light ? "#d4501c" : "#ff8b60"
    readonly property color downColor: light ? "#4a4ad0" : "#9494ff"

    Row {
        anchors.verticalCenter: parent.verticalCenter
        IconButton {
            icon.source: "image://theme/icon-m-up"
            icon.color: bar.likes === 1 ? bar.upColor : Theme.primaryColor
            onClicked: bar.vote("up")
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.itemSizeSmall
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeSmall
            font.bold: bar.likes !== 0
            color: bar.likes === 1 ? bar.upColor : (bar.likes === -1 ? bar.downColor : Theme.primaryColor)
            text: Reader.num(bar.score)
        }
        IconButton {
            icon.source: "image://theme/icon-m-down"
            icon.color: bar.likes === -1 ? bar.downColor : Theme.primaryColor
            onClicked: bar.vote("down")
        }
    }

    Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        IconButton {
            icon.source: "image://theme/icon-m-share"
            onClicked: bar.share()
        }
        BackgroundItem {
            width: commentsRow.width + 2 * Theme.paddingMedium
            height: bar.height
            onClicked: bar.openComments()
            Row {
                id: commentsRow
                anchors.centerIn: parent
                spacing: Theme.paddingSmall
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-chat"
                    width: Theme.iconSizeSmallPlus
                    height: width
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    text: Reader.num(bar.comments)
                }
            }
        }
    }
}
