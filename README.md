# goggin-rs.nvim

Neovim plugin project for extracting Rust and Leptos workflow tooling from Joe
Goggin's Neovim config.

Source context:
https://github.com/joegoggin/goggin-nvim-v2

## Overview

`goggin-rs.nvim` provides Lua helpers for Rust/Leptos project automation. The
current modules focus on project layout discovery, generated file naming,
Rust `mod.rs` and route mutation, SCSS `@forward` maintenance, empty directory
pruning, touched-file formatting, Neovim commands, and Telescope picker
exports.

The plugin exposes setup/configuration helpers from `require("goggin-rs")`.
The lower-level modules are also documented with LuaLS annotations so workflows
can compose them directly.

## Configuration

Call `setup` to override project paths. Relative paths resolve against the
detected web root.

```lua
require("goggin-rs").setup({
    paths = {
        components_dir = "src/components",
        styles_components_dir = "styles/components",
        pages_dir = "src/pages",
        page_styles_dir = "styles/pages",
        app_path = "src/app.rs",
    },
})
```

Project resolution checks both supported layouts:

- `./web/...` from a repository root.
- `./...` from a web root.

## Telescope Extension

Telescope picker workflows require
[`nvim-telescope/telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim).
Load the extension after Telescope is available:

```lua
require("telescope").load_extension("goggin-rs")
```

Exported picker functions map to the same workflow entrypoints as the
`:GogginRs*` commands:

```lua
local goggin_rs = require("telescope").extensions["goggin-rs"]

goggin_rs.pick_component()
goggin_rs.generate_component()
goggin_rs.pick_page()
goggin_rs.generate_page()
goggin_rs.add_style()
goggin_rs.delete_style()
goggin_rs.pick_colors()
```

The same exports are also available through Telescope commands, for example:

```vim
:Telescope goggin-rs pick_component
:Telescope goggin-rs pick_colors
```

## Modules

- `goggin-rs.config` stores default and active configuration.
- `goggin-rs.project` resolves configured web project paths from the current
  Neovim context.
- `goggin-rs.naming` converts user input into Rust, file, style, and route
  naming conventions.
- `goggin-rs.infra` modules provide filesystem, path, line-list, formatting,
  and Telescope-loading helpers.
- `goggin-rs.rust` updates Rust module declarations, exports, Leptos routes,
  and empty module directories.
- `goggin-rs.scss` updates SCSS `@forward` indexes, style directory chains,
  and color variable discovery/parsing.
- `goggin-rs.components` collects component/style pairs and generates new
  component Rust/SCSS files.
- `goggin-rs.pages` collects page/style pairs and generates new flat or
  module-layout page Rust/SCSS files with app route insertion.
- `goggin-rs.styles` collects missing or existing style targets and provides
  add/delete workflows for component, page, and page-local component styles.

Most package directories also contain focused implementation modules. Prefer
the package `init.lua` modules above unless a workflow needs a narrower helper.

## Tests

Run the headless fixture suite with:

```sh
nvim --headless -u NONE -l tests/run.lua
```

Run Lua formatting checks with:

```sh
stylua --check lua tests
```
