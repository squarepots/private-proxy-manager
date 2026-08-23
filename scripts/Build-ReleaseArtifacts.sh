#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

version="$(tr -d '\r\n' < version.txt)"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "version.txt is not plain SemVer X.Y.Z: $version" >&2
  exit 1
fi
if [[ -d dist ]] && find dist -mindepth 1 -print -quit | grep -q .; then
  echo 'dist must be absent or empty before building release artifacts.' >&2
  exit 1
fi
mkdir -p dist

package_dirs=()
for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64; do
  goos="${target%/*}"
  goarch="${target#*/}"
  package_dir="dist/${goos}-${goarch}"
  package_dirs+=("$package_dir")
  mkdir -p "$package_dir/client/vendor"
  binary='route-steward'
  if [[ "$goos" == windows ]]; then binary='route-steward.exe'; fi
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build -trimpath -ldflags='-s -w' -o "$package_dir/$binary" ./cmd/route-steward
  cp LICENSE README.md THIRD_PARTY_NOTICES.md "$package_dir/"
  cp client/vendor/NOTICE.md client/vendor/LICENSE.qrcode-generator.txt "$package_dir/client/vendor/"

  archive="route-steward_${version}_${goos}_${goarch}"
  if [[ "$goos" == windows ]]; then
    (cd "$package_dir" && zip -qr "../${archive}.zip" "$binary" LICENSE README.md THIRD_PARTY_NOTICES.md client)
    member_command=(unzip -Z1 "dist/${archive}.zip")
  else
    tar -C "$package_dir" -czf "dist/${archive}.tar.gz" "$binary" LICENSE README.md THIRD_PARTY_NOTICES.md client
    member_command=(tar -tzf "dist/${archive}.tar.gz")
  fi

  expected_members=(
    LICENSE
    README.md
    THIRD_PARTY_NOTICES.md
    client/vendor/LICENSE.qrcode-generator.txt
    client/vendor/NOTICE.md
    "$binary"
  )
  if ! diff -u \
    <(printf '%s\n' "${expected_members[@]}" | sort) \
    <("${member_command[@]}" | sed -e 's#^\./##' -e '/\/$/d' | sort); then
    echo "Release archive has an unexpected member list: $archive" >&2
    exit 1
  fi
done

(cd dist && sha256sum route-steward_* > SHA256SUMS && sha256sum -c SHA256SUMS)
for package_dir in "${package_dirs[@]}"; do
  rm -rf -- "$package_dir"
done
