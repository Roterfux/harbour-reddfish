import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    Image {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.paddingLarge * 2
        source: "/usr/share/icons/hicolor/172x172/apps/harbour-reddfish.png"
        width: Theme.iconSizeLarge
        height: width
        opacity: 0.6
    }
    Label {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Theme.paddingLarge * 2
        width: parent.width - 2 * Theme.paddingLarge
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: 4
        truncationMode: TruncationMode.Elide
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.highlightColor
        text: app.pageTitle
    }

    CoverActionList {
        enabled: app.browser !== null
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: app.browser.reload()
        }
    }
}
