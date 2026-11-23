.pragma library

// Reader mode: reads the old.reddit.com page the WebView has loaded and returns it as JSON.
// Runs via WebView.runJavaScript, which wraps the script in `new Function(...)`, so it must `return`.
// No extra requests: it only reads the DOM of the page the user opened.

var helpers = [
// backup for the Gecko prefs: no video may run in the hidden page
'var vids = document.querySelectorAll("video");',
'for (var vi = 0; vi < vids.length; vi++) { vids[vi].pause(); vids[vi].removeAttribute("src"); vids[vi].load(); }',
'var q = function(e, s) { return e ? e.querySelector(s) : null; };',
'var t = function(e) { return e ? e.textContent.trim() : ""; };',
'var abs = function(u) {',
'  if (!u) return "";',
'  if (u.indexOf("//") === 0) return "https:" + u;',
'  if (u.indexOf("/") === 0) return location.origin + u;',
'  return u;',
'};',
'var likesOf = function(mid) {',
'  if (!mid) return 0;',
'  return mid.classList.contains("likes") ? 1 : (mid.classList.contains("dislikes") ? -1 : 0);',
'};',
'var num = function(s) { var n = parseInt(s || "0", 10); return isNaN(n) ? 0 : n; };',
'var exHtml = function(el) {',
'  var ex = q(el, ".expando");',
'  return ex ? (ex.getAttribute("data-cachedhtml") || ex.innerHTML) : "";',
'};',
'var prev = function(el) {',
'  var m = /(?:src|poster)="(https:\\/\\/(?:preview|external-preview|i)\\.redd\\.it\\/[^"]+)"/.exec(exHtml(el));',
'  return m ? m[1].replace(/&amp;/g, "&") : "";',
'};',
// all pictures of a gallery as full i.redd.it urls, "|"-joined (ListModel can't hold arrays well)
'var gallery = function(el) {',
'  var re = /preview\\.redd\\.it\\/([A-Za-z0-9_-]+\\.(?:jpe?g|png|gif|webp))/gi, m, seen = {}, out = [];',
'  var h = exHtml(el);',
'  while ((m = re.exec(h))) if (!seen[m[1]]) { seen[m[1]] = 1; out.push("https://i.redd.it/" + m[1]); }',
'  return out.join("|");',
'};',
// box shape (height/width) known before loading, so cards never change height; 0 = unknown
'var ratio = function(el) {',
'  var h = exHtml(el);',
'  var m = /class="preview"[^>]*?width="(\\d+)"[^>]*?height="(\\d+)"/.exec(h);',
'  if (m && +m[1] > 0) return +m[2] / +m[1];',
'  m = /data-orientation="(portrait|landscape)"/.exec(h);',
'  if (m) return m[1] === "portrait" ? 16 / 9 : 9 / 16;',
'  return 0;',
'};',
// redgifs id from the link or the embed in the expando ("" if none)
'var redgifs = function(el) {',
'  var s = (el.getAttribute("data-url") || "") + " " + exHtml(el);',
'  var m = /redgifs\\.com\\/(?:watch|ifr|i)\\/([A-Za-z]+)/i.exec(s);',
'  return m ? m[1].toLowerCase() : "";',
'};',
'var hls = function(el) {',
'  var m = /data-hls-url="(https:\\/\\/v\\.redd\\.it\\/[^"]+)"/.exec(exHtml(el));',
'  return m ? m[1].replace(/&amp;/g, "&") : "";',
'};',
'var post = function(el) {',
'  var th = q(el, "a.thumbnail img");',
'  var sel = q(el, ".expando .usertext-body .md");',
'  return {',
'    id: el.id, name: el.getAttribute("data-fullname") || "",',
'    title: t(q(el, "a.title")), url: abs(el.getAttribute("data-url")),',
'    permalink: abs(el.getAttribute("data-permalink")),',
'    subreddit: el.getAttribute("data-subreddit") || "", author: el.getAttribute("data-author") || "",',
'    score: num(el.getAttribute("data-score")), comments: num(el.getAttribute("data-comments-count")),',
'    time: num(el.getAttribute("data-timestamp")), domain: el.getAttribute("data-domain") || "",',
'    nsfw: el.getAttribute("data-nsfw") === "true", stickied: el.classList.contains("stickied"),',
'    isSelf: el.classList.contains("self"), thumb: th ? abs(th.getAttribute("src")) : "",',
'    selftext: sel ? sel.innerHTML : "", likes: likesOf(q(el, ".midcol")),',
'    flair: t(q(el, ".linkflairlabel")), preview: prev(el), hls: hls(el), ratio: ratio(el),',
'    redgifs: redgifs(el),',
'    isVideo: el.getAttribute("data-domain") === "v.redd.it" || hls(el) !== "",',
'    isGallery: (el.getAttribute("data-url") || "").indexOf("/gallery/") >= 0,',
'    gallery: (el.getAttribute("data-url") || "").indexOf("/gallery/") >= 0 ? gallery(el) : "",',
'    hasExpando: !!q(el, ".expando-button") && !el.classList.contains("self"), expandTried: false',
'  };',
'};'
].join("\n")

var script = helpers + "\n" + [
'var walk = function(table, depth, out) {',
'  if (!table) return;',
'  for (var i = 0; i < table.children.length; i++) {',
// shortcut: big threads are cut at 300 rows (one huge result failed to reach QML); page later if needed
'    if (out.length >= 300) return;',
'    var c = table.children[i];',
'    if (!c.classList || !c.classList.contains("thing")) continue;',
'    if (c.classList.contains("comment")) {',
'      var entry = q(c, ":scope > .entry");',
'      var sc = q(entry, ".tagline .score.unvoted");',
'      var body = q(entry, ".usertext-body .md");',
'      var tm = q(entry, ".tagline time");',
'      out.push({ isMore: false, id: c.id, author: c.getAttribute("data-author") || "[deleted]",',
'        score: sc ? num(sc.getAttribute("title")) : 0, scoreHidden: !sc,',
'        time: tm ? Date.parse(tm.getAttribute("datetime")) || 0 : 0,',
'        body: body ? body.innerHTML.slice(0, 5000) : "", depth: depth, likes: likesOf(q(c, ":scope > .midcol")),',
'        submitter: !!q(entry, ".tagline .submitter"), href: "" });',
'      walk(q(c, ":scope > .child > .sitetable"), depth + 1, out);',
'    } else if (c.classList.contains("morechildren") || c.classList.contains("morerecursion")) {',
'      var a = q(c, "a");',
'      out.push({ isMore: true, id: c.id, author: "", score: 0, scoreHidden: true, time: 0,',
'        body: t(a), depth: depth, likes: 0, submitter: false,',
'        href: c.classList.contains("morerecursion") && a ? a.href : "" });',
'    }',
'  }',
'};',
'var res = { page: "other", loggedIn: document.body.classList.contains("loggedin"),',
'  user: t(q(document, "#header-bottom-right .user a")), title: document.title,',
'  next: "", prev: "", posts: [], post: null, comments: [], href: location.href };',
'var area = q(document, ".commentarea");',
'var links = document.querySelectorAll("#siteTable > .thing.link:not(.promoted)");',
// post pages wrap video posts in #pinnable-placeholder > #pinnable-content, so search deeper
'var op = q(document, "#siteTable .thing.link");',
'if (area && op) {',
'  res.page = "post"; res.post = post(op);',
'  walk(q(area, ":scope > .sitetable"), 0, res.comments);',
'} else if (q(document, "#siteTable")) {',
'  res.page = "feed";',
'  for (var i = 0; i < links.length; i++) res.posts.push(post(links[i]));',
'  var nx = q(document, ".nav-buttons .next-button a"); res.next = nx ? nx.href : "";',
'  var pv = q(document, ".nav-buttons .prev-button a"); res.prev = pv ? pv.href : "";',
'  var h = q(document, ".pagename a"); res.title = h ? "r/" + t(h) : "Front page";',
'}',
'if (location.pathname.indexOf("/over18") === 0) res.page = "over18";',
'var lf = q(document, "#login-form") || q(document, "form.login-form");',
'if (lf && !res.loggedIn && res.page === "other") {',
'  res.page = "login";',
'  var errs = lf.querySelectorAll(".c-form-control-feedback-error, .error, .c-alert");',
'  res.loginError = "";',
'  for (var e = 0; e < errs.length; e++)',
'    if (errs[e].offsetParent !== null && t(errs[e])) res.loginError += t(errs[e]) + " ";',
'}',
'var sb = q(document, ".side .subscribe-button");',
'res.canSubscribe = !!sb;',
'res.subscribed = !!q(sb, ".option.remove.active");',
'res.subs = [];',
'if (res.loggedIn) {',
'  var ch = document.querySelectorAll("#sr-header-area .drop-choices a.choice");',
'  for (var k = 0; k < ch.length; k++) {',
'    var m = /\\/r\\/([A-Za-z0-9_]+)\\/?$/.exec(ch[k].getAttribute("href") || "");',
'    if (m) res.subs.push(m[1]);',
'  }',
'}',
'return JSON.stringify(res);'
].join("\n")

// Clicks the vote arrow or "load more" link of a thing in the page (the user's own action).
function clickScript(thingId, what) {
    if (!/^[A-Za-z0-9_]+$/.test(thingId)) return "return false;"
    var sel = what === "up" ? "[data-event-action='upvote']"
            : what === "down" ? "[data-event-action='downvote']"
            : "a"
    var scope = what === "more" ? "" : ":scope > .midcol "
    return 'var el = document.getElementById("' + thingId + '");'
         + 'var a = el ? el.querySelector("' + scope + sel + '") : null;'
         + 'if (a) a.click(); return !!a;'
}

// Infinite scroll, like the site's own "next" link (and RES's never-ending reddit): fetches the
// next listing page once per scroll-to-end and appends its posts to this page's DOM, so votes on
// older posts still find their buttons. Async: poll moreStatusScript until "done" or "error".
var moreScript = [
'var st = document.querySelector("#siteTable");',
'var nx = document.querySelector("#siteTable .nav-buttons .next-button a");',
'if (!st || !nx) return "end";',
'if (window.__rfMore === "busy") return "busy";',
'window.__rfMore = "busy";',
'fetch(nx.href, { credentials: "include" }).then(function(r) {',
'  if (!r.ok) throw new Error("HTTP " + r.status);',
'  return r.text();',
'}).then(function(h) {',
'  var d = new DOMParser().parseFromString(h, "text/html");',
'  var nav = st.querySelector(".nav-buttons");',
'  var items = d.querySelectorAll("#siteTable > .thing.link");',
'  for (var i = 0; i < items.length; i++) st.insertBefore(document.importNode(items[i], true), nav);',
'  var nn = d.querySelector("#siteTable .nav-buttons");',
'  if (nav) { if (nn) nav.replaceWith(document.importNode(nn, true)); else nav.remove(); }',
'  window.__rfMore = "done";',
'}).catch(function() { window.__rfMore = "error"; });',
'return "started";'
].join("\n")

var moreStatusScript = 'return window.__rfMore || "";'

// Some posts (often on the front page) come without their media in the listing; the site loads it
// when its expand button is tapped. expandScript taps it for one post, readThingScript reads the
// post again a moment later and folds it back (so no player keeps running in the hidden page).
function expandScript(thingId) {
    if (!/^[A-Za-z0-9_]+$/.test(thingId)) return "return false;"
    return 'var el = document.getElementById("' + thingId + '");'
         + 'var b = el ? el.querySelector(".expando-button.collapsed") : null;'
         + 'if (b) b.click(); return !!b;'
}

function readThingScript(thingId) {
    if (!/^[A-Za-z0-9_]+$/.test(thingId)) return "return \"\";"
    return helpers + "\n"
         + 'var el = document.getElementById("' + thingId + '");'
         + 'if (!el) return "";'
         + 'var p = post(el);'
         + 'var b = el.querySelector(".expando-button.expanded"); if (b) b.click();'
         + 'return JSON.stringify(p);'
}

// Debug: the raw markup of one post (to fix the reader against real pages). Expando content
// is in the outerHTML too (data-cachedhtml attribute). Capped so the clipboard stays usable.
function debugScript(thingId) {
    if (!/^[A-Za-z0-9_]+$/.test(thingId)) return "return \"\";"
    return 'var el = document.getElementById("' + thingId + '");'
         + 'return el ? location.href + "\\n" + el.outerHTML.slice(0, 30000) : "not found";'
}

// Import check: loads each subreddit/user page (like opening it), one after another, and keeps
// those that exist. items: [{kind: "r"|"u", name}] (names already cleaned). Async: poll
// importStatusScript until finished.
function importCheckScript(items) {
    return 'var items = ' + JSON.stringify(items) + ';'
         + 'var st = window.__rfImport = { done: 0, total: items.length, ok: [], finished: false };'
         + 'var i = 0;'
         + 'var next = function() {'
         + '  if (i >= items.length) { st.finished = true; return; }'
         + '  var it = items[i++];'
         + '  var url = it.kind === "u" ? "/user/" + it.name + "/submitted/" : "/r/" + it.name + "/";'
         + '  fetch(url, { credentials: "include" }).then(function(r) {'
         + '    if (r.status === 429) { i--; return 5000; }'      // rate limited: same one again later
         + '    var path = new URL(r.url).pathname.toLowerCase();'
         // NSFW / quarantined subs land on reddit's gate page: they exist
         + '    if (r.ok && (path.indexOf(url.toLowerCase()) === 0 || /^\\/(over18|quarantine)/.test(path)))'
         + '      st.ok.push(it);'
         + '    st.done++; return 900;'
         + '  }).catch(function() { st.done++; return 900; })'
         + '  .then(function(wait) { setTimeout(next, wait); });'
         + '};'
         + 'next(); return "started";'
}
var importStatusScript = 'return JSON.stringify(window.__rfImport || null);'

// Saved-user check: HEAD /user/<name>/ one by one; only a 404 counts as gone (errors, 429 and
// login redirects keep the user). Async: poll goneStatusScript until finished.
function goneCheckScript(names) {
    return 'var names = ' + JSON.stringify(names) + ';'
         + 'var st = window.__rfGone = { done: 0, total: names.length, gone: [], finished: false };'
         + 'var i = 0;'
         + 'var next = function() {'
         + '  if (i >= names.length) { st.finished = true; return; }'
         + '  var n = names[i++];'
         + '  fetch("/user/" + n + "/", { method: "HEAD", credentials: "include" }).then(function(r) {'
         + '    if (r.status === 429) { i--; return 5000; }'
         + '    if (r.status === 404) st.gone.push(n);'
         + '    st.done++; return 900;'
         + '  }).catch(function() { st.done++; return 900; })'
         + '  .then(function(wait) { setTimeout(next, wait); });'
         + '};'
         + 'next(); return "started";'
}
var goneStatusScript = 'return JSON.stringify(window.__rfGone || null);'

// Age check page: taps reddit's own "continue", only after the user said yes in the app.
var over18Script = 'var b = document.querySelector("button[name=over18][value=yes]");'
                 + 'if (b) b.click(); return !!b;'

// Clicks the visible join/leave option in the subreddit sidebar.
var subscribeScript = 'var a = document.querySelector(".side .subscribe-button .option.active");'
                    + 'if (a) a.click(); return !!a;'

// Fills and submits the old.reddit login form with what the user typed in the native dialog.
function loginScript(user, pass) {
    return 'var f = document.querySelector("#login-form") || document.querySelector("form.login-form");'
         + 'if (!f) return false;'
         + 'var u = f.querySelector("input[name=user]"), p = f.querySelector("input[name=passwd]");'
         + 'if (!u || !p) return false;'
         + 'u.value = ' + JSON.stringify(String(user)) + '; p.value = ' + JSON.stringify(String(pass)) + ';'
         + 'var r = f.querySelector("input[name=rem]"); if (r) r.checked = true;'
         + 'var b = f.querySelector("button[type=submit]"); if (b) b.click(); else f.submit();'
         + 'return true;'
}

var logoutScript = 'var f = document.querySelector("form.logout"); if (f) f.submit(); return !!f;'

// Reddit-hosted media: the thumbnail preview.redd.it/<file>?<signed params> names the full
// picture i.redd.it/<file>, which needs no signature. Link posts (external-preview) have none.
function fullFromThumb(thumb) {
    var m = /^https:\/\/preview\.redd\.it\/([A-Za-z0-9_-]+\.(?:jpe?g|png|gif|webp))\?/i.exec(thumb || "")
    return m ? "https://i.redd.it/" + m[1] : ""
}

// https://v.redd.it/<id>/HLSPlaylist.m3u8?... -> https://v.redd.it/<id>/
function videoBase(hls) {
    var m = /^(https:\/\/v\.redd\.it\/[A-Za-z0-9]+\/)/.exec(hls || "")
    return m ? m[1] : ""
}

// Debug: the whole page the hidden view is on (for pages without a native view).
var pageDebugScript = 'var s = document.querySelector("#siteTable"), c = document.querySelector(".commentarea");'
                    + 'return location.href + "\\n" + document.title + "\\nbody: " + document.body.className'
                    + ' + "\\n" + (s ? s.outerHTML.slice(0, 15000) : "no #siteTable")'
                    + ' + "\\n" + (c ? c.outerHTML.slice(0, 15000) : "no .commentarea");'

function parse(r) {
    return typeof r === "string" ? JSON.parse(r) : r
}

function isImage(p) {
    return p.domain === "i.redd.it" || /\.(jpe?g|png|gif|webp)(\?.*)?$/i.test(p.url)
}

function ago(ms) {
    var s = Math.max(0, Math.floor((Date.now() - ms) / 1000))
    if (!ms) return ""
    if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    if (s < 86400 * 365) return Math.floor(s / 86400) + "d"
    return Math.floor(s / (86400 * 365)) + "y"
}

function num(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 10000) return Math.round(n / 1000) + "k"
    if (n >= 1000) return (n / 1000).toFixed(1) + "k"
    return "" + n
}
