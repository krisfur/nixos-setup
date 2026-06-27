{ pkgs, ... }:

# Development tooling, moved off `mise` onto Nix, installed system-wide.
# The old `cargo:fex` tool is dropped: Nix handles flakes/binaries natively.

{
  environment.systemPackages = with pkgs; [
    # GCC 16.1 for C++26 work (reflection / P2996 needs >= 16).
    gcc16
    # clangd / clang-format / clang-tidy for editor LSP. (The clang *compiler*
    # is not installed system-wide: it ships bin/cc + bin/c++ and would collide
    # with gcc16. Get it from a dev shell if you need an alternate toolchain.)
    clang-tools

    # C/C++ build stack (replaces the mise cmake/ninja entries).
    cmake
    ninja
    gnumake
    pkg-config
    gdb

    # Languages / runtimes.
    go
    nodejs_22
    nodePackages.pnpm
    rustc
    cargo
    clippy
    rustfmt
    rust-analyzer
    zig
    zls
    odin
    (python3.withPackages (ps: [ ps.pip ]))
    uv

    # Editor + CLI tooling (mirrors the mise list, minus fex).
    neovim
    tree-sitter
    ripgrep
    fd
    fzf
    typst
    gh
    git
    lazygit
    jq
    claude-code

    # Wayland clipboard for neovim (the nvim config expects wl-clipboard).
    wl-clipboard
  ];

  # Docker (the old sway setup enabled the daemon + added the user to docker).
  virtualisation.docker.enable = true;

  # uinput/input access for tooling that needs it.
  hardware.uinput.enable = true;
}
