import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

Page {
    id: page

    property var browser
    property string currentSub: ""
    property string currentUser: ""
    property string currentUrl: ""

    function go(name) {
        if (name === "") browser.open(Store.homeUrl())   // "Home" row
        else browser.openSub(name)
        pageStack.pop()
    }
    function goUser(name) {
        browser.openUser(name)
        pageStack.pop()
    }

    // One list: saved users, then saved subreddits (ListView sections by `kind`).
    function refresh() {
        saved.clear()
        Store.users().forEach(function(n) { saved.append({ name: n, kind: "Saved users" }) })
        Store.subs().forEach(function(n) { saved.append({ name: n, kind: "Saved subreddits" }) })
    }

    function isSaved(name, kind) {
        for (var i = 0; i < saved.count; i++)
            if (saved.get(i).kind === kind && saved.get(i).name.toLowerCase() === name.toLowerCase()) return true
        return false
    }

    // Infinity for Reddit backup: anonymous_subscribed_subreddits.json and
    // anonymous_subscribed_users.json ([{"name": ...}]), unpacked from the backup zip into Downloads.
    function readInfinity(file, clean, kind, items, done) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + downloadsDir + "/" + file)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var n = -1
            try {
                n = 0
                JSON.parse(xhr.responseText).forEach(function(s) {
                    var name = clean(s.name || "")
                    if (name && !isSaved(name, kind === "u" ? "Saved users" : "Saved subreddits")) {
                        items.push({ kind: kind, name: name }); n++
                    }
                })
            } catch (e) { n = -1 }
            done(n)
        }
        xhr.send()
    }

    // Reads both files, then the feed page checks every new name exists before saving it.
    function importInfinity() {
        var items = []
        readInfinity("anonymous_subscribed_subreddits.json", Store.cleanName, "r", items, function(subsN) {
            readInfinity("anonymous_subscribed_users.json", Store.cleanUser, "u", items, function(usersN) {
                if (subsN < 0 && usersN < 0) {
                    importNotice.text = "Put the Infinity .json files into Downloads first"
                    importNotice.show()
                } else if (items.length === 0) {
                    importNotice.text = "Nothing new to import"
                    importNotice.show()
                } else {
                    browser.importChecked(items)
                    pageStack.pop()
                }
            })
        })
    }

    Notice { id: importNotice }

    Component.onCompleted: refresh()

    ListModel { id: saved }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: saved

        section.property: "kind"
        section.delegate: SectionHeader { text: section }

        PullDownMenu {
            MenuItem {
                visible: page.browser.loggedIn
                text: "Log out"
                onClicked: { page.browser.logout(); pageStack.pop() }
            }
            MenuItem {
                text: "Import from Infinity"
                onClicked: page.importInfinity()
            }
            MenuItem {
                text: "Open page in browser"
                onClicked: Qt.openUrlExternally(page.currentUrl)
            }
            MenuItem {
                visible: page.currentUser !== "" && !page.isSaved(page.currentUser, "Saved users")
                text: "Save u/" + page.currentUser
                onClicked: { Store.addUser(page.currentUser); page.refresh() }
            }
            MenuItem {
                visible: page.currentSub !== "" && !page.isSaved(page.currentSub, "Saved subreddits")
                text: "Save r/" + page.currentSub
                onClicked: { Store.addSub(page.currentSub); page.refresh() }
            }
        }

        header: Column {
            width: list.width

            PageHeader { title: "Reddfish" }

            SearchField {
                width: parent.width
                placeholderText: "Go to subreddit or u/user"
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    if (/^\s*\/?(u|user)\//i.test(text)) {
                        var u = Store.cleanUser(text)
                        if (u) page.goUser(u)
                    } else {
                        var n = Store.cleanName(text)
                        if (n) page.go(n)
                    }
                }
            }

            SectionHeader { text: "Feeds" }

            Repeater {
                model: [ { label: "Home", sub: "", icon: "image://theme/icon-m-home" },
                         { label: "r/popular", sub: "popular", icon: "image://theme/icon-m-favorite" },
                         { label: "r/all", sub: "all", icon: "image://theme/icon-m-levels" } ]
                ListItem {
                    id: feedRow
                    Icon {
                        id: feedIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: modelData.icon
                        highlighted: feedRow.highlighted
                    }
                    Label {
                        anchors { left: feedIcon.right; leftMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                        text: modelData.label
                        color: feedRow.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    onClicked: page.go(modelData.sub)
                }
            }

            SectionHeader { text: "Account" }

            ListItem {
                id: accountRow
                enabled: !page.browser.loggedIn
                Icon {
                    id: accountIcon
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-person"
                    highlighted: accountRow.highlighted
                }
                Label {
                    anchors { left: accountIcon.right; leftMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                    text: page.browser.loggedIn ? "u/" + page.browser.user : "Log in"
                    color: page.browser.loggedIn ? Theme.primaryColor : Theme.highlightColor
                }
                onClicked: pageStack.replace(Qt.resolvedUrl("LoginDialog.qml"), { browser: page.browser })
            }

            SectionHeader { text: "Settings" }

            TextSwitch {
                text: "Autoplay videos"
                description: "Off: tap a video to play it."
                checked: app.autoplayVideos
                onCheckedChanged: app.autoplayVideos = checked
            }

            TextSwitch {
                text: "Show NSFW posts"
                description: "Off: posts marked NSFW are left out of every feed."
                checked: app.showNsfw
                onCheckedChanged: app.showNsfw = checked
            }

            TextSwitch {
                visible: app.showNsfw
                text: "Blur NSFW"
                description: "Pictures and videos marked NSFW stay blurred until tapped."
                checked: app.blurNsfw
                onCheckedChanged: app.blurNsfw = checked
            }

            SectionHeader {
                visible: page.browser.subscriptions.length > 0
                text: "Subscribed"
            }

            Repeater {
                model: page.browser.subscriptions
                ListItem {
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: "r/" + modelData
                    }
                    onClicked: page.go(modelData)
                }
            }

            Label {
                visible: saved.count === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: "Nothing saved yet. Open a subreddit or user, come back here and pull down → Save."
            }
        }

        delegate: ListItem {
            id: row
            readonly property bool isUser: model.kind === "Saved users"
            menu: ContextMenu {
                MenuItem {
                    text: "Remove"
                    onClicked: row.remorseDelete(function() {
                        if (row.isUser) Store.removeUser(model.name)
                        else Store.removeSub(model.name)
                        page.refresh()
                    })
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: (row.isUser ? "u/" : "r/") + model.name
            }
            onClicked: row.isUser ? page.goUser(model.name) : page.go(model.name)
        }

        VerticalScrollDecorator {}
    }
}
