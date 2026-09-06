# nixos-setup

Declarative NixOS config: sway (tiling Wayland WM), Nord theme, Waybar, greetd login, and a Nix-managed dev toolchain (latest GCC for C++26, latest kernel). 

Neovim config is pinned as a flake input, shared with non-nix machines machines.

Edit Codex's global instructions in [config/codex/instructions.md](config/codex/instructions.md). Home Manager installs this as `~/.codex/AGENTS.md`; rebuild and start a new Codex session to apply changes.

![screenshot](./screenshot.png)

## Install (from the minimal NixOS installer)

Boot the minimal ISO. You start as user `nixos` (no password); prefix commands with `sudo` or run `sudo -i` for a root shell.

1. **Get online.** Wired DHCP connects automatically - test with `ping nixos.org`. 

   For wifi, the installer ships NetworkManager (this is the way the NixOS manual recommends):

   ```bash
   nmcli device wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
   ```

   Then verify with `ping -c2 nixos.org`.

2. **Partition + format** the target disk (UEFI/GPT). 

   Replace `/dev/sdX` with your disk (`lsblk` to find it). The LABELs `boot`/`nixos` are what the placeholder hardware config expects:

   ```bash
   sudo -i
   lsblk                       # identify the target disk first

   # Wipe any existing partition table + filesystem signatures
   wipefs -a /dev/sdX
   sgdisk --zap-all /dev/sdX

   # GPT: 512MiB EFI system partition + rest for root
   parted /dev/sdX -- mklabel gpt
   parted /dev/sdX -- mkpart ESP fat32 1MiB 512MiB
   parted /dev/sdX -- set 1 esp on
   parted /dev/sdX -- mkpart primary 512MiB 100%

   # NOTE: NVMe names partitions p1/p2 (e.g. /dev/nvme0n1p1); SATA uses 1/2.
   mkfs.fat -F 32 -n boot /dev/sdX1
   mkfs.ext4 -L nixos /dev/sdX2
   ```

3. **Mount** (`umask=077` keeps the ESP root-only, per the NixOS manual):

   ```bash
   mount /dev/disk/by-label/nixos /mnt
   mkdir -p /mnt/boot
   mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
   ```

4. **Clone this repo** (git is on the ISO):

   ```bash
   git clone https://github.com/krisfur/nixos-setup /mnt/etc/nixos-setup
   cd /mnt/etc/nixos-setup
   ```

5. **Generate this machine's hardware config** and stage it. 

   Flakes only see git-tracked files, so it must be `git add`ed (staging is enough - no commit needed) or `nixos-install` won't pick it up. 

   This is the one per-machine file; everything else is shared:

   ```bash
   nixos-generate-config --root /mnt --show-hardware-config \
     > hosts/nixos/hardware-configuration.nix
   git add hosts/nixos/hardware-configuration.nix
   ```

6. **Install:**

   ```bash
   nixos-install --flake '/mnt/etc/nixos-setup#nixos'
   reboot
   ```

After reboot, log in as `kfurman` with password `changeme` and immediately change it:

```bash
passwd
```

### Fingerprint reader (optional, hardware permitting)

On machines with a reader supported by [libfprint](https://fprint.freedesktop.org/supported-devices.html), enrol a finger:

```bash
fprintd-enroll        # touch the sensor repeatedly until it completes
fprintd-verify        # confirm it reads back
```

Check yours is on that list first — `lsusb` shows the vendor:product ID (Synaptics readers are vendor `06cb`). On machines without a reader, skip this: `fprintd-enroll` just reports no devices and nothing else is affected.

This covers `sudo` and the lock screen. On the lock screen just touch the sensor — hyprlock waits on the fingerprint and the password at the same time, so either unlocks, whichever you do first.

Console login and the greeter are deliberately left password-only — fprintd isn't reliably running that early in boot, and a greeter hanging on the sensor is a bad way to lose access.

The lock screen is **hyprlock**, not swaylock, specifically for this. swaylock collects the password *before* running the PAM stack, so it can only check one method at a time: with `pam_fprintd` stacked first it blocks on the sensor before reading what you typed, and stacked last it's never reached unless you deliberately fail a password. hyprlock talks to fprintd over D-Bus directly, which is why `security.pam.services.hyprlock.fprintAuth` is *off* — leaving `pam_fprintd` in its stack as well makes both paths fight over the sensor.

Enrolment is per-user and stored outside the store in `/var/lib/fprint`, so it's one of the few steps that can't be declarative — repeat it on each machine.

## Apply changes later

The repo lives in root-owned `/etc`, so git runs need `sudo`:

```bash
sudo git -C /etc/nixos-setup pull
sudo nixos-rebuild switch --flake '/etc/nixos-setup#nixos'
```

To pull a newer neovim config (the pinned flake input):

```bash
sudo nix flake update neovim-config --flake /etc/nixos-setup
sudo nixos-rebuild switch --flake '/etc/nixos-setup#nixos'
```

## Update everything (like `dnf upgrade` / `pacman -Syu`)

Package versions are pinned by `flake.lock`. 

Updating = bumping the lock to the latest `nixos-unstable` (and other inputs), then rebuilding:

```bash
sudo nix flake update --flake /etc/nixos-setup     # bump flake.lock
sudo nixos-rebuild switch --flake '/etc/nixos-setup#nixos'
```

Commit the changed `flake.lock` afterward so the new versions are pinned/shared. 

Codex and Helium use writable downloads managed by wrappers in `modules/home/home.nix`, so their application versions are separate from `flake.lock`. Codex installs on first launch into `~/.local/bin`; use `codex update` to update it. Its instructions and permission defaults are managed through Home Manager.

To reclaim disk from old generations:

```bash
sudo nix-collect-garbage --delete-older-than 14d
```

To roll back a bad update, pick a previous generation in the boot menu, or:

```bash
sudo nixos-rebuild switch --rollback
```

## Add a package

System packages live in `modules/system/packages.nix` (desktop apps) or `modules/system/dev.nix` (dev tooling). 

Add the attribute name to the relevant list and rebuild. E.g. to add the Helix editor, in `packages.nix`:

```nix
  environment.systemPackages = with pkgs; [
    ghostty
    helix          # <- added
    ...
  ];
```

then:

```bash
sudo nixos-rebuild switch --flake '/etc/nixos-setup#nixos'
```

## Find package names

Search by name or description with `nix search`, or browse [NixOS package search](https://search.nixos.org/packages) with the unstable channel selected:

```bash
nix search nixpkgs helix
nix search nixpkgs 'raylib'
```

A result such as `legacyPackages.x86_64-linux.helix` means the attribute is `helix`: use `nixpkgs#helix` in `nix shell`, or `helix` in a `with pkgs; [ ... ]` package list. Keep any nested attribute path, such as `python3Packages.requests`. Package attributes and executable names can differ: the `helix` package provides `hx`.

## Temporary tools with nix shell

Use `nix shell` to try tools without adding them to the system configuration. No rebuild or sudo is needed:

```bash
nix shell nixpkgs#helix nixpkgs#jq --command fish
hx
exit
```

This starts Fish with the selected tools on PATH; `exit` returns to the original shell. Downloads remain cached in the Nix store until garbage collection, but nothing is added to your persistent package list. This is a temporary environment, not a security sandbox.

For a single command:

```bash
nix shell nixpkgs#helix --command hx README.md
```

`nixpkgs` here resolves through the Nix flake registry and can differ from this repository's input. To use this repository's locked input, run from its root with an existing `flake.lock`:

```bash
nix shell --inputs-from . nixpkgs#helix --command fish
```

## Project dependencies with nix-shell

`nix shell` makes executables available. For a project's compiler, libraries, and build environment, use a `shell.nix` with `nix-shell`, or `nix develop` when the project provides a flake dev shell.

For example, create `shell.nix` in the project root:

```nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [ odin pkg-config ];
  buildInputs = with pkgs; [ raylib ];
}
```

Enter it with `nix-shell` and leave with `exit`. It starts a Bash subshell, not a file to source into your existing shell. The `<nixpkgs>` lookup uses your configured Nix search path, not this repository's flake lock; use a pinned project flake when reproducible dependency versions matter.

See the official [nix shell reference](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-shell) and [nix search reference](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-search).

## C++26

GCC 16.1 is system-wide, so `c++ -std=c++26` (incl. P2996 reflection) works anywhere with no per-project setup.

## Layout

```
flake.nix                      inputs, nixosConfiguration
hosts/nixos/                   host config + (placeholder) hardware-configuration.nix
modules/system/                core, desktop, dev, packages
modules/home/home.nix          home-manager: theming, git, vendored dotfiles
config/                        vendored dotfiles (sway, waybar, fuzzel, fastfetch, ...)
                               (neovim config comes from the neovim-config flake input)
```
