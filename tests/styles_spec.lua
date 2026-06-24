--- Style workflow tests.
---
--- Verifies missing/existing style collection, style creation with Rust class
--- setup, and style deletion with SCSS forward pruning.

local h = require("tests.helpers")

local fs = h.fs
local path = h.path
local styles = h.styles

local temp_root = h.temp_root
local write_file = h.write_file
local create_default_layout = h.create_default_layout
local assert_equals = h.assert_equals
local assert_list_equals = h.assert_list_equals
local test = h.test
local with_stubbed_format = h.with_stubbed_format

--- Finds a style item by component name.
---
---@param items table[] Style items.
---@param component_name string Component name to find.
---@return table|nil item Matching style item.
---
local function find_item(items, component_name)
    for _, item in ipairs(items) do
        if item.component_name == component_name then
            return item
        end
    end

    return nil
end

--- Verifies style collection for missing and existing styles.
---
--- # Example Under Test
---
--- Fixtures include a flat page missing a style, a module page with an existing
--- style, a page-local component missing a parent-prefixed style, a regular
--- component missing a singular-mapped parent-prefixed style, and a regular
--- component with an existing style and custom `ClassNameUtil` class.
---
--- # Assertions
---
--- - Missing and existing modes return disjoint item sets.
--- - Items are ordered by page, page component, then regular component.
--- - Style paths, forward targets, style segments, and class-name extraction match source behavior.
---
test("style workflow collects missing and existing styles", function()
    local root = path.join(temp_root, "styles-collect")
    create_default_layout(root)

    local paths = {
        components_dir = path.join(root, "src", "components"),
        styles_components_dir = path.join(root, "styles", "components"),
        pages_dir = path.join(root, "src", "pages"),
        page_styles_dir = path.join(root, "styles", "pages"),
    }

    write_file(path.join(paths.components_dir, "users", "profile_card.rs"), {
        "#[component]",
        "pub fn ProfileCard() -> impl IntoView {",
        "    view! { <div /> }",
        "}",
    })
    write_file(path.join(paths.components_dir, "nav_bar.rs"), {
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        "pub fn NavBar() -> impl IntoView {",
        '    let class_name = ClassNameUtil::new("nav-shell", None);',
        "    view! { <div /> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "admin", "settings.rs"), {
        "#[component]",
        "pub fn SettingsPage() -> impl IntoView {",
        "    view! { <div /> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "reports", "page.rs"), {
        "#[component]",
        "pub fn ReportsPage() -> impl IntoView {",
        "    view! { <div /> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "reports", "components", "panels", "summary.rs"), {
        "#[component]",
        "pub fn ReportsPageSummary() -> impl IntoView {",
        "    view! { <div /> }",
        "}",
    })

    write_file(path.join(paths.styles_components_dir, "index.scss"), {
        '@forward "user";',
    })
    write_file(path.join(paths.styles_components_dir, "user", "_user-avatar.scss"), {
        ".user-avatar {",
        "}",
    })
    write_file(path.join(paths.styles_components_dir, "_nav-bar.scss"), {
        ".nav-shell {",
        "}",
    })
    write_file(path.join(paths.page_styles_dir, "reports", "_page.scss"), {
        ".reports-page {",
        "}",
    })
    write_file(path.join(paths.page_styles_dir, "reports", "components", "panels", "_panels-list.scss"), {
        ".panels-list {",
        "}",
    })

    local missing = styles.collect({ paths = paths, include_existing = false })
    assert_equals(#missing, 3, "missing collection should include only style gaps")
    assert_equals(missing[1].component_name, "SettingsPage", "missing page should sort first")
    assert_equals(missing[1].item_type, "page", "flat missing page should be a page item")
    assert_equals(
        missing[1].scss_path,
        path.join(paths.page_styles_dir, "admin", "_settings.scss"),
        "flat page should plan module-name SCSS path"
    )
    assert_equals(missing[1].style_target, "settings", "flat page should forward module target")
    assert_list_equals(missing[1].style_segments, { "admin" }, "flat page should use parent style segments")
    assert_equals(missing[1].class_name, "settings-page", "flat page class should derive from component name")

    assert_equals(missing[2].component_name, "ReportsPageSummary", "page component should sort before components")
    assert_equals(missing[2].item_type, "page_component", "page-local missing item should be typed")
    assert_equals(
        missing[2].scss_path,
        path.join(paths.page_styles_dir, "reports", "components", "panels", "_panels-summary.scss"),
        "page component should prefer sibling parent-prefixed style naming"
    )
    assert_equals(missing[2].style_target, "panels-summary", "page component should forward planned target")

    assert_equals(missing[3].component_name, "ProfileCard", "regular component should sort after page items")
    assert_equals(missing[3].item_type, "component", "regular missing item should be typed")
    assert_equals(
        missing[3].scss_path,
        path.join(paths.styles_components_dir, "user", "_user-profile-card.scss"),
        "regular component should use singular root-forward style segment"
    )
    assert_list_equals(missing[3].style_segments, { "user" }, "component style segments should map users to user")
    assert_equals(missing[3].style_target, "user-profile-card", "component target should use prefixed style")

    local existing = styles.collect({ paths = paths, include_existing = true })
    assert_equals(#existing, 2, "existing collection should include only items with styles")
    assert_equals(existing[1].component_name, "ReportsPage", "existing page should sort first")
    assert_equals(existing[1].scss_path, path.join(paths.page_styles_dir, "reports", "_page.scss"))
    assert_equals(existing[2].component_name, "NavBar", "existing component should sort after pages")
    assert_equals(existing[2].class_name, "nav-shell", "existing ClassNameUtil class should be preserved")
end)

--- Verifies missing style creation.
---
--- # Example Under Test
---
--- A nested component has no SCSS partial, but the style root forwards a
--- singular directory and the target style directory already uses
--- parent-prefixed filenames.
---
--- # Assertions
---
--- - The planned SCSS partial is written from the class template.
--- - The nested style index forwards the new partial target.
--- - The Rust component receives the `ClassNameUtil` import and setup block.
--- - Touched files are formatted in mutation order.
---
test("style workflow creates missing style and inserts Rust class setup", function()
    with_stubbed_format(function(formatted)
        local root = path.join(temp_root, "styles-create")
        create_default_layout(root)

        local paths = {
            components_dir = path.join(root, "src", "components"),
            styles_components_dir = path.join(root, "styles", "components"),
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
        }

        local rust_path = path.join(paths.components_dir, "users", "profile_card.rs")
        local scss_path = path.join(paths.styles_components_dir, "user", "_user-profile-card.scss")
        local style_index = path.join(paths.styles_components_dir, "user", "index.scss")
        write_file(rust_path, {
            "use leptos::prelude::*;",
            "",
            "#[component]",
            "pub fn ProfileCard(",
            "    #[prop(optional, into)] class: Option<String>,",
            ") -> impl IntoView {",
            "    view! { <div /> }",
            "}",
        })
        write_file(path.join(paths.styles_components_dir, "index.scss"), {
            '@forward "user";',
        })
        write_file(path.join(paths.styles_components_dir, "user", "_user-avatar.scss"), {
            ".user-avatar {",
            "}",
        })

        local item = find_item(styles.collect({ paths = paths, include_existing = false }), "ProfileCard")
        local result = assert(styles.create_missing_style(item, {
            format_opts = { timeout_ms = 60 },
            notify = false,
        }))

        assert_equals(result.scss_path, scss_path, "creation result should include SCSS path")
        assert_list_equals(fs.read_lines(scss_path), {
            ".user-profile-card {",
            "}",
        }, "created SCSS should use planned class name")
        assert_list_equals(fs.read_lines(style_index), {
            '@forward "user-profile-card";',
        }, "style index should forward new target")
        assert_list_equals(fs.read_lines(rust_path), {
            "use leptos::prelude::*;",
            "use crate::utils::class_name::ClassNameUtil;",
            "",
            "#[component]",
            "pub fn ProfileCard(",
            "    #[prop(optional, into)] class: Option<String>,",
            ") -> impl IntoView {",
            "    // Classes",
            '    let class_name = ClassNameUtil::new("user-profile-card", class);',
            "    let user_profile_card = class_name.get_root_class();",
            "",
            "    view! { <div /> }",
            "}",
        }, "Rust class setup should be inserted after the component body opens")
        assert_list_equals(result.touched_paths, {
            scss_path,
            style_index,
            rust_path,
        }, "creation should return touched files in mutation order")
        assert_list_equals(formatted, {
            scss_path .. ":60",
            style_index .. ":60",
            rust_path .. ":60",
        }, "creation should format touched Rust and SCSS files once")
    end)
end)

--- Verifies existing style deletion.
---
--- # Example Under Test
---
--- A module-layout page has a page-local component style inside an otherwise
--- empty nested style directory chain.
---
--- # Assertions
---
--- - The component style partial is deleted.
--- - Leaf and parent style forwards are removed.
--- - Empty style directories are pruned up to the page directory.
--- - The Rust component file is left unchanged.
---
test("style workflow deletes styles and prunes empty style directories", function()
    local root = path.join(temp_root, "styles-delete")
    create_default_layout(root)

    local paths = {
        components_dir = path.join(root, "src", "components"),
        styles_components_dir = path.join(root, "styles", "components"),
        pages_dir = path.join(root, "src", "pages"),
        page_styles_dir = path.join(root, "styles", "pages"),
    }

    local page_rust_path = path.join(paths.pages_dir, "reports", "page.rs")
    local component_rust_path = path.join(paths.pages_dir, "reports", "components", "panels", "summary.rs")
    local page_index = path.join(paths.page_styles_dir, "reports", "index.scss")
    local components_index = path.join(paths.page_styles_dir, "reports", "components", "index.scss")
    local panels_index = path.join(paths.page_styles_dir, "reports", "components", "panels", "index.scss")
    local component_scss_path = path.join(paths.page_styles_dir, "reports", "components", "panels", "_summary.scss")

    local rust_lines = {
        "#[component]",
        "pub fn ReportsPageSummary() -> impl IntoView {",
        "    view! { <div /> }",
        "}",
    }

    write_file(page_rust_path, {
        "#[component]",
        "pub fn ReportsPage() -> impl IntoView {",
        "    view! { <div /> }",
        "}",
    })
    write_file(component_rust_path, rust_lines)
    write_file(path.join(paths.page_styles_dir, "index.scss"), {
        '@forward "reports";',
    })
    write_file(path.join(paths.page_styles_dir, "reports", "_page.scss"), {
        ".reports-page {",
        "}",
    })
    write_file(page_index, {
        '@forward "page";',
        '@forward "components";',
    })
    write_file(components_index, {
        '@forward "panels";',
    })
    write_file(panels_index, {
        '@forward "summary";',
    })
    write_file(component_scss_path, {
        ".summary {",
        "}",
    })

    local item = find_item(styles.collect({ paths = paths, include_existing = true }), "ReportsPageSummary")
    local result = assert(styles.delete_style(item, { notify = false }))

    assert_equals(result.scss_path, component_scss_path, "deletion result should include SCSS path")
    assert_equals(fs.exists(component_scss_path), false, "style partial should be deleted")
    assert_equals(
        fs.exists(path.join(paths.page_styles_dir, "reports", "components", "panels")),
        false,
        "empty leaf style directory should be pruned"
    )
    assert_equals(
        fs.exists(path.join(paths.page_styles_dir, "reports", "components")),
        false,
        "empty components style directory should be pruned"
    )
    assert_list_equals(fs.read_lines(page_index), {
        '@forward "page";',
    }, "page index should drop the pruned components forward")
    assert_list_equals(fs.read_lines(path.join(paths.page_styles_dir, "index.scss")), {
        '@forward "reports";',
    }, "page style root should keep reports because the page style remains")
    assert_list_equals(fs.read_lines(component_rust_path), rust_lines, "delete style should not mutate Rust source")
    assert_list_equals(result.touched_paths, {
        component_scss_path,
        panels_index,
        path.join(paths.page_styles_dir, "reports", "components", "panels"),
        components_index,
        path.join(paths.page_styles_dir, "reports", "components"),
        page_index,
    }, "delete should track deleted files, pruned directories, and updated indexes")
end)
