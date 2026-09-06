# Repository guide

## Working approach

- Make persistent system and application changes declaratively in this repository. Do not fix issues by editing generated files in `/etc` or `~/.config`, installing packages imperatively, or changing live service or power state.
- Read-only diagnostics and builds are appropriate. Let the user run `nixos-rebuild switch`, service restarts, and other commands that change the running system unless they explicitly delegate those actions.
- Keep secrets, authentication state, and private network identifiers out of the repository and Nix store. Account login, Wi-Fi credentials, and fingerprint enrolment remain local state.
- Work in the current checkout. README installation examples use `/etc/nixos-setup`, but the working copy may be elsewhere; give rebuild commands pointing to the checkout actually edited.
- Preserve the reasoning in existing module comments. Recheck historical troubleshooting conclusions against current configuration and measurements before relying on them.

## Layout and setup

This flake defines `nixosConfigurations.nixos` for `x86_64-linux`, using nixos-unstable and Home Manager integrated into the NixOS rebuild. The configured user is `kfurman`. The desktop uses Sway, greetd, Waybar, Ghostty, and a Dust colour palette.

| Path | Responsibility |
| --- | --- |
| `flake.nix` | Inputs, NixOS/Home Manager composition, and Nix formatter. Neovim configuration comes from a separate flake input. |
| `hosts/nixos/configuration.nix` | Host imports, hostname, and system state version. |
| `hosts/nixos/hardware-configuration.nix` | Machine-specific hardware and filesystem configuration. |
| `modules/system/core.nix` | Boot, networking, power management, system services, and base system settings. |
| `modules/system/desktop.nix` | Desktop services, audio, graphics, and desktop integration. |
| `modules/system/dev.nix` | System-wide development tools, language servers, formatters, Docker, and nix-ld. |
| `modules/system/packages.nix` | Desktop applications and AppImage/Steam integration. |
| `modules/home/home.nix` | User packages, application wrappers, Home Manager files, activation scripts, shell, and appearance. |
| `config/` | Application configuration sources installed through Home Manager. Edit these sources rather than their installed symlinks. |
| `config/codex/instructions.md` | Global Codex instructions installed as `~/.codex/AGENTS.md`. This root `AGENTS.md` contains repository-specific guidance. |
| `README.md` | Installation, rebuild, update, and rollback instructions. |

## Configuration conventions

- Add packages to the existing module responsible for them. Prefer Nix-provided dependencies and explicit executable paths in service scripts and wrappers.
- Helium, Claude Code, and Codex use wrappers in `modules/home/home.nix` to keep their downloaded applications writable for updates. Preserve that behaviour unless the task is to change installation strategy.
- Codex's permission defaults are merged into its writable configuration during Home Manager activation. Preserve unrelated settings, project trust, and authentication state.
- Do not bump `system.stateVersion` or `home.stateVersion` as part of routine package updates. Do not update flake inputs incidentally; preserve `flake.lock` when present and flag its absence when reproducibility matters.
- Preserve speaker DSP behaviour when optimising resources. Its PipeWire filter-chain lives in `config/pipewire/thinkpad-unsuck.conf`, with LV2 dependencies supplied by `desktop.nix`.

## Validation and handoff

- Run `git diff --check` and parse changed Nix files with `nix-instantiate --parse <file>`. Match the existing formatting; avoid unrelated file-wide reformatting.
- Evaluate affected options when possible, using `nix eval .#nixosConfigurations.nixos.config.<option>`. For changes requiring full system validation, use `nix build .#nixosConfigurations.nixos.config.system.build.toplevel --no-link` without activating it.
- Flakes exclude untracked files in Git checkouts. Account for newly added configuration files before evaluating or building; do not misdiagnose an omitted file as a Nix module error.
- Distinguish syntax checks, evaluation, builds, and runtime verification in the handoff. Report checks that could not run and why; do not claim activation or runtime success from a build alone.
- Give the user the rebuild command for the edited checkout and identify any additional restart or reboot required by the change.
