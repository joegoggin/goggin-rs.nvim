--- Component collection workflow tests.
---
--- Verifies Leptos component discovery and paired SCSS partial resolution for
--- root and nested component fixtures.

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

--- Verifies component collection and paired SCSS resolution.
---
--- # Example Under Test
---
--- Component fixtures include root and nested Rust components, a `mod.rs` file
--- with a component-like function, and direct plus parent-prefixed SCSS partials.
---
--- # Assertions
---
--- - `mod.rs` and files without `#[component]` are ignored.
--- - Component names are parsed after optional attributes and blank lines.
--- - Direct root SCSS partials and nested parent-prefixed SCSS partials resolve.
--- - Entries are sorted by component name.
---
test("component workflow collects components and resolves paired styles", function()
    local root = path.join(temp_root, "component-collect")
    create_default_layout(root)

    local paths = {
        components_dir = path.join(root, "src", "components"),
        styles_components_dir = path.join(root, "styles", "components"),
    }

    write_file(path.join(paths.components_dir, "user_card.rs"), {
        "use leptos::prelude::*;",
        "",
        "#[component]",
        "pub fn UserCard() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.components_dir, "admin", "user_list.rs"), {
        "#[component]",
        '#[cfg(feature = "admin")]',
        "",
        "pub fn UserList() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.components_dir, "admin", "mod.rs"), {
        "#[component]",
        "pub fn IgnoredMod() -> impl IntoView {}",
    })
    write_file(path.join(paths.components_dir, "helper.rs"), {
        "pub fn helper() {}",
    })
    write_file(path.join(paths.styles_components_dir, "_user-card.scss"), {
        ".user-card {",
        "}",
    })
    write_file(path.join(paths.styles_components_dir, "admin", "_admin-user-list.scss"), {
        ".admin-user-list {",
        "}",
    })

    local components = component.collect(paths)

    assert_equals(#components, 2, "only component Rust files should be collected")
    assert_equals(components[1].component_name, "UserCard", "root component should sort first")
    assert_equals(components[1].rust_relative, "user_card.rs", "root component relative path should be stored")
    assert_equals(
        components[1].scss_path,
        path.join(paths.styles_components_dir, "_user-card.scss"),
        "root component should resolve direct SCSS partial"
    )
    assert_equals(components[2].component_name, "UserList", "nested component should be collected")
    assert_equals(
        components[2].scss_path,
        path.join(paths.styles_components_dir, "admin", "_admin-user-list.scss"),
        "nested component should resolve parent-prefixed SCSS partial"
    )
end)
