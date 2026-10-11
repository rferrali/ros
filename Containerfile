# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
# Deliberately unpinned: the daily CI build (`just build` uses --pull=newer)
# is what tracks Bluefin's :stable updates.
FROM ghcr.io/ublue-os/bluefin-dx:stable

# /opt stays a symlink to /var/opt (bluefin-dx's Docker keeps containerd state
# there); build.sh moves Chrome's /opt payload into /usr instead.

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=secret,id=GITHUB_TOKEN,required=false \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
