import QtQuick 2.0
import Sailfish.Silica 1.0

// Native login. The values go straight into Reddit's own login form in the hidden page;
// the app never stores the password (the WebView keeps Reddit's session cookie).
Dialog {
    id: dialog
    property var browser

    canAccept: userField.text.trim() !== "" && passField.text !== ""
    onAccepted: browser.login(userField.text.trim().replace(/^\/?u\//, ""), passField.text)

    Column {
        width: parent.width
        spacing: Theme.paddingMedium

        DialogHeader { acceptText: "Log in" }

        TextField {
            id: userField
            width: parent.width
            label: "Reddit username"
            placeholderText: label
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            EnterKey.iconSource: "image://theme/icon-m-enter-next"
            EnterKey.onClicked: passField.focus = true
        }

        PasswordField {
            id: passField
            width: parent.width
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: if (dialog.canAccept) dialog.accept()
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            text: "Sent only to reddit.com. Accounts with 2FA or a captcha prompt can't log in yet."
        }
    }
}
