#!/usr/bin/env bash
# Copy-install home/ into the Copilot CLI home directory.
#
#   scripts/install.sh --dry-run   show what would change
#   scripts/install.sh             install; changed files are backed up first
#
# Target: $COPILOT_HOME if set, otherwise ~/.copilot.
# Only files under home/ are written. Nothing else in the target is touched or deleted.
# Backups go to <target>/.backup/<timestamp>/ mirroring the original paths.

set -euo pipefail

DRY_RUN=0
case "${1:-}" in
  --dry-run|-n) DRY_RUN=1 ;;
  "") ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/home"
DEST="${COPILOT_HOME:-$HOME/.copilot}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DEST/.backup/$STAMP"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "Source: $SRC"
echo "Target: $DEST"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run: no changes)"
echo

added=0; updated=0; unchanged=0

while IFS= read -r src; do
  rel="${src#$SRC/}"
  dst="$DEST/$rel"

  # Render: substitute the install location into hook configs.
  sed "s|__COPILOT_HOME__|$DEST|g" "$src" > "$tmp"

  if [ ! -e "$dst" ]; then
    echo "  add     $rel"
    added=$((added + 1))
  elif cmp -s "$tmp" "$dst"; then
    unchanged=$((unchanged + 1))
    continue
  else
    echo "  update  $rel   (backup: .backup/$STAMP/$rel)"
    updated=$((updated + 1))
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$(dirname "$BACKUP/$rel")"
      cp -p "$dst" "$BACKUP/$rel"
    fi
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$tmp" "$dst"
    case "$rel" in *.sh) chmod 755 "$dst" ;; *) chmod 644 "$dst" ;; esac
  fi
done < <(find "$SRC" -type f ! -name '.DS_Store' | sort)

echo
echo "added: $added  updated: $updated  unchanged: $unchanged"
if [ "$DRY_RUN" -eq 0 ] && [ $((added + updated)) -gt 0 ]; then
  echo "Start a new Copilot CLI session for instruction and hook changes to take effect."
fi
