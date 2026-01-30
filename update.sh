#!/usr/bin/env bash
# update.sh - Check for and apply OpenCode version updates
# Usage:
#   ./update.sh          # Check for updates, output UPDATE_NEEDED and NEW_VERSION
#   ./update.sh --update # Actually update version.json with new hashes

set -euo pipefail

REPO="anomalyco/opencode"
VERSION_FILE="$(dirname "$0")/version.json"

# Get current version from version.json
get_current_version() {
  jq -r '.version' "$VERSION_FILE"
}

# Query GitHub API for releases and find newest non-prerelease, non-draft
get_latest_version() {
  local releases
  releases=$(curl -s "https://api.github.com/repos/$REPO/releases")

  # Filter for non-prerelease, non-draft releases and get the first one
  echo "$releases" | jq -r '
    [.[] | select(.prerelease == false and .draft == false)] |
    .[0].tag_name // empty
  ' | sed 's/^v//'
}

# Convert nix-prefetch-url output (base32) to SRI format
hash_to_sri() {
  local hash="$1"
  nix hash convert --hash-algo sha256 --to sri "$hash"
}

# Fetch hash for a given URL
fetch_hash() {
  local url="$1"
  local hash
  hash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)
  hash_to_sri "$hash"
}

# Check if stored hash matches current upstream hash (spot check one platform)
verify_current_hash() {
  local version="$1"
  local platform="x86_64-linux"  # Use linux x64 as the canary

  local stored_hash
  stored_hash=$(jq -r ".hashes[\"$platform\"]" "$VERSION_FILE")

  local url
  url=$(get_download_url "$version" "$platform")

  local current_hash
  current_hash=$(fetch_hash "$url")

  [[ "$stored_hash" == "$current_hash" ]]
}

# Get download URL for a platform
get_download_url() {
  local version="$1"
  local platform="$2"

  case "$platform" in
    x86_64-linux)
      echo "https://github.com/$REPO/releases/download/v${version}/opencode-linux-x64.tar.gz"
      ;;
    aarch64-linux)
      echo "https://github.com/$REPO/releases/download/v${version}/opencode-linux-arm64.tar.gz"
      ;;
    x86_64-darwin)
      echo "https://github.com/$REPO/releases/download/v${version}/opencode-darwin-x64.zip"
      ;;
    aarch64-darwin)
      echo "https://github.com/$REPO/releases/download/v${version}/opencode-darwin-arm64.zip"
      ;;
    *)
      echo "Unknown platform: $platform" >&2
      return 1
      ;;
  esac
}

# Main logic
main() {
  local update_mode=false

  if [[ "${1:-}" == "--update" ]]; then
    update_mode=true
  fi

  local current_version
  current_version=$(get_current_version)

  local latest_version
  latest_version=$(get_latest_version)

  if [[ -z "$latest_version" ]]; then
    echo "ERROR: Could not fetch latest version from GitHub" >&2
    exit 1
  fi

  # Compare versions
  if [[ "$current_version" == "$latest_version" ]]; then
    # Version matches, but verify hash hasn't changed (upstream rebuild detection)
    echo "Verifying upstream hash hasn't changed..." >&2
    if verify_current_hash "$current_version"; then
      echo "UPDATE_NEEDED=false"
      echo "NEW_VERSION=$current_version"
      exit 0
    else
      echo "Hash mismatch detected - upstream rebuilt $current_version" >&2
      # Fall through to update logic with same version
      latest_version="$current_version"
    fi
  fi

  echo "UPDATE_NEEDED=true"
  echo "NEW_VERSION=$latest_version"

  if [[ "$update_mode" == true ]]; then
    echo "Updating version.json to $latest_version..." >&2

    local platforms=("x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin")

    # Start building the new JSON
    local json_content
    json_content=$(cat <<EOF
{
  "version": "$latest_version",
  "hashes": {
EOF
)

    local first=true
    for platform in "${platforms[@]}"; do
      local url
      url=$(get_download_url "$latest_version" "$platform")
      echo "Fetching hash for $platform..." >&2

      local hash
      hash=$(fetch_hash "$url")

      if [[ "$first" == true ]]; then
        first=false
      else
        json_content+=","
      fi
      json_content+=$'\n'"    \"$platform\": \"$hash\""
    done

    json_content+=$'\n'"  }"$'\n'"}"

    echo "$json_content" > "$VERSION_FILE"
    echo "Updated version.json successfully!" >&2
  fi
}

main "$@"
