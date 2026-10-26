#!/bin/bash
# Everything that used to be rpm-ostree layering on this machine, plus Claude
# Desktop. Third-party repos are verified against keys pinned in keys/ and
# removed again, so the image itself never pulls from them.

set -ouex pipefail

cp -avf "/ctx/system_files"/. /

### Third-party repos (build time only)

cat > /etc/yum.repos.d/ros-google-chrome.repo <<'EOF'
[ros-google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
gpgcheck=1
gpgkey=file:///ctx/keys/google-chrome.asc
EOF

cat > /etc/yum.repos.d/ros-dropbox.repo <<'EOF'
[ros-dropbox]
name=Dropbox
baseurl=https://linux.dropbox.com/fedora/$releasever/
gpgcheck=1
gpgkey=file:///ctx/keys/dropbox.asc
EOF

### GlobalProtect-openconnect from its GitHub release. Not the COPR: that build
### omits gpgui and expects to download it into /usr at runtime, which can't
### work on an image-based system (yuezk/GlobalProtect-openconnect#467).
### The RPM is unsigned; it's checked against the SHA256 digest GitHub records
### for the release asset.

GP_VERSION=latest  # or a tag such as v3.0.2 to pin
GP_API=https://api.github.com/repos/yuezk/GlobalProtect-openconnect/releases
GP_AUTH=()
# CI passes its token as a build secret; GitHub's anonymous API limit is per IP
# and shared runner IPs exhaust it.
if [[ -s /run/secrets/GITHUB_TOKEN ]]; then
  GP_AUTH=(-H "Authorization: Bearer $(< /run/secrets/GITHUB_TOKEN)")
fi
# "latest" means the newest stable release whose RPM is already uploaded:
# assets appear over several minutes after a release is published.
read -r GP_URL GP_DIGEST < <(
  curl -fsSL "${GP_AUTH[@]}" "$GP_API?per_page=10" | jq -er --arg tag "$GP_VERSION" '
    [ .[] | select(.draft | not) | select(.prerelease | not)
      | select($tag == "latest" or .tag_name == $tag)
      | .assets[] | select(.name | test("^globalprotect-openconnect-.*\\.x86_64\\.rpm$"))
      | select(.digest != null) ]
    | first // error("no release \($tag) with an x86_64 RPM")
    | "\(.browser_download_url) \(.digest | ltrimstr("sha256:"))"'
)
GP_RPM=/tmp/${GP_URL##*/}
curl -fsSL -o "$GP_RPM" "$GP_URL"
echo "${GP_DIGEST}  ${GP_RPM}" | sha256sum -c -

### Packages

# /opt -> /var/opt, which the base image leaves to tmpfiles at boot.
mkdir -p /var/opt
dnf5 install -y \
  google-chrome-stable \
  nautilus-dropbox \
  python3-gpg \
  zsh \
  "$GP_RPM"

rm -f /etc/yum.repos.d/ros-*.repo
# Chrome's and Dropbox's scriptlets drop their own repo files; the image is the
# update channel, so keep them disabled.
for repo in /etc/yum.repos.d/google-chrome.repo /etc/yum.repos.d/dropbox.repo; do
  [[ -f $repo ]] && sed -i 's/^enabled=.*/enabled=0/' "$repo"
done

### Chrome lives in /opt, which is /var/opt here and never updated by bootc
### after first deploy. Move it into /usr like rpm-ostree layering does; the
### tmpfiles.d rule from system_files links /opt/google back to it, so PWA
### launchers pointing at /opt/google/chrome keep working.

mkdir -p /usr/lib/opt
mv /var/opt/google /usr/lib/opt/google
rmdir /var/opt

### Claude Desktop (Anthropic only publishes a .deb)

/ctx/claude-desktop.sh

### Neither tree is owned by an RPM (the deb is unpacked; Chrome moved out of
### the /opt path its RPM records), so rpm-ostree's chunker would lump both
### into one ~1 GB "unpackaged content" layer shared with the initramfs. Give
### each its own layer so an update only re-downloads the app that changed.

setfattr -n user.component -v google-chrome /usr/lib/opt/google
setfattr -n user.component -v claude-desktop /usr/lib/claude-desktop
# GConf2's scriptlet (a nautilus-dropbox dependency) regenerates this tree with
# different bytes on every build; alone, it would force a re-download of the
# whole unpackaged-content layer (initramfs, Homebrew tarball, ~570 MB).
setfattr -n user.component -v gconf /etc/gconf

update-mime-database /usr/share/mime
update-desktop-database -q /usr/share/applications
gtk-update-icon-cache -qf /usr/share/icons/hicolor

### Branding (assets rendered by branding/render.sh, copied in from
### system_files): GDM's logo comes from the zz1-ros GSettings override.
### Plymouth runs from the initramfs, which carries its own copy of the theme,
### so the initramfs is rebuilt the way Bluefin builds it.

glib-compile-schemas /usr/share/glib-2.0/schemas

KVER=$(ls /usr/lib/modules)
[[ $(wc -w <<< "$KVER") -eq 1 ]] || { echo "expected one kernel, got: $KVER"; exit 1; }
INITRAMFS=/usr/lib/modules/$KVER/initramfs.img
DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$KVER" --reproducible --add ostree -f "$INITRAMFS"
chmod 0600 "$INITRAMFS"
# No user.component here: rpm-ostree names the initramfs itself and ignores
# the xattr. It shares a layer with the unpackaged content; that's fine because
# --reproducible gives identical bytes until the kernel or base changes.

### Smoke test: fail the build if anything doesn't link on this base.

missing=$(
  for f in \
    /usr/lib/opt/google/chrome/chrome \
    /usr/lib/claude-desktop/claude-desktop \
    /usr/bin/gpclient /usr/bin/gpservice /usr/bin/gpauth \
    /usr/lib64/nautilus/extensions-4/libnautilus-dropbox.so
  do
    ldd "$f" | sed -n "s|^\s*\(\S*\) => not found|$f: \1|p"
  done
)
[[ -z $missing ]] || { echo "Unresolved libraries:"; echo "$missing"; exit 1; }
python3 -c 'import gpg'

### Leftovers bootc lint flags: GConf2 scriptlet state, dnf countme markers.

dnf5 clean all
rm -rf /run/dnf /var/lib/rpm-state /var/lib/dnf/repos
