# ros

Personal bootc image: `ghcr.io/ublue-os/bluefin-dx:stable` plus what used to be
rpm-ostree layering on my machine. Built daily by GitHub Actions from
ublue-os/image-template, published as `ghcr.io/rferrali/ros:stable`. My machine
is rebased onto it (`ostree-unverified-registry:`).

## Scope

This repo is only about building the image. Shell/dotfile configuration (zsh
setup, `~/.zshrc`, switching the login shell) is handled separately, not here:
dotfiles live in `$HOME`, never in the image. The image only guarantees `zsh`
is installed; it never sets anyone's shell.

## Decisions

- Base is Fedora-based Bluefin, not Bluefin Dakota (GNOME OS, alpha, would need
  a reinstall). The `dakota` branch is a parked Dakota version, local only.
- Base image is deliberately unpinned (no digest): the daily build tracks
  `:stable`. Renovate is told not to pin it.
- Third-party repos (Google, Dropbox) are enabled only during the build, with
  keys pinned in `build_files/keys/`; their repo files are disabled in the image.
- Claude Desktop comes from Anthropic's signed apt repo (.deb, unpacked by
  `build_files/claude-desktop.sh`), not a community RPM.
- GlobalProtect comes from the GitHub release RPM, not the COPR (the COPR can't
  ship `gpgui` on image-based systems, yuezk/GlobalProtect-openconnect#467).
  "Latest" = newest release whose RPM is already uploaded; `GP_VERSION` pins.

## Gotchas

- `/opt` is `/var/opt`, which bootc doesn't update after first deploy. Chrome is
  moved to `/usr/lib/opt/google`; `system_files/usr/lib/tmpfiles.d/ros-opt.conf`
  links `/opt/google` back. PWA launchers depend on that path. Don't make `/opt`
  immutable: bluefin-dx's Docker keeps state there.
- Update size depends on stable layer packing:
  - `just ostree-rechunk` passes `--previous-build` (the published image) so
    the package-to-layer plan doesn't reshuffle between builds.
  - Files no RPM owns are lumped into one ~570 MB layer with the initramfs.
    Anything big or regenerated each build gets its own `user.component` xattr
    in `build.sh` (Chrome, Claude Desktop, `/etc/gconf`).
  - Adding a component repacks the image once (127-layer cap): one large client
    download, then it's stable. Baseline no-change update is ~120 MB.
- Branding: `branding/logo.png` is the source; `branding/render.sh` renders
  the Plymouth watermark and GDM logo into `system_files/` (committed, so the
  bytes never change between builds). GDM's logo is set by
  `zz1-ros.gschema.override`. Plymouth runs from the initramfs, so `build.sh`
  rebuilds it with Bluefin's dracut flags (reproducible: identical bytes for
  identical inputs) and tags it `user.component=initramfs`.
- Builds run `bootc container lint`; clean up scriptlet leftovers in `/var` and
  `/run` (see end of `build.sh`).
- CI cancels an in-progress build when a new push arrives (concurrency group).
- `just build` forwards `$GITHUB_TOKEN` as a build secret for the GitHub API.
