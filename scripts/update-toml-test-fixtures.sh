#!/usr/bin/env bash
# Refresh t/fixtures/toml-test from a toml-lang/toml-test release.
# Run from the repository root. Only the fixture directory is modified.
set -euo pipefail

REPO_URL="https://github.com/toml-lang/toml-test"
TOML_VERSION="${TOML_VERSION:-1.1.0}"
DEST="${DEST:-t/fixtures/toml-test}"
TIMEOUT_SECS="${TIMEOUT_SECS:-300}"
TAG="${1:-}"

# Run a command under a wall-clock limit. Prefer GNU timeout, then gtimeout,
# then a perl alarm so the script also works on a stock macOS.
run_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECS" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT_SECS" "$@"
  else
    perl -e 'alarm shift; exec @ARGV' "$TIMEOUT_SECS" "$@"
  fi
}

if [ -z "$TAG" ]; then
  refs="$(run_timeout git ls-remote --tags --refs --sort=-v:refname "$REPO_URL" || true)"
  TAG="$(printf '%s\n' "$refs" \
    | sed -n 's#.*refs/tags/##p' \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed -n '1p' || true)"
fi

if [ -z "$TAG" ]; then
  echo "could not resolve a release tag; pass one explicitly" >&2
  exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/toml-test.XXXXXX")"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

echo "cloning $REPO_URL at $TAG"
run_timeout git clone --depth 1 --branch "$TAG" "$REPO_URL" "$work"

manifest="$work/tests/files-toml-$TOML_VERSION"
if [ ! -f "$manifest" ]; then
  echo "manifest not found for TOML $TOML_VERSION: tests/files-toml-$TOML_VERSION" >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/valid" "$DEST/invalid"

count=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  mkdir -p "$DEST/$(dirname "$rel")"
  cp -p "$work/tests/$rel" "$DEST/$rel"
  count=$((count + 1))
done < "$manifest"

cp -p "$manifest" "$DEST/files-toml-$TOML_VERSION"
cp -p "$work/LICENSE" "$DEST/LICENSE"

echo "imported $count fixtures for TOML $TOML_VERSION from $TAG into $DEST"
