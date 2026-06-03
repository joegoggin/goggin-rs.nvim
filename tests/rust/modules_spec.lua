--- Rust module mutation tests.
---
--- Verifies Rust `mod.rs` declaration insertion, export insertion, layout
--- normalization, and attributed or inline module preservation.

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

--- Verifies Rust module declarations and exports are inserted and normalized.
---
--- # Example Under Test
---
--- A `mod.rs` fixture starts with a public export, other content, and an
--- existing public module declaration.
---
--- # Assertions
---
--- - A new public module declaration is inserted.
--- - Existing module declarations are not duplicated.
--- - Private declarations are inserted and treated as existing for public insertion.
--- - Public exports are inserted once.
--- - Final module layout groups modules, exports, and other content.
---
test("rust helpers update module declarations and exports", function()
    local root = path.join(temp_root, "rust-mod")
    local mod_path = path.join(root, "src", "pages", "mod.rs")
    write_file(mod_path, {
        "pub use account::AccountPage;",
        "",
        "const VALUE: usize = 1;",
        "pub mod existing;",
    })

    assert_equals(rust.ensure_mod_declaration(mod_path, "new_page"), true, "public module should be inserted")
    assert_equals(
        rust.ensure_mod_declaration(mod_path, "existing"),
        false,
        "existing public module should not duplicate"
    )
    assert_equals(
        rust.ensure_mod_declaration(mod_path, "private_page", { private = true }),
        true,
        "private module should be inserted"
    )
    assert_equals(
        rust.ensure_mod_declaration(mod_path, "private_page"),
        false,
        "opposite visibility module should not duplicate"
    )
    assert_equals(
        rust.ensure_use_declaration(mod_path, "new_page::NewPage"),
        true,
        "use declaration should be inserted"
    )
    assert_equals(
        rust.ensure_use_declaration(mod_path, "new_page::NewPage"),
        false,
        "existing use declaration should not duplicate"
    )
    assert_equals(rust.normalize_mod_layout(mod_path), true, "module layout should normalize")

    assert_list_equals(fs.read_lines(mod_path), {
        "pub mod new_page;",
        "mod private_page;",
        "pub mod existing;",
        "",
        "pub use account::AccountPage;",
        "pub use new_page::NewPage;",
        "",
        "const VALUE: usize = 1;",
    }, "module declarations and exports should be grouped")
end)

--- Verifies Rust layout normalization does not detach attributes or split
--- inline module blocks.
---
--- # Example Under Test
---
--- A `mod.rs` fixture contains a normal public module, an attribute-bound
--- module declaration, an inline test module, and a public export.
---
--- # Assertions
---
--- - Plain module declarations and public exports are grouped.
--- - Attribute-bound declarations remain attached to their attributes.
--- - Inline module blocks stay in their original content order.
---
test("rust layout normalization preserves attributed and inline modules", function()
    local root = path.join(temp_root, "rust-mod-attributes")
    local mod_path = path.join(root, "src", "pages", "mod.rs")
    write_file(mod_path, {
        "pub mod existing;",
        '#[cfg(feature = "admin")]',
        "pub mod admin;",
        "#[cfg(test)]",
        "mod tests {",
        "    fn smoke() {}",
        "}",
        "pub use existing::ExistingPage;",
    })

    assert_equals(rust.normalize_mod_layout(mod_path), true, "module layout should normalize")
    assert_list_equals(fs.read_lines(mod_path), {
        "pub mod existing;",
        "",
        "pub use existing::ExistingPage;",
        "",
        '#[cfg(feature = "admin")]',
        "pub mod admin;",
        "#[cfg(test)]",
        "mod tests {",
        "    fn smoke() {}",
        "}",
    }, "attributed and inline modules should stay attached")
end)
