#!/usr/bin/env bash
# Builds the Android app, puts it into the server image and pushes the image
# to GitHub. On the NAS afterwards: Container -> super-papagei -> Aktualisieren.
#
#   ./release.sh 1.1.8            server version to publish
#   ./release.sh 1.1.8 --no-push  build locally only
#
# The app version comes from app/pubspec.yaml ("version: 1.0.1+2"). Raise the
# build number (+2, +3, ...) for every app release, or phones won't see an update.
set -euo pipefail

SERVER_VERSION="${1:?Server-Version angeben, z. B. ./release.sh 1.1.8}"
PUSH="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../app"

# Your own settings live in release.local (not in the repository), e.g.:
#   IMAGE=ghcr.io/<github-name>/super-papagei-server
#   DEFAULT_SERVER=https://audio.example.org
IMAGE="super-papagei-server"
DEFAULT_SERVER=""
PUBLIC_URL=""
OPERATOR_NAME=""
OPERATOR_URL=""
[ -f "$HERE/release.local" ] && . "$HERE/release.local"

APP_LINE="$(grep -E '^version:' "$APP/pubspec.yaml" | head -1 | awk '{print $2}')"
APP_VERSION="${APP_LINE%%+*}"
APP_BUILD="${APP_LINE##*+}"
echo "App $APP_VERSION (Build $APP_BUILD) -> Server $SERVER_VERSION"

(cd "$APP" && flutter build apk --release --dart-define=DEFAULT_SERVER="$DEFAULT_SERVER" >/dev/null)
mkdir -p "$HERE/download"
cp "$APP/build/app/outputs/flutter-apk/app-release.apk" "$HERE/download/super-papagei.apk"
printf '{"version": "%s", "build": %s}\n' "$APP_VERSION" "$APP_BUILD" > "$HERE/download/app-version.json"

sed -i '' -E "s/^VERSION = \"[^\"]+\"/VERSION = \"${SERVER_VERSION}\"/" "$HERE/app/main.py"
sed -i '' -E "s/org.opencontainers.image.version=\"[^\"]+\"/org.opencontainers.image.version=\"${SERVER_VERSION}\"/" "$HERE/Dockerfile"

if [ "$PUSH" = "--no-push" ]; then
  docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
    --build-arg PUBLIC_URL="$PUBLIC_URL" --build-arg OPERATOR_NAME="$OPERATOR_NAME" --build-arg OPERATOR_URL="$OPERATOR_URL" \
    -t "super-papagei-server:${SERVER_VERSION}" --load "$HERE"
else
  docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
    --build-arg PUBLIC_URL="$PUBLIC_URL" --build-arg OPERATOR_NAME="$OPERATOR_NAME" --build-arg OPERATOR_URL="$OPERATOR_URL" \
    -t "${IMAGE}:${SERVER_VERSION}" -t "${IMAGE}:latest" --push "$HERE"
  echo "Fertig. Auf dem NAS: Container -> super-papagei -> Aktualisieren."
fi
