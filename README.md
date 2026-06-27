# nixos-setup

Declarative NixOS config: labwc (stacking Wayland WM), Nord theme, Waybar,
greetd login, and a Nix-managed dev toolchain (latest GCC for C++26, latest
kernel). Neovim config is pinned as a flake input, shared across machines.

## Install (from the minimal NixOS installer)

Boot the minimal ISO. You start as user `nixos` (no password); prefix commands
with `sudo` or run `sudo -i` for a root shell.

1. **Get online.** Wired DHCP connects automatically - test with `ping nixos.org`.
   For wifi, the installer ships NetworkManager (this is the way the NixOS
   manual recommends):

   ```bash
   nmcli device wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
   ```

   Then verify with `ping -c2 nixos.org`.

2. **Partition + format** the target disk (UEFI/GPT). Replace `/dev/sdX` with
   your disk (`lsblk` to find it). The LABELs `boot`/`nixos` are what the
   placeholder hardware config expects:

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

5. **Generate this machine's hardware config** and stage it. Flakes only see
   git-tracked files, so it must be `git add`ed (staging is enough - no commit
   needed) or `nixos-install` won't pick it up. This is the one per-machine
   file; everything else is shared:

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

After reboot, log in as `kfurman` with password `changeme` and immediately
change it:

```bash
passwd
```

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

(Prefer keeping the repo in your home, e.g. `~/nixos-setup`, to avoid the
`sudo git` dance - only the `nixos-rebuild`/`nixos-install` step needs root.)

## C++26

GCC 16.1 is system-wide, so `c++ -std=c++26` (incl. P2996 reflection) works
anywhere with no per-project setup.

## What maps to what

- Desktop: `labwc` replaces Sway (non-tiling). Keybinds in
  `config/labwc/rc.xml` mirror the old Sway binds; tiling-only ones
  (scratchpad, pixel resize) became edge-snapping / window cycling.
- Bar/launcher/notifications: Waybar + fuzzel + swaync, Nord-themed.
  Waybar uses `wlr/taskbar` instead of `sway/workspaces` (no sway IPC).
  Network is the NetworkManager applet/editor (no nmtui).
- Browser: Helium, as its auto-updating AppImage. First run of `helium`
  (e.g. Super+B) downloads the latest release into `~/Applications` and it
  self-updates after that. `programs.appimage.binfmt` runs it.
- Dev tooling: moved from `mise` to Nix (`modules/system/dev.nix`).
  GCC 16.1 system-wide for `-std=c++26` (P2996 reflection).
  `fex` is dropped; Nix handles binaries/flakes natively.
- Neovim: pinned flake input `neovim-config` (`github.com/krisfur/neovim-config`).

## Layout

```
flake.nix                      inputs, nixosConfiguration
hosts/nixos/                   host config + (placeholder) hardware-configuration.nix
modules/system/                core, desktop, dev, packages
modules/home/home.nix          home-manager: theming, git, vendored dotfiles
config/                        vendored dotfiles (labwc, waybar, fuzzel, fastfetch, ...)
                               (neovim config comes from the neovim-config flake input)
```
