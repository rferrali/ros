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

### GlobalProtect-openconnect: upstream's release RPM is unsigned, so pin its hash.

GP_VERSION=2.6.5
GP_SHA256=e1e72666df83d5715de3230f0ccc867f132187ac420473c34ceadb75bee195bc
GP_RPM=/tmp/globalprotect-openconnect-${GP_VERSION}-1.x86_64.rpm
curl -fsSL -o "$GP_RPM" \
  "https://github.com/yuezk/GlobalProtect-openconnect/releases/download/v${GP_VERSION}/${GP_RPM##*/}"
echo "${GP_SHA256}  ${GP_RPM}" | sha256sum -c -

### Packages

# /opt -> /var/opt, which the base image leaves to tmpfiles at boot.
mkdir -p /var/opt
dnf5 install -y \
  google-chrome-stable \
  nautilus-dropbox \
  python3-gpg \
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

update-mime-database /usr/share/mime
update-desktop-database -q /usr/share/applications
gtk-update-icon-cache -qf /usr/share/icons/hicolor

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

### Scriptlet leftovers bootc lint flags (GConf2 writes /var/lib/rpm-state).

dnf5 clean all
rm -rf /run/dnf /var/lib/rpm-state
