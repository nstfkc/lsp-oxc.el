# lsp-oxc

An Emacs package providing LSP integration for [Oxc](https://oxc.rs) tools - [Oxlint](https://oxc.rs/docs/guide/usage/linter) (linter) and [Oxfmt](https://oxc.rs/docs/guide/usage/formatter) (formatter), fast JavaScript/TypeScript tools written in Rust.

## Features

- Real-time linting diagnostics via LSP (Oxlint)
- Code formatting via LSP (Oxfmt)
- Code actions for automatic fixes
- Auto-fix on save support (Oxlint)
- Format on save support (Oxfmt)
- Monorepo support (searches upward for config and binary)
- Runs as an add-on alongside other LSP servers (e.g., typescript-language-server)
- No external Emacs package dependencies beyond lsp-mode

## Requirements

- Emacs 27.1+
- [lsp-mode](https://github.com/emacs-lsp/lsp-mode) 8.0.0+
- oxlint and/or oxfmt installed in your project
- Configuration files in your project (`.oxlintrc.json` and/or `.oxfmtrc.json`)

## Installation

### Doom Emacs

1. Add to `~/.doom.d/packages.el`:
   ```elisp
   (package! lsp-oxc
     :recipe (:host github :repo "nstfkc/lsp-oxc.el"))
   ```

2. Run `doom sync` and restart Emacs

The package auto-enables when lsp-mode loads. To configure, add to `~/.doom.d/config.el`:
```elisp
(setq lsp-oxlint-autofix-on-save t)  ; optional
(setq lsp-oxfmt-format-on-save t)    ; optional
```

### straight.el + use-package

```elisp
(use-package lsp-oxc
  :straight (lsp-oxc :type git
                     :host github
                     :repo "nstfkc/lsp-oxc.el")
  :after lsp-mode)
```

## Project Setup

1. Install the tools in your project:
   ```bash
   npm install -D oxlint oxfmt
   ```

2. Create configuration files in your project root:

   `.oxlintrc.json`:
   ```json
   {
     "$schema": "./node_modules/oxlint/configuration_schema.json",
     "rules": {}
   }
   ```

   `.oxfmtrc.json`:
   ```json
   {
     "$schema": "./node_modules/oxfmt/configuration_schema.json"
   }
   ```

3. Open a supported file and run `M-x lsp`

## Configuration

### Auto-fix on save (Oxlint)

```elisp
(setq lsp-oxlint-autofix-on-save t)
```

### Format on save (Oxfmt)

```elisp
(setq lsp-oxfmt-format-on-save t)
```

### Custom config file names

```elisp
(setq lsp-oxlint-config-file "oxlint.json")
(setq lsp-oxfmt-config-file "oxfmt.json")
```

### Supported file types

By default, lsp-oxc activates for: `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs`, `.mts`, `.cts`, `.md`, `.mdx`

To customize:
```elisp
(setq lsp-oxc-active-file-types '("\\.js\\'" "\\.ts\\'"))
```

## Commands

| Command                    | Description                              |
|----------------------------|------------------------------------------|
| `M-x lsp-oxlint-fix`       | Apply fixable issues in current buffer   |
| `M-x lsp-oxfmt-format`     | Format current buffer                    |
| `M-x lsp-oxc-verify-setup` | Debug activation issues                  |

## Troubleshooting

Run `M-x lsp-oxc-verify-setup` to diagnose issues. Common problems:

- **oxlint not found**: Run `npm install -D oxlint` in your project
- **oxfmt not found**: Run `npm install -D oxfmt` in your project
- **Config not found**: Create `.oxlintrc.json` or `.oxfmtrc.json` in your project root
- **Wrong file type**: Ensure you're in a supported file (JS/TS/MD/MDX)

## License

MIT
