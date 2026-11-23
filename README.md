# Reddfish

Native Reddit client for Sailfish OS 5.x (Silica), styled after Infinity for Reddit.
No API key needed: Reddit no longer hands out new ones, so Reddfish reads old.reddit.com
in a hidden WebView ("reader mode") and shows everything with native Silica views.
No web page is ever shown.

- Feed cards: subreddit, author, age, title, big picture / video / gallery, votes, comments.
- Home = your saved subreddits as one feed; r/popular, r/all, any subreddit or u/user.
- Posts with comments collapsed until "Show comments".
- Vote, join/leave, follow users, share, save images and videos.
- Muted video autoplay (setting), redgifs, NSFW filter and blur (settings).
- Import subscriptions and users from an Infinity backup (existence checked first).
- Log in with your Reddit account in a native dialog. Reddit now requires login for
  old.reddit.com, so the app needs it too. The password is never stored.

## Build
WSL Platform SDK: `sh tools/build-rpm.sh` (runs `tools/qml-check.sh` first), or `sfdk build`.
RPM lands in `RPMS/`.

## Tests
- `tools/reader-test.html`: checks `qml/js/reader.js` against fake old.reddit markup.
  Serve the project folder (`python -m http.server`) and open `tools/reader-test.html`.
- On a device: `REDDFISH_SELFTEST="url url comments ..." QT_LOGGING_TO_CONSOLE=1 harbour-reddfish`
  opens the pages 15 s apart and logs what it reads.

## License
Copyright (C) 2026 Roterfux

This program is free software: you can redistribute it and/or modify it under the terms of
the GNU General Public License as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version. See [LICENSE](LICENSE).

SPDX-License-Identifier: GPL-3.0-or-later
