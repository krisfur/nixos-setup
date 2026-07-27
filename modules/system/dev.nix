{ pkgs, ... }:

# Development tooling, installed system-wide.

{
  environment.systemPackages = with pkgs; [
    # GCC 16.1 for C++26 work (reflection / P2996 needs >= 16).
    gcc16
    # clangd / clang-format / clang-tidy for editor LSP. The clang *compiler*
    # is omitted: it ships bin/cc + bin/c++ and would collide with gcc16. Use
    # a dev shell if you need an alternate toolchain.
    clang-tools

    # C/C++ build stack.
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

    # Editor + CLI tooling.
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
    # claude-code is deliberately not from nixpkgs — see the wrapper in
    # modules/home/home.nix for why.

    # Neovim language servers + formatters. The nvim config doesn't use Mason,
    # so every server and conform formatter must be on PATH (it shells out by
    # command name). clangd comes from clang-tools, rust-analyzer/zls above.
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

    # Neovim plugins that build native bits on first run (telescope-fzf-native,
    # treesitter parsers, markdown-preview) are covered by gnumake/gcc16/nodejs
    # above; unzip is a generally-useful extractor.
    unzip
  ];

  # Escape hatch for dynamically-linked foreign binaries (no /lib64/ld-linux-*
  # on NixOS). Unused by the Nix-provided LSPs; needed by ad-hoc prebuilt tools.
  programs.nix-ld.enable = true;

  # Socket-activated: the daemon starts on first docker command rather than
  # sitting in RAM from boot (~90 MiB idle).
  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = false;

  # uinput/input access for tooling that needs it.
  hardware.uinput.enable = true;
}
