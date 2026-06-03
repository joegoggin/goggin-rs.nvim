--- Page collection workflow tests.
---
--- Verifies page discovery across flat and module-layout fixtures and paired
--- SCSS partial resolution for picker entries.

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

--- Verifies page collection and paired SCSS resolution.
---
--- # Example Under Test
---
--- Page fixtures include flat root pages, nested flat pages, a module-layout
--- page, a duplicate flat/module pair, and a page-like component under a
--- `components` directory.
---
--- # Assertions
---
--- - `mod.rs` and page component files are ignored.
--- - Direct, parent-prefixed, component-name, and module-layout SCSS partials resolve.
--- - Module-layout pages win over duplicate flat page files for the same module.
--- - Entries are sorted by display name and relative module path.
---
test("page workflow collects pages and resolves paired styles", function()
    local root = path.join(temp_root, "page-collect")
    create_default_layout(root)

    local paths = {
        pages_dir = path.join(root, "src", "pages"),
        page_styles_dir = path.join(root, "styles", "pages"),
    }

    write_file(path.join(paths.pages_dir, "dashboard.rs"), {
        "use leptos::prelude::*;",
        "",
        "#[component]",
        "pub fn DashboardPage() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "admin", "settings.rs"), {
        "#[component]",
        '#[cfg(feature = "admin")]',
        "",
        "pub fn AdminSettingsPage() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "profile.rs"), {
        "#[component]",
        "pub fn UserProfilePage() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "reports.rs"), {
        "#[component]",
        "pub fn ReportsPage() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "reports", "page.rs"), {
        "#[component]",
        "pub fn ReportsPage() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "reports", "components", "ignored.rs"), {
        "#[component]",
        "pub fn IgnoredPage() -> impl IntoView {",
        "    view! { <div></div> }",
        "}",
    })
    write_file(path.join(paths.pages_dir, "helper.rs"), {
        "pub fn helper() {}",
    })
    write_file(path.join(paths.page_styles_dir, "_dashboard.scss"), {
        ".dashboard-page {",
        "}",
    })
    write_file(path.join(paths.page_styles_dir, "admin", "_admin-settings.scss"), {
        ".admin-settings-page {",
        "}",
    })
    write_file(path.join(paths.page_styles_dir, "_user-profile-page.scss"), {
        ".user-profile-page {",
        "}",
    })
    write_file(path.join(paths.page_styles_dir, "reports", "_page.scss"), {
        ".reports-page {",
        "}",
    })

    local pages = page.collect(paths)

    assert_equals(#pages, 4, "only top-level page Rust files should be collected")
    assert_equals(pages[1].display_name, "AdminSettings", "nested page should sort first")
    assert_equals(pages[1].rust_relative, "admin/settings.rs", "nested page relative path should be stored")
    assert_equals(
        pages[1].page_style_path,
        path.join(paths.page_styles_dir, "admin", "_admin-settings.scss"),
        "nested page should resolve parent-prefixed SCSS partial"
    )
    assert_equals(pages[2].display_name, "Dashboard", "root page should sort by display name")
    assert_equals(
        pages[2].page_style_path,
        path.join(paths.page_styles_dir, "_dashboard.scss"),
        "root page should resolve direct stem SCSS partial"
    )
    assert_equals(pages[3].display_name, "Reports", "module-layout page should be collected")
    assert_equals(pages[3].is_module_layout, true, "module-layout page should win over duplicate flat page")
    assert_equals(pages[3].rust_relative, "reports/page.rs", "module-layout page path should be stored")
    assert_equals(
        pages[3].page_style_path,
        path.join(paths.page_styles_dir, "reports", "_page.scss"),
        "module-layout page should resolve _page.scss"
    )
    assert_equals(pages[4].display_name, "UserProfile", "component-name style fallback page should sort last")
    assert_equals(
        pages[4].page_style_path,
        path.join(paths.page_styles_dir, "_user-profile-page.scss"),
        "page should resolve component-name SCSS partial"
    )
end)
