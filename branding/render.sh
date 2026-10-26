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

# Plymouth draws images at logical size and doubles them on HiDPI screens;
# 43 px matches the height of the Bluefin watermark it replaces.
render 43 system_files/usr/share/plymouth/themes/spinner/watermark.png

# GDM scales its logo to 48 logical px tall; 192 px stays sharp up to 4x.
render 192 system_files/usr/share/pixmaps/ros-gdm-logo.png
