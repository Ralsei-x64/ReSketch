#!/usr/bin/env bash
set -euo pipefail

case "${RELEASE_ENGINE:?}" in
    cef) expected_branch=main ;;
    main) expected_branch=Legacy ;;
    *) echo "Unknown release engine" >&2; exit 1 ;;
esac
[[ "${GITHUB_REF_NAME:?}" == "$expected_branch" ]]
workspace=${GITHUB_WORKSPACE:?}
# Container root and checkout's host user have different UIDs.
git config --global --add safe.directory "$workspace"
[[ "$(git rev-parse HEAD)" == "${GITHUB_SHA:?}" ]]
version=$(sed -n 's/^project(ReSketch VERSION \([^ ]*\) .*/\1/p' CMakeLists.txt)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
short_commit=$(git rev-parse --short=7 HEAD)
package_dir="$workspace/.ci-package"
mkdir -p "$package_dir" "$workspace/dist"
cp packaging/arch/PKGBUILD "$package_dir/PKGBUILD"
# Use the existing recipe, pinned to this checkout rather than a moving branch.
printf '\nsource=("resketch::git+file://%s#commit=%s")\noptions=(!debug !lto)\n' \
    "$workspace" "$GITHUB_SHA" >> "$package_dir/PKGBUILD"

useradd --create-home resketch-builder
printf 'resketch-builder ALL=(ALL) NOPASSWD: /usr/bin/pacman\n' > /etc/sudoers.d/resketch-builder
chmod 440 /etc/sudoers.d/resketch-builder
chown -R resketch-builder:resketch-builder "$workspace"
cd "$package_dir"
sudo -u resketch-builder env CMAKE_BUILD_PARALLEL_LEVEL=2 \
    makepkg --syncdeps --noconfirm --cleanbuild
packages=(resketch-git-*.pkg.tar.zst)
[[ ${#packages[@]} -eq 1 && -f "${packages[0]}" ]]
mkdir staged
bsdtar -xpf "${packages[0]}" -C staged
reported=$(sudo -u resketch-builder env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    "$package_dir/staged/usr/bin/resketch" --version)
[[ "$reported" == "ReSketch $version (commit $short_commit)" ]]
printf '%s\n' "$reported"
if [[ "$RELEASE_ENGINE" == cef ]]; then
    # CI has no display server or user-namespace sandbox. These switches
    # apply only to the isolated smoke test, never the packaged app.
    sudo -u resketch-builder env RESKETCH_CEF_FLAGS='--disable-gpu --no-sandbox --ozone-platform=headless' \
        bash "$workspace/tests/check-cef-startup.sh" "$package_dir/staged/usr/bin/resketch"
fi
asset="resketch-$RELEASE_ENGINE-$version-$short_commit-x86_64.pkg.tar.zst"
cp "${packages[0]}" "$workspace/dist/$asset"
cd "$workspace/dist"
sha256sum "$asset" > SHA256SUMS
