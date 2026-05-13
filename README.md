# opencode-nix

Nix flake for [OpenCode](https://github.com/anomalyco/opencode) - an AI coding assistant in your terminal.

**Features:**
- Direct binary packaging from GitHub releases
- Smart Home Manager detection with automatic symlink management
- Pre-built binaries via Garnix for instant installation
- Hourly automated updates for new OpenCode versions
- Linux and macOS support (x86_64 and aarch64)

## Quick Start

**Try without installing:**
```bash
nix run github:dominicnunez/opencode-nix
```

**Install to your profile:**
```bash
nix profile add github:dominicnunez/opencode-nix
```

## Binary Cache

This flake uses [Garnix](https://garnix.io) for CI and binary caching. The `nixConfig` in `flake.nix` automatically configures the cache, so pre-built binaries are fetched without any manual setup.

If prompted to allow configuration from the flake, answer yes or add `accept-flake-config = true` to your Nix configuration.

## Flake Usage

### As a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    opencode-nix.url = "github:dominicnunez/opencode-nix";
  };

  outputs = { self, nixpkgs, opencode-nix, ... }: {
    # Your configuration here
  };
}
```

### NixOS Configuration

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.opencode-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
```

### Home Manager Configuration

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.opencode-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
```

### Using the Overlay

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    opencode-nix.url = "github:dominicnunez/opencode-nix";
  };

  outputs = { self, nixpkgs, opencode-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ opencode-nix.overlays.default ];
      };
    in {
      # pkgs.opencode is now available
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.opencode ];
      };
    };
}
```

## Home Manager Integration

This package includes smart Home Manager detection. When Home Manager is detected, the package skips creating symlinks to respect your declarative configuration.

**Detection methods:**
- `HM_SESSION_VARS` environment variable is set
- `~/.config/home-manager` directory exists
- `/etc/profiles/per-user/$USER` directory exists

**Behavior:**
- **Home Manager detected:** Skips symlink creation and cleans up any orphaned symlinks
- **Home Manager absent:** Creates `~/.local/bin/opencode` symlink for convenience

**Automatic cleanup:** If you previously installed opencode standalone (creating a `~/.local/bin/opencode` symlink) and later enable Home Manager, the package will automatically remove the orphaned symlink on first run to prevent PATH conflicts.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENCODE_NIX_VERBOSE` | Set to `1` to enable Home Manager detection and symlink management messages |

Example:
```bash
export OPENCODE_NIX_VERBOSE=1
```

## Updating

**If using `nix profile add`:**
```bash
nix profile upgrade '.*opencode.*'
```

**If using as a flake input:**
```bash
nix flake update opencode-nix
nixos-rebuild switch  # or home-manager switch
```

## Contributing

### Development Setup

```bash
git clone https://github.com/dominicnunez/opencode-nix
cd opencode-nix
nix develop  # enters shell with dev tools
nix build
./result/bin/opencode --version
```

### Update Workflow

The `update.sh` script checks for new OpenCode releases and updates `version.json`:

```bash
# Enter dev shell (provides required tools)
nix develop

# Check for updates (dry run)
./update.sh

# Update to latest version
./update.sh --update
```

The script:
1. Queries GitHub API for the latest non-prerelease release
2. Compares against current version in `version.json`
3. With `--update`: fetches SRI hashes for all platforms and updates `version.json`

### Automated Updates

A GitHub Actions workflow runs hourly to check for new releases. When a new version is found, it automatically:
1. Updates `version.json` with new version and hashes
2. Validates with `nix flake check`
3. Pushes directly to main

## License

This packaging is MIT-licensed. See `LICENSE`.

OpenCode is developed by [Anomaly](https://github.com/anomalyco).
