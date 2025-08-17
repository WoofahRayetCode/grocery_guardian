#!/usr/bin/env bash
set -euo pipefail

# Upload a file to Google Drive into a specific folder, overwriting any existing file with the same name.
#
# Prefers rclone if available (recommended), falls back to the legacy `gdrive` CLI if installed.
#
# Usage:
#   tools/upload_to_gdrive.sh [files_or_dirs...]
#     - If you pass one or more files/directories, all APKs found will be uploaded.
#     - If no args are provided, the script scans common Flutter/Gradle output dirs
#       for both release and debug APKs and uploads whatever it finds.
#
# Config (env):
#   GG_DRIVE_FOLDER_ID   Google Drive folder ID (default points to the provided folder)
#   GG_RCLONE_REMOTE     rclone remote name for Google Drive (default: gdrive)
#   GG_UPLOAD_ENABLED    If set to "0", skip uploading (default: upload enabled)

has_args=0
if [[ $# -gt 0 ]]; then
  has_args=1
fi

FOLDER_ID="${GG_DRIVE_FOLDER_ID:-1eNEb3RV-kqUDPIaYnBCftAdI1JoT-ZzW}"
REMOTE="${GG_RCLONE_REMOTE:-gdrive}"
UPLOAD_ENABLED="${GG_UPLOAD_ENABLED:-1}"

if [[ "$UPLOAD_ENABLED" == "0" ]]; then
  echo "==> Upload disabled by GG_UPLOAD_ENABLED=0; skipping upload for $FILE_PATH"
  exit 0
fi

upload_file() {
  local FILE_PATH="$1"
  local BASENAME
  BASENAME=$(basename -- "$FILE_PATH")
  if [[ ! -f "$FILE_PATH" ]]; then
    echo "WARN: Skipping non-existent file: $FILE_PATH"
    return 0
  fi

  if try_rclone_upload; then
    echo "==> Upload complete via rclone: $BASENAME"
    return 0
  fi

  if try_gdrive_cli_upload; then
    echo "==> Upload complete via gdrive CLI: $BASENAME"
    return 0
  fi

  echo "ERROR: No supported Google Drive uploader found for $BASENAME"
  return 3
}

collect_targets_from_args() {
  local -n OUT_ARR=$1
  shift || true
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      OUT_ARR+=("$path")
    elif [[ -d "$path" ]]; then
      while IFS= read -r -d '' f; do OUT_ARR+=("$f"); done < <(find "$path" -type f -name "*.apk" -print0)
    else
      echo "WARN: Not found: $path"
    fi
  done
}

collect_default_targets() {
  local -n OUT_ARR=$1
  # Common Flutter outputs
  for f in \
    "build/app/outputs/flutter-apk/app-oss-release.apk" \
    "build/app/outputs/flutter-apk/app-play-release.apk" \
    "build/app/outputs/flutter-apk/app-release.apk" \
    "build/app/outputs/flutter-apk/app-oss-debug.apk" \
    "build/app/outputs/flutter-apk/app-play-debug.apk" \
    "build/app/outputs/flutter-apk/app-debug.apk"; do
    [[ -f "$f" ]] && OUT_ARR+=("$f")
  done
  # Fallback to Gradle output trees
  if [[ -d "android/app/build/outputs/apk" ]]; then
    while IFS= read -r -d '' f; do OUT_ARR+=("$f"); done < <(find android/app/build/outputs/apk -type f -name "*.apk" -print0)
  fi
}

try_rclone_upload() {
  if ! command -v rclone >/dev/null 2>&1; then
    return 1
  fi
  echo "==> Uploading with rclone to folder $FOLDER_ID as $BASENAME (remote=$REMOTE)"
  # --drive-root-folder-id makes the remote path relative to the folder ID.
  # copyto overwrites the destination file by name in that folder.
  rclone copyto \
    --drive-root-folder-id "$FOLDER_ID" \
    --progress --transfers 1 --checkers 4 --retries 3 --low-level-retries 10 \
    "$FILE_PATH" "$REMOTE:$BASENAME"
}

try_gdrive_cli_upload() {
  if ! command -v gdrive >/dev/null 2>&1; then
    return 1
  fi
  echo "==> Uploading with gdrive CLI to folder $FOLDER_ID as $BASENAME"
  # Look for existing file with same name in the folder
  local FILE_ID
  FILE_ID=$(gdrive files list --query "name = '$BASENAME' and '$FOLDER_ID' in parents and trashed = false" --no-header --max 1 2>/dev/null | awk '{print $1}' | head -n1 || true)
  if [[ -n "$FILE_ID" ]]; then
    echo "==> Found existing file ($FILE_ID); updating in place"
    gdrive files update --file "$FILE_ID" "$FILE_PATH"
  else
    echo "==> No existing file; uploading new"
    gdrive files upload --parent "$FOLDER_ID" --name "$BASENAME" "$FILE_PATH"
  fi
}

TARGETS=()
if [[ $has_args -eq 1 ]]; then
  collect_targets_from_args TARGETS "$@"
else
  collect_default_targets TARGETS
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "ERROR: No APK files found to upload."
  echo "Hints:"
  echo "  - Build your app first (e.g., flutter build apk --release --flavor oss)"
  echo "  - Or pass one or more paths: tools/upload_to_gdrive.sh <file_or_dir>..."
  exit 2
fi

ec=0
for f in "${TARGETS[@]}"; do
  echo "==> Processing: $f"
  if ! FILE_PATH="$f" BASENAME="$(basename -- "$f")" upload_file "$f"; then
    ec=3
  fi
done

if [[ $ec -ne 0 ]]; then
  cat <<EOF
ERROR: No supported Google Drive uploader found.
Install one of the following and retry:

1) rclone (recommended)
   - Install: https://rclone.org/install/
   - Configure a remote named 'gdrive': rclone config
     Choose 'drive' backend and follow prompts (use your Google account).
   - Then re-run the build script (uses remote: $REMOTE)

2) gdrive (legacy CLI)
   - Install: https://github.com/prasmussen/gdrive
   - Authenticate: gdrive about

Alternatively, set GG_UPLOAD_ENABLED=0 to skip uploading.
EOF
fi
exit $ec
