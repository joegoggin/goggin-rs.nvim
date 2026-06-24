--- Rust public-use cleanup tests.
---
--- Verifies symbol removal from Rust public exports, module reference cleanup,
--- and attribute handling for deleted declarations.

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

--- Verifies Rust module and public-use cleanup.
---
--- # Example Under Test
---
--- A `mod.rs` fixture contains module declarations, direct exports, terminal
--- path exports, and grouped exports.
---
--- # Assertions
---
--- - Grouped, path-terminal, and direct symbols are removed.
--- - Missing symbols leave the file unchanged.
--- - Remaining exports are preserved.
--- - Removing a module reference also removes its declaration and direct export.
---
test("rust helpers remove modules and use symbols", function()
    local root = path.join(temp_root, "rust-remove")
    local mod_path = path.join(root, "src", "components", "mod.rs")
    write_file(mod_path, {
        "pub mod admin;",
        "pub mod users;",
        "",
        "pub use admin::AdminPage;",
        "pub use users::{UserCard, UserList, UserPage};",
        "pub use UserPage;",
    })

    assert_equals(rust.remove_use_symbol(mod_path, "UserList"), true, "grouped use symbol should be removed")
    assert_equals(rust.remove_use_symbol(mod_path, "AdminPage"), true, "path-terminal use symbol should be removed")
    assert_equals(rust.remove_use_symbol(mod_path, "UserPage"), true, "direct and grouped symbols should be removed")
    assert_equals(rust.remove_use_symbol(mod_path, "Missing"), false, "missing symbol should not change file")

    assert_list_equals(fs.read_lines(mod_path), {
        "pub mod admin;",
        "pub mod users;",
        "",
        "pub use users::UserCard;",
    }, "use removals should preserve remaining declarations")

    assert_equals(rust.remove_module_reference(mod_path, "admin"), true, "module reference should be removed")
    assert_list_equals(fs.read_lines(mod_path), {
        "pub mod users;",
        "",
        "pub use users::UserCard;",
    }, "module removal should normalize remaining layout")
end)

--- Verifies Rust removal helpers do not orphan attributes from deleted items.
---
--- # Example Under Test
---
--- `mod.rs` fixtures contain attributes attached to module declarations and
--- public-use declarations that are removed by deletion helpers.
---
--- # Assertions
---
--- - Attributes attached to deleted module declarations are removed.
--- - Attributes attached to deleted public-use declarations are removed.
--- - Attributes attached to surviving public-use declarations remain attached.
---
test("rust removal helpers drop attributes attached to removed declarations", function()
    local root = path.join(temp_root, "rust-remove-attributes")
    local mod_path = path.join(root, "src", "pages", "mod.rs")
    write_file(mod_path, {
        '#[cfg(feature = "admin")]',
        "pub mod admin;",
        "pub mod users;",
        "",
        '#[cfg(feature = "admin")]',
        "pub use admin::AdminPage;",
        "pub use users::UserCard;",
        '#[cfg(feature = "reports")]',
        "pub use reports::ReportsPage;",
    })

    assert_equals(rust.remove_module_reference(mod_path, "admin"), true, "module reference should be removed")
    assert_list_equals(fs.read_lines(mod_path), {
        "pub mod users;",
        "",
        "pub use users::UserCard;",
        "",
        '#[cfg(feature = "reports")]',
        "pub use reports::ReportsPage;",
    }, "module removal should remove attributes attached to deleted declarations")

    local use_path = path.join(root, "src", "components", "mod.rs")
    write_file(use_path, {
        '#[cfg(feature = "admin")]',
        "",
        "pub use admin::AdminPage;",
        "pub use users::UserCard;",
    })

    assert_equals(rust.remove_use_symbol(use_path, "AdminPage"), true, "attributed use symbol should be removed")
    assert_list_equals(fs.read_lines(use_path), {
        "pub use users::UserCard;",
    }, "use removal should not leave deleted symbol attributes behind")
end)
