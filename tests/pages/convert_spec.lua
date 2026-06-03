--- Page conversion workflow tests.
---
--- Verifies flat-to-module page conversion across Rust files, SCSS partials,
--- page modules, style forwards, touched files, and formatting.

local h = require("tests.helpers")

local component = h.component
local page = h.page
local plugin = h.plugin
local fs = h.fs
local naming = h.naming
local path = h.path
local project = h.project
local rust = h.rust
local scss = h.scss
local touch = h.touch

local temp_root = h.temp_root
local mkdir = h.mkdir
local write_file = h.write_file
local create_default_layout = h.create_default_layout
local reset = h.reset
local assert_equals = h.assert_equals
local assert_match = h.assert_match
local assert_list_equals = h.assert_list_equals
local test = h.test
local with_stubbed_format = h.with_stubbed_format

--- Verifies flat-to-module page conversion.
---
--- # Example Under Test
---
--- A flat page and component-name SCSS partial are converted to module layout.
---
--- # Assertions
---
--- - The Rust page moves to `page.rs` and gains a re-exporting page `mod.rs`.
--- - The SCSS partial moves to `_page.scss` with a module style index.
--- - The parent style index replaces the flat partial forward with the module forward.
--- - Touched files are formatted in first-seen order.
---
test("page workflow converts flat page to module layout", function()
    with_stubbed_format(function(formatted)
        local root = path.join(temp_root, "page-convert-module-layout")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
        }

        local flat_rust_path = path.join(paths.pages_dir, "admin.rs")
        local flat_scss_path = path.join(paths.page_styles_dir, "_admin-page.scss")
        local module_rust_path = path.join(paths.pages_dir, "admin", "page.rs")
        local module_scss_path = path.join(paths.page_styles_dir, "admin", "_page.scss")
        local page_mod = path.join(paths.pages_dir, "admin", "mod.rs")
        local root_index = path.join(paths.page_styles_dir, "index.scss")
        local module_index = path.join(paths.page_styles_dir, "admin", "index.scss")

        write_file(flat_rust_path, {
            "use leptos::prelude::*;",
            "",
            "#[component]",
            "pub fn AdminPage() -> impl IntoView {",
            "    view! { <div /> }",
            "}",
        })
        write_file(flat_scss_path, {
            ".admin-page {",
            "}",
        })
        write_file(root_index, {
            '@forward "admin-page";',
        })

        local pages = page.collect(paths)
        local result = assert(page.convert_to_module_layout({
            page = pages[1],
            paths = paths,
            format_opts = { timeout_ms = 50 },
        }))

        assert_equals(result.converted, true, "conversion result should record that a flat page was converted")
        assert_equals(result.rust_path, module_rust_path, "conversion result should include module page path")
        assert_equals(result.scss_path, module_scss_path, "conversion result should include module style path")
        assert_equals(fs.exists(flat_rust_path), false, "flat Rust page should be moved away")
        assert_equals(fs.exists(flat_scss_path), false, "flat SCSS partial should be moved away")
        assert_list_equals(fs.read_lines(module_rust_path), {
            "use leptos::prelude::*;",
            "",
            "#[component]",
            "pub fn AdminPage() -> impl IntoView {",
            "    view! { <div /> }",
            "}",
        }, "converted page Rust should preserve original content")
        assert_list_equals(fs.read_lines(module_scss_path), {
            ".admin-page {",
            "}",
        }, "converted page SCSS should preserve original content")
        assert_list_equals(fs.read_lines(page_mod), {
            "pub mod page;",
            "",
            "pub use page::AdminPage;",
        }, "converted page mod should declare and re-export page.rs")
        assert_list_equals(fs.read_lines(root_index), {
            '@forward "admin";',
        }, "parent index should forward the module directory")
        assert_list_equals(fs.read_lines(module_index), {
            '@forward "page";',
        }, "module style index should forward the page partial")
        assert_list_equals(result.touched_paths, {
            module_rust_path,
            page_mod,
            module_scss_path,
            module_index,
            root_index,
        }, "conversion should return touched files in mutation order")
        assert_list_equals(formatted, {
            module_rust_path .. ":50",
            page_mod .. ":50",
            module_scss_path .. ":50",
            module_index .. ":50",
            root_index .. ":50",
        }, "conversion should format touched Rust and SCSS files")
    end)
end)
