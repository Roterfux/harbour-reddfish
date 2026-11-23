.pragma library
.import QtQuick.LocalStorage 2.0 as Sql

// Saved subreddits and settings, kept in the app's own LocalStorage db.

var _db = null

function db() {
    if (!_db) {
        _db = Sql.LocalStorage.openDatabaseSync("reddfish", "1.0", "Reddfish", 100000)
        _db.transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS subs (name TEXT PRIMARY KEY)")
            tx.executeSql("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")
            tx.executeSql("CREATE TABLE IF NOT EXISTS users (name TEXT PRIMARY KEY)")
        })
    }
    return _db
}

function subs() {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT name FROM subs ORDER BY name COLLATE NOCASE")
        for (var i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).name)
    })
    return out
}

function addSub(name) {
    db().transaction(function(tx) { tx.executeSql("INSERT OR IGNORE INTO subs VALUES (?)", [name]) })
}

function removeSub(name) {
    db().transaction(function(tx) { tx.executeSql("DELETE FROM subs WHERE name = ?", [name]) })
}

// Saved (followed) users, same pattern as subs.
function users() {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT name FROM users ORDER BY name COLLATE NOCASE")
        for (var i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).name)
    })
    return out
}

function addUser(name) {
    db().transaction(function(tx) { tx.executeSql("INSERT OR IGNORE INTO users VALUES (?)", [name]) })
}

function removeUser(name) {
    db().transaction(function(tx) { tx.executeSql("DELETE FROM users WHERE name = ?", [name]) })
}

// "u/Foo", "/u/foo/", "user/foo" -> "Foo"; "" if not a valid user name.
function cleanUser(s) {
    var n = String(s).trim().replace(/^\/?(u|user)\//i, "").replace(/\/+$/, "")
    return /^[A-Za-z0-9_-]{3,20}$/.test(n) ? n : ""
}

function userUrl(name) {
    return "https://old.reddit.com/user/" + name + "/submitted/"
}

// User name from a reddit URL, or "".
function userFromUrl(url) {
    var m = /^https?:\/\/[^\/]*reddit\.com\/(?:u|user)\/([A-Za-z0-9_-]+)/i.exec(String(url))
    return m ? m[1] : ""
}

function get(key, fallback) {
    var v = fallback
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT value FROM settings WHERE key = ?", [key])
        if (r.rows.length) v = r.rows.item(0).value
    })
    return v
}

function set(key, value) {
    db().transaction(function(tx) {
        tx.executeSql("INSERT OR REPLACE INTO settings VALUES (?, ?)", [key, String(value)])
    })
}

// "r/Foo", "/r/foo/", "foo" -> "foo"; "" if not a valid name.
function cleanName(s) {
    var n = String(s).trim().replace(/^\/?r\//i, "").replace(/\/+$/, "")
    return /^[A-Za-z0-9_]{2,21}$/.test(n) ? n : ""
}

// Subreddit name from a reddit URL, or "" (also for combined feeds like /r/a+b/).
function subFromUrl(url) {
    var m = /^https?:\/\/[^\/]*reddit\.com\/r\/([A-Za-z0-9_]+)(?:[\/?#]|$)/i.exec(String(url))
    return m ? m[1] : ""
}

// Home (start feed): all saved subreddits as one feed, else r/popular. Saved users are not in it.
function homeUrl() {
    var s = subs()
    return subUrl(s.length ? s.join("+") : "popular")
}

// Native views read old.reddit.com pages, so all reddit links go there.
function subUrl(name) {
    return "https://old.reddit.com" + (name ? "/r/" + name + "/" : "/")
}

function toOld(url) {
    return String(url).replace(/^https?:\/\/(www\.|new\.|np\.|m\.)?reddit\.com/i, "https://old.reddit.com")
}
