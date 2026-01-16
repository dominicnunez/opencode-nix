{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip,
}:

let
  versionInfo = lib.importJSON ./version.json;
  version = versionInfo.version;
  hashes = versionInfo.hashes;

  # Map Nix system to GitHub asset platform suffix
  platformMap = {
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
    "x86_64-darwin" = "darwin-x64";
    "aarch64-darwin" = "darwin-arm64";
  };

  isDarwin = stdenv.hostPlatform.isDarwin;
  assetExt = if isDarwin then "zip" else "tar.gz";

  system = stdenv.hostPlatform.system;
  platform = platformMap.${system} or (throw "Unsupported platform: ${system}");
  hash = hashes.${system} or (throw "No hash for platform: ${system}");

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-${platform}.${assetExt}";
    inherit hash;
  };

  # Home Manager detection wrapper script
  wrapperScript = ''
    #!/usr/bin/env bash

    # Home Manager detection function
    is_home_manager_active() {
      [[ -n "''${HM_SESSION_VARS:-}" ]] ||
      [[ -d "$HOME/.config/home-manager" ]] ||
      [[ -d "/etc/profiles/per-user/$USER" ]]
    }

    # Get state file path (XDG compliant)
    get_state_file() {
      local data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
      echo "$data_home/opencode-nix/.symlink-state"
    }

    # Read current state from file
    read_state() {
      local state_file
      state_file="$(get_state_file)"
      if [[ -f "$state_file" ]]; then
        # shellcheck source=/dev/null
        source "$state_file"
        echo "''${BINARY_PATH:-}:''${HM_DETECTED:-}"
      else
        echo ":"
      fi
    }

    # Write state to file
    write_state() {
      local binary_path="$1"
      local hm_detected="$2"
      local state_file
      state_file="$(get_state_file)"
      local state_dir
      state_dir="$(dirname "$state_file")"

      mkdir -p "$state_dir"
      cat > "$state_file" << STATE_EOF
    BINARY_PATH=$binary_path
    HM_DETECTED=$hm_detected
    STATE_EOF
    }

    # Symlink management (only when state changes)
    manage_symlink() {
      local target_dir="$HOME/.local/bin"
      local symlink_path="$target_dir/opencode"
      local binary_path="@out@/bin/.opencode-unwrapped"
      local hm_detected

      if is_home_manager_active; then
        hm_detected="true"
      else
        hm_detected="false"
      fi

      # Check if state has changed
      local current_state="$binary_path:$hm_detected"
      local stored_state
      stored_state="$(read_state)"

      if [[ "$current_state" == "$stored_state" ]]; then
        # State unchanged, skip symlink management
        return 0
      fi

      # State changed, perform symlink management
      if [[ "$hm_detected" == "true" ]]; then
        # Home Manager detected - skip symlink creation
        if [[ -z "''${OPENCODE_NIX_QUIET:-}" ]]; then
          echo "[opencode-nix] Home Manager detected, skipping symlink creation" >&2
        fi
      else
        # No Home Manager - create convenience symlink
        mkdir -p "$target_dir"
        ln -sf "$binary_path" "$symlink_path"
        if [[ -z "''${OPENCODE_NIX_QUIET:-}" ]]; then
          echo "[opencode-nix] Created symlink: $symlink_path -> $binary_path" >&2
        fi
      fi

      # Update state file
      write_state "$binary_path" "$hm_detected"
    }

    # Run symlink management
    manage_symlink

    # Execute the actual binary
    exec "@out@/bin/.opencode-unwrapped" "$@"
  '';
in
stdenv.mkDerivation {
  pname = "opencode";
  inherit version src;

  sourceRoot = ".";

  nativeBuildInputs =
    lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
    ]
    ++ lib.optionals isDarwin [
      unzip
    ];

  # autoPatchelfHook will find required libraries automatically
  buildInputs = [ ];

  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    if [ "${lib.boolToString isDarwin}" = "true" ]; then
      unzip -q $src
    else
      tar -xzf $src
    fi
    runHook postUnpack
  '';

  installPhase = ''
        runHook preInstall
        mkdir -p $out/bin

        # Install unwrapped binary
        cp opencode $out/bin/.opencode-unwrapped
        chmod +x $out/bin/.opencode-unwrapped

        # Install wrapper script
        cat > $out/bin/opencode << 'WRAPPER_EOF'
    ${wrapperScript}
    WRAPPER_EOF
        chmod +x $out/bin/opencode

        # Substitute @out@ placeholder
        substituteInPlace $out/bin/opencode --replace-quiet "@out@" "$out"

        runHook postInstall
  '';

  meta = with lib; {
    description = "OpenCode CLI - AI coding assistant in your terminal";
    homepage = "https://opencode.ai";
    license = licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "opencode";
  };
}
