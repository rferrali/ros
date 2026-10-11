# ros

`ghcr.io/ublue-os/bluefin-dx:stable` plus what used to be rpm-ostree layering on
my machine, built daily by CI from [ublue-os/image-template](https://github.com/ublue-os/image-template).

| Component | Source | Notes |
|---|---|---|
| Google Chrome | Google's rpm repo, latest | Moved to `/usr/lib/opt/google`; tmpfiles links `/opt/google` to it so PWA launchers keep working |
| Claude Desktop | Anthropic's apt repo, latest | Only shipped as a .deb; unpacked by `build_files/claude-desktop.sh` |
| GlobalProtect-openconnect | GitHub release RPM, pinned | Unsigned upstream, so version + SHA256 are pinned in `build.sh` |
| Dropbox (Nautilus extension + CLI) | Dropbox's rpm repo, latest | Plus `python3-gpg` so the CLI can verify the daemon it downloads |

Third-party repos are only enabled during the build, with signing keys pinned in
`build_files/keys/`. The build fails if any of the binaries above has unresolved
libraries on the current base.

## Updating

- Chrome, Claude Desktop, Dropbox and the Bluefin base: automatic, via the daily build.
- GlobalProtect: bump `GP_VERSION` and `GP_SHA256` in `build_files/build.sh`.

## Build locally

```sh
just build
```

## Rebase onto it

Drop the old layering first, so the same packages aren't layered on top of an
image that already contains them:

```sh
sudo rpm-ostree reset
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/rferrali/ros:stable
rpm-ostree status   # pending deployment: ros, no LayeredPackages/LocalPackages
systemctl reboot
```

Rollback: `sudo rpm-ostree rollback`, or pick the previous entry in the boot menu.
