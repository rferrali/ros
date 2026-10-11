#!/bin/bash
# Claude Desktop from Anthropic's signed apt repo, unpacked into /. The deb
# already installs under /usr/lib/claude-desktop; this replays the parts of its
# postinst that matter outside apt (search provider, MIME types, ccd launcher).
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

/ctx/lib/apt-fetch.sh https://downloads.claude.ai/claude-desktop/apt/stable stable main \
  claude-desktop /ctx/keys/claude-desktop.asc "$work/claude-desktop.deb"

(cd "$work" && ar x claude-desktop.deb)
tar -xpf "$work"/data.tar.* -C / --no-overwrite-dir

res=/usr/lib/claude-desktop/resources
install -Dm644 -t /usr/share/gnome-shell/search-providers \
  "$res/gnome-search-provider/com.anthropic.Claude.search-provider.ini"
install -Dm644 -t /usr/share/dbus-1/services \
  "$res/gnome-search-provider/com.anthropic.Claude.SearchProvider.service"
install -Dm644 -t /usr/share/mime/packages \
  "$res/linux-mime/com.anthropic.Claude.xml"
if [[ -x $res/bin/ccd ]]; then
  ln -sf ../lib/claude-desktop/resources/bin/ccd /usr/bin/ccd
fi
