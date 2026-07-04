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
    pnpm
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
    cloc
    claude-code

    # Neovim language servers + formatters. The nvim config no longer uses
    # Mason: every server in its `servers` table and every conform formatter
    # must be on PATH (it shells out by command name). clangd comes from
    # clang-tools, rust-analyzer/zls are above; the rest are here.
    gopls                          # go
    lua-language-server            # lua  (lua_ls)
    ols                            # odin
    ty                             # python types (ty server)
    ruff                           # python lint/format (ruff server + ruff_format)
    tinymist                       # typst
    vscode-langservers-extracted   # eslint (vscode-eslint-language-server)
    typescript-language-server     # ts/js (ts_ls)
    typescript                     # tsserver backing ts_ls
    stylua                         # lua format
    prettier                       # js/ts/json format
    # (swiftformat / sourcekit-lsp are macOS-only and not enabled on Linux.)

    # Wayland clipboard for neovim (the nvim config expects wl-clipboard).
    wl-clipboard

    # Some neovim plugins build native bits on first run: telescope-fzf-native
    # (make), treesitter parsers (cc), markdown-preview (npm). gnumake/gcc16/
    # nodejs above cover those; unzip is kept as a generally-useful extractor.
    unzip
  ];

  # Escape hatch for running dynamically-linked foreign binaries (no
  # /lib64/ld-linux-*.so on NixOS). Not needed by the Nix-provided LSPs, but
  # handy for ad-hoc prebuilt tools (e.g. pip wheels shipping binaries).
  programs.nix-ld.enable = true;

  # Docker (the old sway setup enabled the daemon + added the user to docker).
  virtualisation.docker.enable = true;

  # uinput/input access for tooling that needs it.
  hardware.uinput.enable = true;
}
