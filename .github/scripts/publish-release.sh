#!/usr/bin/env bash
set -euo pipefail

case "${RELEASE_ENGINE:?}" in
    cef) title=CEF; release_options=(--prerelease=true --latest=false) ;;
    main) title='Qt WebEngine'; release_options=(--prerelease=false --latest=true) ;;
    *) echo "Unknown release engine" >&2; exit 1 ;;
esac
version=$(sed -n 's/^project(ReSketch VERSION \([^ ]*\) .*/\1/p' CMakeLists.txt)
short_commit=$(git rev-parse --short=7 HEAD)
tag="$RELEASE_ENGINE-v$version-$short_commit"
asset="resketch-$RELEASE_ENGINE-$version-$short_commit-x86_64.pkg.tar.zst"
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
printf 'Automated x86_64 Arch Linux package from `%s`.\n\nVersion: %s\nCommit: `%s`\n\nInstall with `sudo pacman -U %s`.\n' \
    "${GITHUB_REF_NAME:?}" "$version" "${GITHUB_SHA:?}" "$asset" > "$notes"
# Keep the release private until every asset is uploaded; retries can finish a draft.
if draft=$(gh release view "$tag" --json isDraft --jq .isDraft 2>/dev/null); then
    if [[ "$draft" == false ]]; then
        printf 'Release %s is already published.\n' "$tag"
        exit 0
    fi
else
    gh release create "$tag" --draft --target "$GITHUB_SHA" \
        --title "ReSketch $version — $title ($short_commit)" --notes-file "$notes"
fi
gh release upload "$tag" "dist/$asset" dist/SHA256SUMS --clobber
gh release edit "$tag" --draft=false "${release_options[@]}"
