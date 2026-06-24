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

## Installation

Install the plugin with `lazy.nvim` and load the Telescope extension after
Telescope is available:

```lua
{
    "joegoggin/goggin-rs.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope.nvim",
    },
    config = function()
        require("goggin-rs").setup({
            paths = {
                components_dir = "src/components",
                styles_components_dir = "styles/components",
                pages_dir = "src/pages",
                page_styles_dir = "styles/pages",
                app_path = "src/app.rs",
            },
        })

        require("telescope").load_extension("goggin-rs")
    end,
}
```

Telescope is required for picker workflows and for the `goggin-rs` Telescope
extension. Plenary is included because Telescope depends on it. Non-picker
modules can still be required directly, but the public user workflows are
designed around Telescope, `vim.ui.input`, and `vim.ui.select`.

## Configuration

Call `setup` to override command registration or project paths. Relative paths
resolve against the detected web root.

```lua
require("goggin-rs").setup({
    commands = {
        enabled = true,
    },
    paths = {
        components_dir = "src/components",
        styles_components_dir = "styles/components",
        pages_dir = "src/pages",
        page_styles_dir = "styles/pages",
        app_path = "src/app.rs",
    },
})
```

Available options:

| Option | Default | Description |
| --- | --- | --- |
| `commands.enabled` | `true` | Registers the public `:GogginRs*` commands when enabled. |
| `paths.components_dir` | `src/components` | Rust component root. |
| `paths.styles_components_dir` | `styles/components` | SCSS partial root for component styles. |
| `paths.pages_dir` | `src/pages` | Rust page root. |
| `paths.page_styles_dir` | `styles/pages` | SCSS partial root for page styles. |
| `paths.app_path` | `src/app.rs` | Leptos app file updated by page route generation. |

Project resolution checks both supported layouts:

- `./web/...` from a repository root.
- `./...` from a web root.

The default layout expects these paths under the resolved web root:

```text
src/components/
src/pages/
styles/components/
styles/pages/
src/app.rs
```

## Commands

`setup()` registers these commands by default:

| Command | Workflow |
| --- | --- |
| `:GogginRsPickComponent` | Pick an existing Rust component and open its paired SCSS style when present. |
| `:GogginRsGenerateComponent` | Generate a component Rust file, paired SCSS partial, Rust module exports, and SCSS forwards. |
| `:GogginRsPickPage` | Pick an existing page, then open the page or one of its page-local components. |
| `:GogginRsGeneratePage` | Generate a flat or module-layout page, or create a page-local component. |
| `:GogginRsAddStyle` | Pick a component or page missing a style and create the matching SCSS partial. |
| `:GogginRsDeleteStyle` | Pick a component or page with an existing style and delete that SCSS partial. |
| `:GogginRsPickColors` | Pick an SCSS color variable from `_colors.scss` files and copy its variable name. |

Command-based keymaps do not need direct module requires:

```lua
local keymap = vim.keymap.set

keymap("n", "<leader>oc", "<cmd>GogginRsPickComponent<cr>", { desc = "Open Component + Style" })
keymap("n", "<leader>op", "<cmd>GogginRsPickPage<cr>", { desc = "Open Page + Components" })
keymap("n", "<leader>nc", "<cmd>GogginRsGenerateComponent<cr>", { desc = "New Component" })
keymap("n", "<leader>np", "<cmd>GogginRsGeneratePage<cr>", { desc = "New Page" })
keymap("n", "<leader>ns", "<cmd>GogginRsAddStyle<cr>", { desc = "New Style" })
keymap("n", "<leader>ds", "<cmd>GogginRsDeleteStyle<cr>", { desc = "Delete Style" })
keymap("n", "<leader>fvc", "<cmd>GogginRsPickColors<cr>", { desc = "Find SCSS Colors" })
```

## Telescope Extension

Load the extension after Telescope is available:

```lua
require("telescope").load_extension("goggin-rs")
```

The extension exposes the same workflow entrypoints as the public commands:

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

The same exports are available through Telescope commands:

```vim
:Telescope goggin-rs pick_component
:Telescope goggin-rs generate_component
:Telescope goggin-rs pick_page
:Telescope goggin-rs generate_page
:Telescope goggin-rs add_style
:Telescope goggin-rs delete_style
:Telescope goggin-rs pick_colors
```

You can also bind the extension exports directly after loading the extension:

```lua
local keymap = vim.keymap.set
local goggin_rs = require("telescope").extensions["goggin-rs"]

keymap("n", "<leader>oc", goggin_rs.pick_component, { desc = "Open Component + Style" })
keymap("n", "<leader>op", goggin_rs.pick_page, { desc = "Open Page + Components" })
keymap("n", "<leader>nc", goggin_rs.generate_component, { desc = "New Component" })
keymap("n", "<leader>np", goggin_rs.generate_page, { desc = "New Page" })
keymap("n", "<leader>ns", goggin_rs.add_style, { desc = "New Style" })
keymap("n", "<leader>ds", goggin_rs.delete_style, { desc = "Delete Style" })
keymap("n", "<leader>fvc", goggin_rs.pick_colors, { desc = "Find SCSS Colors" })
```

## Migration From `goggin-nvim-v2`

The source config wired these workflows directly from
`lua/goggin/plugins/telescope.lua` with `require("goggin.telescope.*")`. Replace
those direct requires with either `:GogginRs*` commands or the loaded Telescope
extension exports.

| Source config require | Plugin replacement |
| --- | --- |
| `require("goggin.telescope.component_pair_picker").pick()` | `:GogginRsPickComponent` or `goggin_rs.pick_component()` |
| `require("goggin.telescope.component_generator").generate()` | `:GogginRsGenerateComponent` or `goggin_rs.generate_component()` |
| `require("goggin.telescope.page_component_picker").pick_page()` | `:GogginRsPickPage` or `goggin_rs.pick_page()` |
| `require("goggin.telescope.page_generator").generate()` | `:GogginRsGeneratePage` or `goggin_rs.generate_page()` |
| `require("goggin.telescope.missing_style_adder").pick()` | `:GogginRsAddStyle` or `goggin_rs.add_style()` |
| `require("goggin.telescope.missing_style_adder").pick_delete()` | `:GogginRsDeleteStyle` or `goggin_rs.delete_style()` |
| `require("goggin.telescope.color_picker").pick()` | `:GogginRsPickColors` or `goggin_rs.pick_colors()` |

The legacy `component_deleter`, `page_deleter`, and related delete utilities
from the source config are not exposed by this plugin. Use the style delete
workflow for SCSS partial cleanup; component and page deletion are outside the
current public surface.

The old `goggin.telescope.web_paths` defaults map to the current `paths`
configuration. Keep the defaults for a web root with `src/components`,
`src/pages`, `styles/components`, `styles/pages`, and `src/app.rs`, or override
the relevant keys in `setup()`.

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
