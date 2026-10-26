#!/bin/bash
# Render the boot/login logos from branding/logo.png into system_files/.
# Outputs are committed rather than rendered during the image build, so their
# bytes never change between builds (which would churn image layers).
set -euo pipefail

cd "$(dirname "$0")/.."
src=branding/logo.png

# Trim the transparent padding, resize, and drop metadata chunks (timestamps)
# so re-running this on an unchanged logo.png gives identical files.
render() {
  magick "$src" -trim +repage -resize "x$1" -strip \
    -define png:exclude-chunk=date,time "$2"
}

# Plymouth draws the watermark 1:1 in physical pixels; 43 px matches the
# height of the Bluefin watermark it replaces.
render 43 system_files/usr/share/plymouth/themes/spinner/watermark.png

# GDM always scales its logo to fill a 48 logical px tall slot (96 physical
# px at 2x). To match Plymouth's 43 physical px, pad the wordmark into a
# transparent canvas: 86 px tall inside 192 px, i.e. 43 inside 96 at 2x.
gdm=system_files/usr/share/pixmaps/ros-gdm-logo.png
render 86 "$gdm"
magick "$gdm" -background none -gravity center -extent "x192" -strip \
  -define png:exclude-chunk=date,time "$gdm"
