import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0
import "../components"
import "../js/store.js" as Store
import "../js/reader.js" as Reader

// Reader mode. Two WebViews load old.reddit.com but are never shown:
//  - web:     feeds (+ login, other pages). Keeps its DOM, so infinite scroll and feed votes work.
//  - postWeb: the open post. Closing a post just hides it; the feed keeps its scroll position.
// Pages are read with runJavaScript and drawn with Silica on top.
WebViewPage {
    id: page

    property string mode: "none"        // feed | post | login | other | none
    property bool otherFromPost: false
    property string otherUrl: ""
    property string otherWhy: ""         // read error, shown under the URL
    property bool otherOver18: false     // the page is reddit's NSFW age check

    property bool loggedIn: false
    property string user: ""
    property var pendingLogin: null      // {user, pass} until the form is submitted, never stored
    property bool loginBusy: false
    property string loginError: ""
    property int loginTries: 0

    property string feedTitle: ""
    property string feedUrl: ""
    property bool feedMore: false        // a next page exists
    property bool feedMoreBusy: false
    property var feedNames: ({})         // fullname -> true, dedupes appended pages
    property int hiddenNsfw: 0           // left out because "Show NSFW posts" is off
    property bool canSubscribe: false
    property bool subscribed: false
    property var subscriptions: JSON.parse(Store.get("subscriptions", "[]"))

    property var post: null
    property bool showComments: false
    property real keepY: -1              // restore comment scroll after "load more"

    readonly property string currentSub: Store.subFromUrl(feedUrl)
    readonly property string currentUser: Store.userFromUrl(feedUrl)
    property int followTick: 0           // bump to re-read the saved users
    readonly property bool userFollowed: {
        followTick
        var u = currentUser.toLowerCase()
        return u !== "" && Store.users().some(function(n) { return n.toLowerCase() === u })
    }
    readonly property bool loading: mode === "post" || (mode === "other" && otherFromPost)
                                    ? postWeb.loading : web.loading

    // ---- navigation ----

    // Posts open with 1 comment (fast); the full thread loads when comments are expanded.
    property string postUrl: ""
    property bool commentsLoaded: false
    onShowCommentsChanged: if (showComments && !commentsLoaded) loadComments()
    function loadComments() {
        commentsLoaded = true
        postWeb.url = postUrl
    }

    function open(url, withComments) {
        url = Store.toOld(url)
        if (/^https:\/\/old\.reddit\.com\/(r\/[^\/]+\/)?comments\//i.test(url)) {
            post = null
            comments.clear()
            postUrl = url
            commentsLoaded = withComments === true
            showComments = commentsLoaded
            mode = "post"
            postWeb.url = commentsLoaded ? url : url + (url.indexOf("?") < 0 ? "?" : "&") + "limit=1"
        } else {
            if (mode === "post" || (mode === "other" && otherFromPost)) {
                mode = feed.count > 0 ? "feed" : "none"
                otherFromPost = false
            }
            web.url = url
        }
    }
    function openSub(name) { open(Store.subUrl(name)) }
    function openUser(name) { open(Store.userUrl(name)) }

    function reload() {
        if (mode === "post" || (mode === "other" && otherFromPost)) postWeb.reload()
        else web.reload()
    }

    function back() {
        if (mode === "post" || (mode === "other" && otherFromPost)) {
            mode = feed.count > 0 ? "feed" : "none"
            otherFromPost = false
        } else if (web.canGoBack) {
            web.goBack()
        }
    }

    function handleLink(url) {
        if (url.indexOf("/") === 0) url = "https://old.reddit.com" + url
        if (/^https?:\/\/([a-z]+\.)?reddit\.com\//i.test(url)) open(url)
        else Qt.openUrlExternally(url)
    }

    // ---- reading pages ----

    function extract(view, appendFeed) {
        view.runJavaScript(Reader.script, function(r) {
            var d = Reader.parse(r)
            console.log("reddfish: read", view === postWeb ? "postWeb" : "web", d.page, "posts", d.posts.length,
                        "post", d.post ? d.post.title.slice(0, 40) + " media=" + (d.post.preview || d.post.hls || d.post.gallery ? 1 : 0) : "-",
                        "comments", d.comments.length, "mode", mode, d.href, "| title:", d.title)
            apply(d, view === postWeb, appendFeed)
        }, function(err) {
            console.log("reddfish: extract failed:", err)
            showOther(view, "Reading the page failed: " + err)
        })
    }

    function showOther(view, why, page18) {
        otherFromPost = view === postWeb
        otherUrl = String(view.url)
        otherWhy = why || ""
        otherOver18 = page18 === "over18"
        mode = "other"
    }

    // The user confirmed the age check in the app: tap reddit's own "continue".
    function confirmOver18() {
        (otherFromPost ? postWeb : web).runJavaScript(Reader.over18Script)
    }

    function apply(d, fromPost, appendFeed) {
        loggedIn = d.loggedIn
        user = d.user
        if (d.loggedIn && d.subs.length) saveSubscriptions(d.subs)
        if (d.loggedIn && d.page === "feed" && !fromPost) startUserCheck()

        if (fromPost) {
            if (mode !== "post" && !(mode === "other" && otherFromPost)) return  // closed meanwhile
            if (d.page === "post") applyPost(d)
            else showOther(postWeb, "", d.page)
            return
        }

        if (d.loggedIn && (loginBusy || d.page === "login")) {
            loginBusy = false
            loginPoll.stop()
            openSub("")
            return
        }
        if (d.page === "login") {
            if (mode !== "post") mode = "login"
            handleLoginPage(d)
        } else if (d.page === "feed") {
            applyFeed(d, appendFeed)
        } else if (mode !== "post") {
            showOther(web, "", d.page)
        }
    }

    function applyFeed(d, append) {
        canSubscribe = d.canSubscribe
        subscribed = d.subscribed
        feedMore = d.next !== ""
        if (!append) {
            feedTitle = /\/r\/[^\/]*\+/.test(String(web.url)) ? "Home"
                      : Store.userFromUrl(web.url) ? "u/" + Store.userFromUrl(web.url) : d.title
            feedUrl = String(web.url)
            feed.clear()
            feedNames = {}
            hiddenNsfw = 0
        }
        var names = feedNames
        for (var i = 0; i < d.posts.length; i++) {
            var p = d.posts[i]
            if (names[p.name]) continue
            if (p.nsfw && !app.showNsfw) { hiddenNsfw++; continue }
            names[p.name] = true
            feed.append(p)
        }
        feedNames = names
        if (!append) {
            if (mode !== "post") mode = "feed"
            feedList.positionViewAtBeginning()
        }
    }

    function applyPost(d) {
        post = d.post
        var y = keepY
        keepY = -1
        comments.clear()
        mode = "post"
        if (!commentsLoaded) return          // only the 1-comment page so far
        for (var j = 0; j < d.comments.length; j++) {
            var c = d.comments[j]
            c.collapsed = false
            c.hidden = false
            comments.append(c)
        }
        mode = "post"
        if (y >= 0) postList.contentY = y
    }

    // ---- infinite scroll ----

    function loadMoreFeed() {
        if (!feedMore || feedMoreBusy || web.loading) return
        feedMoreBusy = true
        web.runJavaScript(Reader.moreScript, function(r) {
            if (r === "started" || r === "busy") morePoll.restart()
            else { feedMoreBusy = false; feedMore = false }
        }, function() { feedMoreBusy = false })
    }

    Timer {
        id: morePoll
        interval: 500
        onTriggered: web.runJavaScript(Reader.moreStatusScript, function(s) {
            if (s === "busy") morePoll.restart()
            else {
                page.feedMoreBusy = false
                if (s === "done") page.extract(web, true)
            }
        })
    }

    // Copies a post's raw markup, for bug reports.
    function copyDebug(view, thingId) {
        view.runJavaScript(Reader.debugScript(thingId), function(r) {
            Clipboard.text = String(r)
            debugNotice.show()
        })
    }

    // ---- media the listing left out ----

    property var expandPending: []

    function expandMedia(index) {
        var id = feed.get(index).id
        feed.setProperty(index, "expandTried", true)
        web.runJavaScript(Reader.expandScript(id), function(ok) {
            if (ok === false || ok === "false") return
            expandPending.push(id)
            expandTimer.restart()
        })
    }

    Timer {
        id: expandTimer
        interval: 1500
        onTriggered: {
            var ids = page.expandPending
            page.expandPending = []
            ids.forEach(function(id) {
                web.runJavaScript(Reader.readThingScript(id), function(r) {
                    if (!r) return
                    var p = Reader.parse(r)
                    for (var i = 0; i < feed.count; i++) {
                        if (feed.get(i).id !== id) continue
                        feed.setProperty(i, "preview", p.preview)
                        feed.setProperty(i, "hls", p.hls)
                        feed.setProperty(i, "gallery", p.gallery)
                        feed.setProperty(i, "ratio", p.ratio)
                        feed.setProperty(i, "redgifs", p.redgifs)
                        break
                    }
                })
            })
        }
    }

    // ---- import with existence check (runs in the feed page, ~1 name per second) ----

    property string importStatus: ""     // "Checking 30/150", shown in the feed header

    function importChecked(items) {
        importStatus = "Checking 0/" + items.length
        web.runJavaScript(Reader.importCheckScript(items), function() { importPoll.restart() })
    }

    Timer {
        id: importPoll
        interval: 1000
        onTriggered: web.runJavaScript(Reader.importStatusScript, function(r) {
            var st = r ? Reader.parse(r) : null
            if (!st) {                       // feed page changed meanwhile: its check is gone
                page.importStatus = ""
                importNotice.text = "Import stopped (page changed). Run it again."
                importNotice.show()
                return
            }
            if (!st.finished) {
                page.importStatus = "Checking " + st.done + "/" + st.total
                importPoll.restart()
                return
            }
            var subs = 0, users = 0
            st.ok.forEach(function(it) {
                if (it.kind === "u") { Store.addUser(it.name); users++ }
                else { Store.addSub(it.name); subs++ }
            })
            page.importStatus = ""
            importNotice.text = subs + " subreddits, " + users + " users imported, "
                             + (st.total - subs - users) + " not found"
            importNotice.show()
            if (subs > 0) page.open(Store.homeUrl())
        })
    }

    // ---- saved users: once a day (logged in only), drop the ones reddit says don't exist ----

    property bool userCheckStarted: false
    function startUserCheck() {
        var today = new Date().toISOString().slice(0, 10)
        if (userCheckStarted || Store.get("userCheck", "") === today) return
        var names = Store.users()
        if (!names.length) return
        userCheckStarted = true
        web.runJavaScript(Reader.goneCheckScript(names), function() { userCheckPoll.restart() })
    }

    Timer {
        id: userCheckPoll
        interval: 3000
        onTriggered: web.runJavaScript(Reader.goneStatusScript, function(r) {
            var st = r ? Reader.parse(r) : null
            if (!st) { page.userCheckStarted = false; return }   // page changed: retry on a later feed
            if (!st.finished) { userCheckPoll.restart(); return }
            st.gone.forEach(function(n) { Store.removeUser(n) })
            Store.set("userCheck", new Date().toISOString().slice(0, 10))
            page.followTick++
            if (st.gone.length) {
                importNotice.text = "Removed " + st.gone.length + " users that no longer exist"
                importNotice.show()
            }
        })
    }

    // ---- login ----

    function showLogin() {
        pageStack.push(Qt.resolvedUrl("LoginDialog.qml"), { browser: page })
    }

    function login(userName, pass) {
        pendingLogin = { user: userName, pass: pass }
        loginError = ""
        loginBusy = true
        loginTries = 0
        mode = "login"
        web.url = "https://old.reddit.com/login"
    }

    function logout() {
        web.runJavaScript(Reader.logoutScript, function() {
            loggedIn = false
            saveSubscriptions([])
        })
    }

    // On the login page: submit the native dialog's input once, then poll until logged in.
    function handleLoginPage(d) {
        if (pendingLogin) {
            var creds = pendingLogin
            pendingLogin = null
            web.runJavaScript(Reader.loginScript(creds.user, creds.pass), function(ok) {
                if (ok === false || ok === "false") {
                    loginBusy = false
                    loginError = "Reddit's login form was not found."
                } else {
                    loginPoll.restart()
                }
            })
        } else if (loginBusy) {
            if (d.loginError) {
                loginBusy = false
                loginError = d.loginError
            } else if (++loginTries < 8) {
                loginPoll.restart()
            } else {
                loginBusy = false
                loginError = "Login did not finish. Reddit may want a captcha or 2FA code."
            }
        }
    }

    Timer {
        id: loginPoll
        interval: 2000
        onTriggered: page.extract(web, false)
    }

    // ---- actions (they click the site's own buttons) ----

    function vote(view, model, index, row, which) {
        if (!loggedIn) {
            showLogin()
            return
        }
        var dir = which === "up" ? 1 : -1
        var newLikes = row.likes === dir ? 0 : dir
        view.runJavaScript(Reader.clickScript(row.id, which), function(ok) {
            if (ok === false || ok === "false") return
            if (model) {
                model.setProperty(index, "score", row.score - row.likes + newLikes)
                model.setProperty(index, "likes", newLikes)
            } else {
                var p = {}
                for (var k in post) p[k] = post[k]
                p.score = post.score - post.likes + newLikes
                p.likes = newLikes
                post = p
            }
        })
    }

    function saveSubscriptions(list) {
        list.sort(function(a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : 1 })
        subscriptions = list
        Store.set("subscriptions", JSON.stringify(list))
    }

    function toggleSubscribe() {
        if (!loggedIn) {
            showLogin()
            return
        }
        var name = currentSub
        web.runJavaScript(Reader.subscribeScript, function(ok) {
            if (ok === false || ok === "false") return
            subscribed = !subscribed
            var list = subscriptions.filter(function(s) { return s.toLowerCase() !== name.toLowerCase() })
            if (subscribed) list.push(name)
            saveSubscriptions(list)
        })
    }

    function toggle(index) {
        var c = comments.get(index)
        var collapse = !c.collapsed
        comments.setProperty(index, "collapsed", collapse)
        for (var j = index + 1; j < comments.count && comments.get(j).depth > c.depth; j++) {
            comments.setProperty(j, "hidden", collapse)
            if (!collapse) comments.setProperty(j, "collapsed", false)
        }
    }

    function loadMoreComments(index) {
        var m = comments.get(index)
        if (m.href) {
            open(m.href, true)               // "continue this thread": comments wanted
            return
        }
        postWeb.runJavaScript(Reader.clickScript(m.id, "more"))
        comments.setProperty(index, "body", "Loading…")
        rereadTimer.restart()
    }

    Timer {
        id: rereadTimer
        interval: 2000
        onTriggered: {
            page.keepY = postList.contentY
            page.extract(postWeb, false)
        }
    }

    // The hidden pages must never play video: reddit's own player there ran GStreamer next to ours
    // and crashed the app. Native video is MediaImage's job. (Types: 64 = int, 128 = bool pref.)
    function blockWebVideo() {
        WebEngineSettings.autoLoadImages = false   // hidden pages: the app loads its own pictures
        WebEngineSettings.setPreference("media.autoplay.default", 5, 64)
        WebEngineSettings.setPreference("media.autoplay.blocking_policy", 2, 64)
        WebEngineSettings.setPreference("media.mediasource.enabled", false, 128)
        WebEngineSettings.setPreference("media.mp4.enabled", false, 128)
        WebEngineSettings.setPreference("media.webm.enabled", false, 128)
    }
    Connections {
        target: app
        onShowNsfwChanged: web.reload()
    }
    Connections {
        target: WebEngineSettings
        onInitialized: page.blockWebVideo()
    }

    Component.onCompleted: {
        app.browser = page
        blockWebVideo()
    }

    ListModel { id: feed }
    ListModel { id: comments }

    // ---- hidden web views ----

    WebView {
        id: web
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: toolbar.top }
        visible: false                   // never shown: drawing it under the native list cost every frame
        url: Store.homeUrl()             // the main feed
        onTitleChanged: if (page.mode !== "post") app.pageTitle = title || "Reddfish"
        // read as soon as the HTML is parsed (early), not after every ad/script has loaded
        property bool readEarly: false
        onLoadingChanged: {
            if (loading) { readEarly = false; page.markOld(web) }
            else if (!readEarly) page.extract(web, false)
        }
    }

    WebView {
        id: postWeb
        anchors.fill: web
        visible: false
        onTitleChanged: if (page.mode === "post") app.pageTitle = title || "Reddfish"
        property bool readEarly: false
        onLoadingChanged: {
            if (loading) { readEarly = false; page.markOld(postWeb) }
            else if (!readEarly && String(url) !== "") page.extract(postWeb, false)
        }
    }

    // Device self-test (env REDDFISH_SELFTEST): open each url 15 s apart; "comments" = Show comments.
    Timer {
        property var urls: (typeof selfTestUrls === "string" ? selfTestUrls : "").split(" ").filter(function(u) { return u })
        property int i: 0
        interval: 15000
        repeat: true
        running: urls.length > 0
        onTriggered: {
            if (i >= urls.length) { stop(); console.warn("reddfish: selftest end, mode", page.mode,
                                                         "feed", feed.count, "comments", comments.count); return }
            console.warn("reddfish: selftest", urls[i], "| now mode", page.mode, "feed", feed.count,
                        "comments", comments.count)
            if (urls[i] === "comments") page.showComments = true
            else page.open(urls[i])
            i++
        }
    }

    // A load starts while the previous page is still in the view ("complete"): tag it, so the
    // early read below never takes it for the new page. New pages come without the tag.
    function markOld(v) { v.runJavaScript('window.__rfOld = true') }

    // While a page loads: once its HTML is parsed, read it right away.
    Timer {
        interval: 500
        repeat: true
        running: (web.loading && !web.readEarly) || (postWeb.loading && !postWeb.readEarly)
        onTriggered: [web, postWeb].forEach(function(v) {
            if (!v.loading || v.readEarly) return
            v.runJavaScript('return window.__rfOld ? "old" : document.readyState', function(s) {
                if (s === "loading" || s === "old" || !v.loading || v.readEarly) return
                v.readEarly = true
                page.extract(v, false)
            })
        })
    }

    // ---- native views, always opaque on top ----

    Rectangle {
        id: overlay
        anchors.fill: web
        color: Theme.colorScheme === Theme.DarkOnLight ? "white" : "black"

        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.highlightBackgroundColor, 0.08)
        }

        // Login progress, and pages Reddfish has no native view for.
        Column {
            visible: page.mode === "login" || page.mode === "other"
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.horizontalPageMargin
            spacing: Theme.paddingLarge

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Large
                running: page.loginBusy
                visible: running
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: page.mode === "other" && page.otherOver18 ? "NSFW subreddit"
                    : page.mode === "other" ? "No native view for this page"
                    : page.loginBusy ? "Logging in…"
                    : page.loginError !== "" ? "Login failed" : "Log in to Reddit"
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 6                  // long combined-feed addresses
                truncationMode: TruncationMode.Elide
                color: Theme.secondaryHighlightColor
                text: page.mode === "other" && page.otherOver18
                      ? (app.showNsfw ? "Are you 18 or older?" : "Turn on \"Show NSFW posts\" in the menu to open it.")
                      : page.mode === "other" ? (page.otherUrl.length > 200 ? "the combined Home feed" : page.otherUrl)
                                                + (page.otherWhy ? "\n\n" + page.otherWhy : "")
                      : page.loginError
            }
            Button {
                visible: page.mode === "other" && page.otherOver18 && app.showNsfw
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Yes, continue"
                onClicked: page.confirmOver18()
            }
            Button {
                visible: page.mode === "other" && page.otherOver18
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Back"
                onClicked: page.back()
            }
            Button {
                visible: page.mode === "login" && !page.loginBusy
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Log in"
                onClicked: page.showLogin()
            }
            Button {
                visible: page.mode === "other" && !page.otherOver18
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Open in browser"
                onClicked: Qt.openUrlExternally(page.otherUrl)
            }
            Button {
                visible: page.mode === "other" && !page.otherOver18
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Copy debug info"
                onClicked: (page.otherFromPost ? postWeb : web).runJavaScript(Reader.pageDebugScript, function(r) {
                    Clipboard.text = String(r)
                    debugNotice.show()
                }, function(err) {
                    Clipboard.text = page.otherUrl + "\n" + page.otherWhy + "\ndebug script error: " + err
                    debugNotice.show()
                })
            }
        }

        SilicaListView {
            id: feedList
            anchors.fill: parent
            visible: page.mode === "feed"
            clip: true
            model: feed
            cacheBuffer: height * 2          // cards (and their pictures) load 2 screens ahead

            PullDownMenu {
                busy: web.loading
                MenuItem {
                    text: "Copy debug info"
                    onClicked: web.runJavaScript(Reader.pageDebugScript, function(r) {
                        Clipboard.text = String(r)
                        debugNotice.show()
                    })
                }
                MenuItem { text: "Refresh"; onClicked: web.reload() }
            }

            header: Column {
                width: feedList.width
                PageHeader {
                    title: page.feedTitle
                    description: page.importStatus !== "" ? page.importStatus
                               : page.loggedIn ? "u/" + page.user : "Not logged in"
                }
                Button {
                    visible: page.canSubscribe && page.currentSub !== ""
                             && page.currentSub !== "all" && page.currentSub !== "popular"
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: page.subscribed ? "Leave" : "Join"
                    highlighted: !page.subscribed
                    onClicked: page.toggleSubscribe()
                }
                // Follow a user: saved locally (menu → Saved users).
                Button {
                    visible: page.currentUser !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: page.userFollowed ? "Unfollow" : "Follow"
                    highlighted: !page.userFollowed
                    onClicked: {
                        if (page.userFollowed) Store.removeUser(page.currentUser)
                        else Store.addUser(page.currentUser)
                        page.followTick++
                    }
                }
                Item { width: 1; height: Theme.paddingMedium }
            }

            delegate: PostItem {
                showSubreddit: page.currentSub === "" || page.currentSub === "all"
                               || page.currentSub === "popular"
                autoplay: feedList.visible && Qt.application.active
                onOpenPost: page.open(model.permalink)
                onVote: page.vote(web, feed, index, feed.get(index), which)
                onOpenSub: page.openSub(name)
                onOpenUser: page.openUser(name)
                onNeedMedia: page.expandMedia(index)
                onCopyDebug: page.copyDebug(web, model.id)
            }

            // Infinite scroll: fetch the next page when close to the end.
            onContentYChanged: if (contentHeight - contentY - height < height * 4) page.loadMoreFeed()

            footer: Item {
                width: feedList.width
                height: page.feedMore ? Theme.itemSizeLarge : Theme.paddingLarge
                BusyIndicator {
                    anchors.centerIn: parent
                    running: page.feedMoreBusy
                }
            }

            ViewPlaceholder {
                enabled: feed.count === 0 && !web.loading
                text: "No posts"
                hintText: page.hiddenNsfw > 0 ? page.hiddenNsfw + " NSFW posts hidden. Turn on \"Show NSFW posts\" in the menu."
                                              : "Pull down → Copy debug info, and send it."
            }
            VerticalScrollDecorator {}
        }

        SilicaListView {
            id: postList
            anchors.fill: parent
            visible: page.mode === "post"
            clip: true
            model: page.showComments ? comments : null

            PullDownMenu {
                busy: postWeb.loading
                MenuItem {
                    text: "Open in browser"
                    onClicked: Qt.openUrlExternally(page.post.permalink)
                }
                MenuItem {
                    visible: page.post !== null
                    text: "Share"
                    onClicked: app.share(page.post.title, page.post.permalink)
                }
                MenuItem {
                    visible: page.post !== null
                    text: "Copy debug info"
                    onClicked: page.copyDebug(postWeb, page.post.id)
                }
                MenuItem {
                    visible: app.mediaKind(page.post) !== ""
                    text: app.mediaKind(page.post) === "video" ? "Save video" : "Save image"
                    onClicked: app.saveMedia(page.post, postMedia.galleryIndex)
                }
                MenuItem {
                    visible: page.post !== null
                    text: page.post ? "Go to r/" + page.post.subreddit : ""
                    onClicked: page.openSub(page.post.subreddit)
                }
                MenuItem { text: "Refresh"; onClicked: postWeb.reload() }
            }

            header: Column {
                width: postList.width
                spacing: Theme.paddingMedium
                visible: page.post !== null

                PageHeader {
                    title: page.post ? "r/" + page.post.subreddit : ""
                    description: page.post ? "u/" + page.post.author + " · " + Reader.ago(page.post.time) : ""
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    text: page.post ? page.post.title : ""
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.highlightColor
                }

                MediaImage {
                    id: postMedia
                    post: page.post
                    maxHeightRatio: 3
                    autoplay: postList.visible && Qt.application.active
                }

                Label {
                    visible: text !== ""
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    text: page.post ? page.post.selftext : ""
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primaryColor
                    linkColor: Theme.highlightColor
                    onLinkActivated: page.handleLink(link)
                }

                Button {
                    visible: page.post !== null && !page.post.isSelf && !Reader.isImage(page.post)
                             && !(page.post.isVideo && page.post.hls)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !page.post ? "" : page.post.isVideo ? "Play video in browser"
                        : page.post.isGallery ? "Open gallery in browser" : "Open " + page.post.domain
                    onClicked: page.post.isVideo || page.post.isGallery
                               ? Qt.openUrlExternally(page.post.url) : page.handleLink(page.post.url)
                }

                VoteBar {
                    likes: page.post ? page.post.likes : 0
                    score: page.post ? page.post.score : 0
                    comments: page.post ? page.post.comments : 0
                    onVote: page.vote(postWeb, null, -1, page.post, which)
                    onOpenComments: page.showComments = !page.showComments
                }

                // Comments are hidden until asked for.
                BackgroundItem {
                    width: parent.width
                    onClicked: page.showComments = !page.showComments
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.highlightColor
                        text: (page.showComments ? "Hide comments" : "Show comments")
                              + (page.post ? " (" + Reader.num(page.post.comments) + ")" : "")
                    }
                    Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: page.showComments ? "image://theme/icon-m-up" : "image://theme/icon-m-down"
                    }
                }
            }

            delegate: CommentItem {
                onClicked: model.isMore ? page.loadMoreComments(index) : page.toggle(index)
                onVote: page.vote(postWeb, comments, index, comments.get(index), which)
                onLink: page.handleLink(url)
            }

            VerticalScrollDecorator {}
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && !(page.mode === "post" && page.post !== null)
                     && !(page.mode === "feed" && feed.count > 0)
        }
    }

    Notice {
        id: debugNotice
        text: "Debug info copied – paste it to the developer"
    }
    Notice { id: importNotice }

    // Thin load progress line above the toolbar.
    Rectangle {
        anchors.bottom: toolbar.top
        height: Theme.paddingSmall / 2
        width: page.width * (page.mode === "post" ? postWeb.loadProgress : web.loadProgress) / 100
        color: Theme.highlightColor
        visible: page.loading
    }

    Rectangle {
        id: toolbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Theme.itemSizeSmall
        color: Theme.rgba(Theme.highlightDimmerColor, 0.9)

        Row {
            anchors.centerIn: parent
            spacing: (toolbar.width - 4 * Theme.iconSizeMedium) / 5

            IconButton {
                icon.source: "image://theme/icon-m-back"
                enabled: page.mode === "post" || page.mode === "other" || web.canGoBack
                onClicked: page.back()
            }
            IconButton {
                icon.source: "image://theme/icon-m-home"
                onClicked: page.open(Store.homeUrl())
            }
            IconButton {
                icon.source: page.loading ? "image://theme/icon-m-reset" : "image://theme/icon-m-refresh"
                onClicked: page.loading ? (page.mode === "post" ? postWeb.stop() : web.stop()) : page.reload()
            }
            IconButton {
                icon.source: "image://theme/icon-m-menu"
                onClicked: pageStack.push(Qt.resolvedUrl("SubredditsPage.qml"),
                                          { browser: page, currentSub: page.currentSub,
                                            currentUser: page.currentUser,
                                            currentUrl: page.mode === "post" ? String(postWeb.url) : String(web.url) })
            }
        }
    }
}
