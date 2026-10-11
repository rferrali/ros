#!/usr/bin/env bash
# Download the newest amd64 build of a package from a signed apt repository.
#
#   apt-fetch.sh <repo-url> <suite> <component> <package> <keyfile> <dest.deb>
#
# Trust chain: InRelease is verified against the pinned key in build_files/keys,
# the Packages index against the SHA256 in InRelease, and the .deb against the
# SHA256 in Packages. Any mismatch aborts the build.
set -euo pipefail

repo=$1 suite=$2 component=$3 package=$4 keyfile=$5 dest=$6
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gpg --batch --quiet --dearmor --output "$work/keyring.gpg" "$keyfile"
curl -fsSL "$repo/dists/$suite/InRelease" -o "$work/InRelease"
gpgv --quiet --keyring "$work/keyring.gpg" --output "$work/Release" "$work/InRelease"

index="$component/binary-amd64/Packages"
want=$(awk -v f="$index" '/^SHA256:/{s=1;next} /^[^ ]/{s=0} s && $3==f {print $1}' "$work/Release")
[[ -n $want ]] || { echo "apt-fetch: $index not listed in InRelease" >&2; exit 1; }
curl -fsSL "$repo/dists/$suite/$index" -o "$work/Packages"
echo "$want  $work/Packages" | sha256sum --quiet -c -

# Emit "version filename sha256" for every stanza of $package, keep the newest.
read -r version filename sha256 < <(
  awk -v p="$package" '
    /^Package:/  {pkg=$2}
    /^Version:/  {ver=$2}
    /^Filename:/ {fn=$2}
    /^SHA256:/   {sha=$2}
    /^$/ { if (pkg==p) print ver, fn, sha; pkg=ver=fn=sha="" }
    END  { if (pkg==p) print ver, fn, sha }
  ' "$work/Packages" | sort -V -k1,1 | tail -n1
)
[[ -n ${filename:-} ]] || { echo "apt-fetch: $package not found in $repo" >&2; exit 1; }

echo "apt-fetch: $package $version"
curl -fsSL "$repo/$filename" -o "$dest"
echo "$sha256  $dest" | sha256sum --quiet -c -
