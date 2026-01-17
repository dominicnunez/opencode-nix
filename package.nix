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

    # Symlink management (only when target changes)
    manage_symlink() {
      local target_dir="$HOME/.local/bin"
      local symlink_path="$target_dir/opencode"
      local binary_path="@out@/bin/.opencode-unwrapped"

      # If Home Manager is active, clean up any orphaned symlink and skip creation
      if is_home_manager_active; then
        # Remove symlink if it points to a Nix store path (we likely created it)
        if [[ -L "$symlink_path" ]]; then
          local link_target
          link_target="$(readlink "$symlink_path" 2>/dev/null || echo "")"
          if [[ "$link_target" == /nix/store/* ]]; then
            rm -f "$symlink_path"
            if [[ -z "''${OPENCODE_NIX_QUIET:-}" ]]; then
              echo "[opencode-nix] Removed orphaned symlink: $symlink_path (Home Manager now manages opencode)" >&2
            fi
          fi
        fi
        return 0
      fi

      # Check if symlink already points to the correct target
      local current_target
      current_target="$(readlink -f "$symlink_path" 2>/dev/null || echo "")"

      if [[ "$current_target" == "$binary_path" ]]; then
        # Symlink already correct, nothing to do
        return 0
      fi

      # Create or update symlink
      mkdir -p "$target_dir"
      ln -sf "$binary_path" "$symlink_path"
      if [[ -z "''${OPENCODE_NIX_QUIET:-}" ]]; then
        echo "[opencode-nix] Created symlink: $symlink_path -> $binary_path" >&2
      fi
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

    ${
      if isDarwin then
        ''
                # macOS: Install unwrapped binary and wrapper script
                cp opencode $out/bin/.opencode-unwrapped
                chmod +x $out/bin/.opencode-unwrapped

                # Install wrapper script with Home Manager detection
                cat > $out/bin/opencode << 'WRAPPER_EOF'
          ${wrapperScript}
          WRAPPER_EOF
                chmod +x $out/bin/opencode

                # Substitute @out@ placeholder
                substituteInPlace $out/bin/opencode --replace-quiet "@out@" "$out"
        ''
      else
        ''
          # Linux: Install binary directly (no wrapper needed)
          cp opencode $out/bin/opencode
          chmod +x $out/bin/opencode
        ''
    }

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
