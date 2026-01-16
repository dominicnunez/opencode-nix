# opencode-nix

Nix flake for [OpenCode](https://github.com/anomalyco/opencode) - an AI coding assistant in your terminal.

**Features:**
- Direct binary packaging from GitHub releases
- Smart Home Manager detection with automatic symlink management
- Pre-built binaries via Cachix for instant installation
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

## Cachix Setup

Use the public binary cache to skip building from source.

### Option 1: NixOS Configuration

```nix
{ config, pkgs, ... }:
{
  nix.settings = {
    substituters = [ "https://opencode.cachix.org" ];
    trusted-public-keys = [ "opencode.cachix.org-1:LdhuFTs/xrlYuchvsF+cOBCgCKEJIcesw9ef06GPlXU=" ];
  };
}
```

### Option 2: nix.conf

Add to `~/.config/nix/nix.conf`:
```
extra-substituters = https://opencode.cachix.org
extra-trusted-public-keys = opencode.cachix.org-1:LdhuFTs/xrlYuchvsF+cOBCgCKEJIcesw9ef06GPlXU=
```

### Option 3: Flake nixConfig

```nix
{
  nixConfig = {
    extra-substituters = [ "https://opencode.cachix.org" ];
    extra-trusted-public-keys = [ "opencode.cachix.org-1:LdhuFTs/xrlYuchvsF+cOBCgCKEJIcesw9ef06GPlXU=" ];
  };

  inputs.opencode-nix.url = "github:dominicnunez/opencode-nix";
  # ...
}
```

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
    inputs.opencode-nix.packages.${pkgs.system}.default
  ];
}
```

### Home Manager Configuration

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.opencode-nix.packages.${pkgs.system}.default
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
- **Home Manager detected:** Skips symlink creation, prints info message
- **Home Manager absent:** Creates `~/.local/bin/opencode` symlink for convenience

Symlink management uses state tracking - it only runs when the package version changes or Home Manager status changes, not on every launch.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENCODE_NIX_QUIET` | Set to `1` to suppress Home Manager detection messages |

Example:
```bash
export OPENCODE_NIX_QUIET=1
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
2. Creates a PR with title "chore: update opencode to {version}"
3. Enables auto-merge after CI passes

### Repository Settings for Auto-Updates

For the automated workflow to function, configure these GitHub settings:

**Settings > Actions > General > Workflow permissions:**
- Select "Read and write permissions"
- Check "Allow GitHub Actions to create and approve pull requests"

**Settings > General > Pull Requests:**
- Check "Allow auto-merge"

## License

This packaging is MIT-licensed. See `LICENSE`.

OpenCode is developed by [Anomaly](https://github.com/anomalyco).
