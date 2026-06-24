--- Component creation workflow tests.
---
--- Verifies root, nested, and duplicate component generation behavior across
--- Rust modules, SCSS forwards, touched files, and formatting.

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

--- Verifies root component generation.
---
--- # Example Under Test
---
--- A root-level component is generated into a fixture project with empty
--- component and style roots.
---
--- # Assertions
---
--- - Rust and SCSS templates match the source-config output.
--- - Root Rust `mod.rs` and SCSS `index.scss` are updated.
--- - Touched files are formatted in first-seen order.
---
test("component workflow creates root component files and indexes", function()
    with_stubbed_format(function(formatted)
        local root = path.join(temp_root, "component-create-root")
        create_default_layout(root)

        local paths = {
            components_dir = path.join(root, "src", "components"),
            styles_components_dir = path.join(root, "styles", "components"),
        }

        local result = assert(component.create({
            input_name = "Hero Card",
            relative_dir = "",
            paths = paths,
            format_opts = { timeout_ms = 10 },
        }))

        local rust_path = path.join(paths.components_dir, "hero_card.rs")
        local scss_path = path.join(paths.styles_components_dir, "_hero-card.scss")
        local mod_path = path.join(paths.components_dir, "mod.rs")
        local index_path = path.join(paths.styles_components_dir, "index.scss")

        assert_equals(result.rust_path, rust_path, "result should include rust path")
        assert_equals(result.scss_path, scss_path, "result should include scss path")
        assert_list_equals(fs.read_lines(rust_path), {
            "use leptos::prelude::*;",
            "",
            "use crate::utils::class_name::ClassNameUtil;",
            "",
            "#[component]",
            "pub fn HeroCard(#[prop(optional, into)] class: Option<String>) -> impl IntoView {",
            "    // Classes",
            '    let class_name = ClassNameUtil::new("hero-card", class);',
            "    let hero_card = class_name.get_root_class();",
            "",
            "    view! {",
            "        <div class=hero_card></div>",
            "    }",
            "}",
        }, "root component Rust template should match expected output")
        assert_list_equals(fs.read_lines(scss_path), {
            ".hero-card {",
            "}",
        }, "root component SCSS template should match expected output")
        assert_list_equals(fs.read_lines(mod_path), {
            "pub mod hero_card;",
            "",
            "pub use hero_card::HeroCard;",
        }, "root component mod.rs should declare and export the component")
        assert_list_equals(fs.read_lines(index_path), {
            '@forward "hero-card";',
        }, "root style index should forward the component partial")
        assert_list_equals(result.touched_paths, {
            rust_path,
            scss_path,
            mod_path,
            index_path,
        }, "root create should return touched files in mutation order")
        assert_list_equals(formatted, {
            rust_path .. ":10",
            scss_path .. ":10",
            mod_path .. ":10",
            index_path .. ":10",
        }, "root create should format touched Rust and SCSS files")
    end)
end)

--- Verifies nested component generation.
---
--- # Example Under Test
---
--- A component is generated into a nested component directory selected from
--- mixed-case user input.
---
--- # Assertions
---
--- - The nested directory is normalized to snake_case path segments.
--- - Parent Rust modules and root re-export are maintained.
--- - Nested SCSS indexes forward from root to leaf partial.
---
test("component workflow creates nested component files and forward chains", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "component-create-nested")
        create_default_layout(root)

        local paths = {
            components_dir = path.join(root, "src", "components"),
            styles_components_dir = path.join(root, "styles", "components"),
        }

        local result = assert(component.create({
            input_name = "User Badge",
            relative_dir = "Admin Tools/Users",
            paths = paths,
            format_opts = { timeout_ms = 20 },
        }))

        local rust_path = path.join(paths.components_dir, "admin_tools", "users", "user_badge.rs")
        local scss_path = path.join(paths.styles_components_dir, "admin_tools", "users", "_user-badge.scss")
        local root_mod = path.join(paths.components_dir, "mod.rs")
        local admin_mod = path.join(paths.components_dir, "admin_tools", "mod.rs")
        local users_mod = path.join(paths.components_dir, "admin_tools", "users", "mod.rs")
        local root_index = path.join(paths.styles_components_dir, "index.scss")
        local admin_index = path.join(paths.styles_components_dir, "admin_tools", "index.scss")
        local users_index = path.join(paths.styles_components_dir, "admin_tools", "users", "index.scss")

        assert_equals(result.relative_dir, "admin_tools/users", "relative directory should normalize")
        assert_list_equals(fs.read_lines(rust_path), {
            "use leptos::prelude::*;",
            "",
            "use crate::utils::class_name::ClassNameUtil;",
            "",
            "#[component]",
            "pub fn UserBadge(#[prop(optional, into)] class: Option<String>) -> impl IntoView {",
            "    // Classes",
            '    let class_name = ClassNameUtil::new("user-badge", class);',
            "    let user_badge = class_name.get_root_class();",
            "",
            "    view! {",
            "        <div class=user_badge></div>",
            "    }",
            "}",
        }, "nested component Rust template should match expected output")
        assert_list_equals(fs.read_lines(scss_path), {
            ".user-badge {",
            "}",
        }, "nested component SCSS template should match expected output")
        assert_list_equals(fs.read_lines(root_mod), {
            "pub mod admin_tools;",
            "",
            "pub use admin_tools::*;",
        }, "root mod should declare and re-export the first nested segment")
        assert_list_equals(fs.read_lines(admin_mod), {
            "pub mod users;",
        }, "intermediate mod should declare the next nested segment")
        assert_list_equals(fs.read_lines(users_mod), {
            "pub mod user_badge;",
            "",
            "pub use user_badge::UserBadge;",
        }, "target mod should declare and export the generated component")
        assert_list_equals(fs.read_lines(root_index), {
            '@forward "admin_tools";',
        }, "root style index should forward the first nested segment")
        assert_list_equals(fs.read_lines(admin_index), {
            '@forward "users";',
        }, "intermediate style index should forward the next segment")
        assert_list_equals(fs.read_lines(users_index), {
            '@forward "user-badge";',
        }, "target style index should forward the component partial")
        assert_list_equals(result.touched_paths, {
            rust_path,
            scss_path,
            root_mod,
            admin_mod,
            users_mod,
            root_index,
            admin_index,
            users_index,
        }, "nested create should return touched files in mutation order")
    end)
end)

--- Verifies duplicate component generation aborts before writing related files.
---
--- # Example Under Test
---
--- The target Rust component path already exists before generation starts.
---
--- # Assertions
---
--- - Creation returns nil and a duplicate-path warning.
--- - The existing Rust file remains unchanged.
--- - No SCSS partial or index files are created for the duplicate.
---
test("component workflow aborts when target files already exist", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "component-create-duplicate")
        create_default_layout(root)

        local paths = {
            components_dir = path.join(root, "src", "components"),
            styles_components_dir = path.join(root, "styles", "components"),
        }

        local rust_path = path.join(paths.components_dir, "hero_card.rs")
        local scss_path = path.join(paths.styles_components_dir, "_hero-card.scss")
        local index_path = path.join(paths.styles_components_dir, "index.scss")
        write_file(rust_path, { "existing" })

        local result, err = component.create({
            input_name = "Hero Card",
            paths = paths,
        })

        assert_equals(result, nil, "duplicate rust target should abort creation")
        assert_match(err, "Rust component already exists:", "duplicate error should name existing rust target")
        assert_list_equals(fs.read_lines(rust_path), {
            "existing",
        }, "duplicate create should not rewrite the existing Rust file")
        assert_equals(fs.exists(scss_path), false, "duplicate create should not write the SCSS file")
        assert_equals(fs.exists(index_path), false, "duplicate create should not write style indexes")
    end)
end)

--- Verifies component generation rejects subdirectories that would create
--- invalid Rust module names.
---
test("component workflow rejects numeric-leading subdirectories", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "component-create-invalid-subdir")
        create_default_layout(root)

        local paths = {
            components_dir = path.join(root, "src", "components"),
            styles_components_dir = path.join(root, "styles", "components"),
        }

        local result, err = component.create({
            input_name = "Report Card",
            relative_dir = "2024/Reports",
            paths = paths,
        })

        assert_equals(result, nil, "numeric component subdirectory should abort")
        assert_match(
            err,
            "Component sub-directory cannot start with a number:",
            "subdirectory error should explain invalid module"
        )
        assert_equals(
            fs.exists(path.join(paths.components_dir, "2024")),
            false,
            "invalid subdirectory should not write files"
        )
    end)
end)
