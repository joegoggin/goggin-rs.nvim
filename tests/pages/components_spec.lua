--- Page-local component workflow tests.
---
--- Verifies nested page-local component generation, flat-page conversion,
--- duplicate handling, and nested-page conflict handling.

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

--- Verifies nested page-local component generation.
---
--- # Example Under Test
---
--- A flat nested page is converted to module layout while a page-local component
--- is generated under a nested components directory.
---
--- # Assertions
---
--- - The page is converted before component creation.
--- - Generated component Rust and SCSS use page-prefixed names and classes.
--- - Rust modules and style indexes forward through nested component directories.
--- - Page entry collection includes the page and generated local component.
---
test("page workflow creates nested page components and converts flat pages", function()
    with_stubbed_format(function(formatted)
        local root = path.join(temp_root, "page-create-local-component")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
        }

        local flat_rust_path = path.join(paths.pages_dir, "admin", "settings.rs")
        local flat_scss_path = path.join(paths.page_styles_dir, "admin", "_settings-page.scss")
        local module_rust_path = path.join(paths.pages_dir, "admin", "settings", "page.rs")
        local module_scss_path = path.join(paths.page_styles_dir, "admin", "settings", "_page.scss")
        local page_mod = path.join(paths.pages_dir, "admin", "settings", "mod.rs")
        local component_rust_path =
            path.join(paths.pages_dir, "admin", "settings", "components", "panels", "steps", "workflow.rs")
        local component_scss_path =
            path.join(paths.page_styles_dir, "admin", "settings", "components", "panels", "steps", "_workflow.scss")
        local components_mod = path.join(paths.pages_dir, "admin", "settings", "components", "mod.rs")
        local panels_mod = path.join(paths.pages_dir, "admin", "settings", "components", "panels", "mod.rs")
        local steps_mod = path.join(paths.pages_dir, "admin", "settings", "components", "panels", "steps", "mod.rs")
        local admin_index = path.join(paths.page_styles_dir, "admin", "index.scss")
        local page_index = path.join(paths.page_styles_dir, "admin", "settings", "index.scss")
        local components_index = path.join(paths.page_styles_dir, "admin", "settings", "components", "index.scss")
        local panels_index = path.join(paths.page_styles_dir, "admin", "settings", "components", "panels", "index.scss")
        local steps_index =
            path.join(paths.page_styles_dir, "admin", "settings", "components", "panels", "steps", "index.scss")

        write_file(flat_rust_path, {
            "use leptos::prelude::*;",
            "",
            "#[component]",
            "pub fn SettingsPage() -> impl IntoView {",
            "    view! { <div /> }",
            "}",
        })
        write_file(flat_scss_path, {
            ".settings-page {",
            "}",
        })
        write_file(admin_index, {
            '@forward "settings-page";',
        })

        local pages = page.collect(paths)
        local result = assert(page.create_component({
            page = pages[1],
            input_name = "Workflow",
            relative_dir = "Panels/Steps",
            paths = paths,
            format_opts = { timeout_ms = 60 },
        }))

        assert_equals(result.converted_page, true, "flat page should be converted before component creation")
        assert_equals(result.component_name, "SettingsPageWorkflow", "component should be page-prefixed")
        assert_equals(result.module_name, "workflow", "component module should be suffix-based")
        assert_equals(result.class_name, "settings-page-workflow", "component class should be page-prefixed")
        assert_equals(result.relative_dir, "panels/steps", "relative component directory should normalize")
        assert_equals(result.rust_path, component_rust_path, "result should include component Rust path")
        assert_equals(result.scss_path, component_scss_path, "result should include component SCSS path")
        assert_equals(fs.exists(flat_rust_path), false, "flat page Rust should be moved during conversion")
        assert_equals(fs.exists(flat_scss_path), false, "flat page SCSS should be moved during conversion")
        assert_list_equals(fs.read_lines(module_rust_path), {
            "use leptos::prelude::*;",
            "",
            "#[component]",
            "pub fn SettingsPage() -> impl IntoView {",
            "    view! { <div /> }",
            "}",
        }, "converted page Rust should preserve original content")
        assert_list_equals(fs.read_lines(module_scss_path), {
            ".settings-page {",
            "}",
        }, "converted page SCSS should preserve original content")
        assert_list_equals(fs.read_lines(component_rust_path), {
            "use leptos::prelude::*;",
            "",
            "use crate::utils::class_name::ClassNameUtil;",
            "",
            "#[component]",
            "pub fn SettingsPageWorkflow(#[prop(optional, into)] class: Option<String>) -> impl IntoView {",
            "    // Classes",
            '    let class_name = ClassNameUtil::new("settings-page-workflow", class);',
            "    let workflow = class_name.get_root_class();",
            "",
            "    view! {",
            "        <div class=workflow></div>",
            "    }",
            "}",
        }, "page component Rust template should match expected output")
        assert_list_equals(fs.read_lines(component_scss_path), {
            ".settings-page-workflow {",
            "}",
        }, "page component SCSS template should match expected output")
        assert_list_equals(fs.read_lines(page_mod), {
            "mod components;",
            "pub mod page;",
            "",
            "pub use page::SettingsPage;",
        }, "page mod should declare private components and re-export the page")
        assert_list_equals(fs.read_lines(components_mod), {
            "pub mod panels;",
        }, "components mod should declare the first nested component directory")
        assert_list_equals(fs.read_lines(panels_mod), {
            "pub mod steps;",
        }, "nested component parent mod should declare its child")
        assert_list_equals(fs.read_lines(steps_mod), {
            "pub mod workflow;",
            "",
            "pub use workflow::SettingsPageWorkflow;",
        }, "target component mod should declare and export the component")
        assert_list_equals(fs.read_lines(admin_index), {
            '@forward "settings";',
        }, "parent page style index should forward the converted page directory")
        assert_list_equals(fs.read_lines(page_index), {
            '@forward "page";',
            '@forward "components";',
        }, "page style index should forward page and page components")
        assert_list_equals(fs.read_lines(components_index), {
            '@forward "panels";',
        }, "components style index should forward the first nested directory")
        assert_list_equals(fs.read_lines(panels_index), {
            '@forward "steps";',
        }, "nested style index should forward its child directory")
        assert_list_equals(fs.read_lines(steps_index), {
            '@forward "workflow";',
        }, "target style index should forward the component partial")

        local collected_pages = page.collect(paths)
        local entries = page.collect_entries(collected_pages[1], paths)
        assert_equals(#entries, 2, "page entry collection should include page and local component")
        assert_equals(entries[1].label, "Page", "page entry should remain first")
        assert_equals(entries[1].rust_path, module_rust_path, "page entry should point at module page")
        assert_equals(entries[2].label, "Workflow", "component entry should trim the page prefix")
        assert_equals(entries[2].rust_path, component_rust_path, "component entry should point at generated Rust")
        assert_equals(entries[2].scss_path, component_scss_path, "component entry should resolve generated SCSS")

        assert_list_equals(result.touched_paths, {
            module_rust_path,
            page_mod,
            module_scss_path,
            page_index,
            admin_index,
            component_rust_path,
            component_scss_path,
            components_mod,
            panels_mod,
            steps_mod,
            components_index,
            panels_index,
            steps_index,
        }, "page component create should return touched files in mutation order")
        assert_list_equals(formatted, {
            module_rust_path .. ":60",
            page_mod .. ":60",
            module_scss_path .. ":60",
            page_index .. ":60",
            admin_index .. ":60",
            component_rust_path .. ":60",
            component_scss_path .. ":60",
            components_mod .. ":60",
            panels_mod .. ":60",
            steps_mod .. ":60",
            components_index .. ":60",
            panels_index .. ":60",
            steps_index .. ":60",
        }, "page component create should format touched Rust and SCSS files once")

        local duplicate, duplicate_err = page.create_component({
            page = collected_pages[1],
            input_name = "Workflow",
            relative_dir = "panels/steps",
            paths = paths,
        })
        assert_equals(duplicate, nil, "duplicate component creation should abort")
        assert_match(
            duplicate_err,
            "Page component already exists:",
            "duplicate error should name existing Rust target"
        )
    end)
end)

--- Verifies page generation aborts before writing nested pages under flat pages.
---
--- # Example Under Test
---
--- A flat parent page already exists when a nested child route is requested.
---
--- # Assertions
---
--- - Creation returns nil and a flat-parent warning.
--- - No nested Rust, SCSS, or app route changes are written.
---
test("page workflow aborts when nesting under a flat page", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "page-create-flat-parent")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
            app_path = path.join(root, "src", "app.rs"),
        }

        write_file(path.join(paths.pages_dir, "admin.rs"), { "existing" })
        write_file(paths.app_path, {
            "view! {",
            "    <Routes>",
            "    </Routes>",
            "}",
        })

        local result, err = page.create({
            route = "/admin/settings",
            page_name = "Settings",
            paths = paths,
        })

        assert_equals(result, nil, "flat parent should abort creation")
        assert_match(err, "Cannot create nested page under flat page:", "flat-parent error should explain conflict")
        assert_equals(
            fs.exists(path.join(paths.pages_dir, "admin", "settings.rs")),
            false,
            "nested Rust page should not be written"
        )
        assert_equals(
            fs.exists(path.join(paths.page_styles_dir, "admin", "_settings.scss")),
            false,
            "nested SCSS page should not be written"
        )
        assert_list_equals(fs.read_lines(paths.app_path), {
            "view! {",
            "    <Routes>",
            "    </Routes>",
            "}",
        }, "app routes should remain unchanged")
    end)
end)

--- Verifies page-local component generation rejects suffixes that would create
--- invalid Rust module names.
---
test("page workflow rejects numeric-leading page component suffixes", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "page-create-invalid-local-component")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
        }

        write_file(path.join(paths.pages_dir, "admin", "settings", "page.rs"), {
            "#[component]",
            "pub fn SettingsPage() -> impl IntoView {}",
        })

        local pages = page.collect(paths)
        local result, err = page.create_component({
            page = pages[1],
            input_name = "123 Panel",
            paths = paths,
        })

        assert_equals(result, nil, "numeric component suffix should abort")
        assert_match(err, "Component suffix cannot start with a number.", "suffix error should explain invalid module")
        assert_equals(
            fs.exists(path.join(paths.pages_dir, "admin", "settings", "components", "123_panel.rs")),
            false,
            "invalid component should not write files"
        )
    end)
end)

--- Verifies page-local component generation rejects subdirectories that would
--- create invalid Rust module names.
---
test("page workflow rejects numeric-leading page component subdirectories", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "page-create-invalid-local-component-subdir")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
        }

        write_file(path.join(paths.pages_dir, "admin", "settings", "page.rs"), {
            "#[component]",
            "pub fn SettingsPage() -> impl IntoView {}",
        })

        local pages = page.collect(paths)
        local result, err = page.create_component({
            page = pages[1],
            input_name = "Panel",
            relative_dir = "2024/Reports",
            paths = paths,
        })

        assert_equals(result, nil, "numeric page component subdirectory should abort")
        assert_match(
            err,
            "Page component sub-directory cannot start with a number:",
            "subdirectory error should explain invalid module"
        )
        assert_equals(
            fs.exists(path.join(paths.pages_dir, "admin", "settings", "components", "2024")),
            false,
            "invalid page component subdirectory should not write files"
        )
    end)
end)
