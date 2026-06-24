--- Page creation workflow tests.
---
--- Verifies public, private, flat, and module-layout page generation across
--- Rust modules, SCSS forwards, app routes, touched files, and formatting.

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

--- Verifies public and private page generation.
---
--- # Example Under Test
---
--- Public and private pages are generated into nested route fixture paths while
--- the app file contains an initially empty `<Routes>` block.
---
--- # Assertions
---
--- - Rust and SCSS templates match the source-config output.
--- - Page modules and exports are maintained for nested route segments.
--- - Page style indexes forward through nested directories.
--- - Public and private app routes are inserted with the expected path macros.
--- - Touched files are formatted in first-seen order.
---
test("page workflow creates public and private page files routes and indexes", function()
    with_stubbed_format(function(formatted)
        local root = path.join(temp_root, "page-create-routes")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
            app_path = path.join(root, "src", "app.rs"),
        }

        write_file(paths.app_path, {
            "view! {",
            "    <Router>",
            "        <Routes>",
            "        </Routes>",
            "    </Router>",
            "}",
        })

        local public_result = assert(page.create({
            route = "/admin",
            subroute = "User Settings",
            page_name = "User Settings",
            paths = paths,
            format_opts = { timeout_ms = 30 },
        }))

        local private_result = assert(page.create({
            route = "/auth/login",
            private = true,
            page_name = "Login",
            paths = paths,
            format_opts = { timeout_ms = 30 },
        }))

        local admin_rust_path = path.join(paths.pages_dir, "admin", "user_settings.rs")
        local admin_scss_path = path.join(paths.page_styles_dir, "admin", "_user-settings.scss")
        local auth_rust_path = path.join(paths.pages_dir, "auth", "login.rs")
        local auth_scss_path = path.join(paths.page_styles_dir, "auth", "_login.scss")
        local root_mod = path.join(paths.pages_dir, "mod.rs")
        local admin_mod = path.join(paths.pages_dir, "admin", "mod.rs")
        local auth_mod = path.join(paths.pages_dir, "auth", "mod.rs")
        local root_index = path.join(paths.page_styles_dir, "index.scss")
        local admin_index = path.join(paths.page_styles_dir, "admin", "index.scss")
        local auth_index = path.join(paths.page_styles_dir, "auth", "index.scss")

        assert_equals(public_result.route_path, "/admin/user-settings", "public route path should include sub-route")
        assert_equals(public_result.rust_path, admin_rust_path, "public result should include rust path")
        assert_equals(public_result.scss_path, admin_scss_path, "public result should include scss path")
        assert_equals(private_result.route_path, "/auth/login", "private route path should be preserved")
        assert_equals(private_result.private, true, "private result should record route visibility")

        assert_list_equals(fs.read_lines(admin_rust_path), {
            "use leptos::prelude::*;",
            "",
            "use crate::utils::class_name::ClassNameUtil;",
            "",
            "#[component]",
            "pub fn UserSettingsPage() -> impl IntoView {",
            "    // Classes",
            '    let class_name = ClassNameUtil::new("user-settings-page", None);',
            "    let user_settings_page = class_name.get_root_class();",
            "",
            "    view! {",
            "        <div class=user_settings_page></div>",
            "    }",
            "}",
        }, "public page Rust template should match expected output")
        assert_list_equals(fs.read_lines(admin_scss_path), {
            ".user-settings-page {",
            "}",
        }, "public page SCSS template should match expected output")
        assert_list_equals(fs.read_lines(auth_rust_path), {
            "use leptos::prelude::*;",
            "",
            "use crate::utils::class_name::ClassNameUtil;",
            "",
            "#[component]",
            "pub fn LoginPage() -> impl IntoView {",
            "    // Classes",
            '    let class_name = ClassNameUtil::new("login-page", None);',
            "    let login_page = class_name.get_root_class();",
            "",
            "    view! {",
            "        <div class=login_page></div>",
            "    }",
            "}",
        }, "private page Rust template should match expected output")
        assert_list_equals(fs.read_lines(auth_scss_path), {
            ".login-page {",
            "}",
        }, "private page SCSS template should match expected output")
        assert_list_equals(fs.read_lines(root_mod), {
            "pub mod admin;",
            "pub mod auth;",
            "",
            "pub use admin::user_settings::UserSettingsPage;",
            "pub use auth::login::LoginPage;",
        }, "root pages mod.rs should declare route groups and export pages")
        assert_list_equals(fs.read_lines(admin_mod), {
            "pub mod user_settings;",
        }, "admin mod should declare generated leaf page")
        assert_list_equals(fs.read_lines(auth_mod), {
            "pub mod login;",
        }, "auth mod should declare generated leaf page")
        assert_list_equals(fs.read_lines(root_index), {
            '@forward "admin";',
            '@forward "auth";',
        }, "root page style index should forward route groups")
        assert_list_equals(fs.read_lines(admin_index), {
            '@forward "user-settings";',
        }, "admin style index should forward the generated public page")
        assert_list_equals(fs.read_lines(auth_index), {
            '@forward "login";',
        }, "auth style index should forward the generated private page")
        assert_list_equals(fs.read_lines(paths.app_path), {
            "view! {",
            "    <Router>",
            "        <Routes>",
            "",
            "                    // Admin",
            '                    <Route path=path!("/admin/user-settings") view=UserSettingsPage />',
            "",
            "                    // Auth routes",
            '                    <PrivateRoute path=path!("auth/login") view=LoginPage />',
            "        </Routes>",
            "    </Router>",
            "}",
        }, "app routes should include public and private generated pages")
        assert_list_equals(public_result.touched_paths, {
            admin_rust_path,
            admin_scss_path,
            root_mod,
            admin_mod,
            root_index,
            admin_index,
            paths.app_path,
        }, "public create should return touched files in mutation order")
        assert_list_equals(private_result.touched_paths, {
            auth_rust_path,
            auth_scss_path,
            root_mod,
            auth_mod,
            root_index,
            auth_index,
            paths.app_path,
        }, "private create should return touched files in mutation order")
        assert_list_equals(formatted, {
            admin_rust_path .. ":30",
            admin_scss_path .. ":30",
            root_mod .. ":30",
            admin_mod .. ":30",
            root_index .. ":30",
            admin_index .. ":30",
            paths.app_path .. ":30",
            auth_rust_path .. ":30",
            auth_scss_path .. ":30",
            root_mod .. ":30",
            auth_mod .. ":30",
            root_index .. ":30",
            auth_index .. ":30",
            paths.app_path .. ":30",
        }, "page create should format touched Rust and SCSS files")
    end)
end)

--- Verifies module-layout page generation.
---
--- # Example Under Test
---
--- A nested page is generated directly as a module-layout page with `page.rs`,
--- a page `mod.rs`, and `_page.scss`.
---
--- # Assertions
---
--- - The generated Rust and SCSS files use module-layout paths.
--- - The page module re-exports `page::SummaryPage`.
--- - Parent modules and SCSS indexes point through the route directory chain.
--- - The app route still points at the generated page component.
---
test("page workflow creates module-layout page files and indexes", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "page-create-module-layout")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
            app_path = path.join(root, "src", "app.rs"),
        }

        write_file(paths.app_path, {
            "view! {",
            "    <Router>",
            "        <Routes>",
            "        </Routes>",
            "    </Router>",
            "}",
        })

        local result = assert(page.create({
            route = "/reports/summary",
            page_name = "Summary",
            module_layout = true,
            paths = paths,
            format_opts = { timeout_ms = 40 },
        }))

        local rust_path = path.join(paths.pages_dir, "reports", "summary", "page.rs")
        local scss_path = path.join(paths.page_styles_dir, "reports", "summary", "_page.scss")
        local root_mod = path.join(paths.pages_dir, "mod.rs")
        local reports_mod = path.join(paths.pages_dir, "reports", "mod.rs")
        local summary_mod = path.join(paths.pages_dir, "reports", "summary", "mod.rs")
        local root_index = path.join(paths.page_styles_dir, "index.scss")
        local reports_index = path.join(paths.page_styles_dir, "reports", "index.scss")
        local summary_index = path.join(paths.page_styles_dir, "reports", "summary", "index.scss")

        assert_equals(result.is_module_layout, true, "result should record module-layout generation")
        assert_equals(result.rust_path, rust_path, "module-layout result should include page.rs path")
        assert_equals(result.scss_path, scss_path, "module-layout result should include _page.scss path")
        assert_list_equals(fs.read_lines(rust_path), {
            "use leptos::prelude::*;",
            "",
            "use crate::utils::class_name::ClassNameUtil;",
            "",
            "#[component]",
            "pub fn SummaryPage() -> impl IntoView {",
            "    // Classes",
            '    let class_name = ClassNameUtil::new("summary-page", None);',
            "    let summary_page = class_name.get_root_class();",
            "",
            "    view! {",
            "        <div class=summary_page></div>",
            "    }",
            "}",
        }, "module-layout page Rust template should match expected output")
        assert_list_equals(fs.read_lines(scss_path), {
            ".summary-page {",
            "}",
        }, "module-layout page SCSS template should match expected output")
        assert_list_equals(fs.read_lines(root_mod), {
            "pub mod reports;",
            "",
            "pub use reports::summary::SummaryPage;",
        }, "root pages mod.rs should export the module-layout page")
        assert_list_equals(fs.read_lines(reports_mod), {
            "pub mod summary;",
        }, "parent mod should declare the module-layout leaf")
        assert_list_equals(fs.read_lines(summary_mod), {
            "pub mod page;",
            "",
            "pub use page::SummaryPage;",
        }, "module-layout page mod should re-export the page component")
        assert_list_equals(fs.read_lines(root_index), {
            '@forward "reports";',
        }, "root style index should forward the parent route group")
        assert_list_equals(fs.read_lines(reports_index), {
            '@forward "summary";',
        }, "parent style index should forward the module-layout page directory")
        assert_list_equals(fs.read_lines(summary_index), {
            '@forward "page";',
        }, "module-layout style index should forward _page.scss")
        assert_list_equals(fs.read_lines(paths.app_path), {
            "view! {",
            "    <Router>",
            "        <Routes>",
            "",
            "                    // Reports",
            '                    <Route path=path!("/reports/summary") view=SummaryPage />',
            "        </Routes>",
            "    </Router>",
            "}",
        }, "app routes should include the module-layout page")
        assert_list_equals(result.touched_paths, {
            rust_path,
            scss_path,
            root_mod,
            reports_mod,
            summary_mod,
            root_index,
            reports_index,
            summary_index,
            paths.app_path,
        }, "module-layout create should return touched files in mutation order")
    end)
end)

--- Verifies page generation rejects names and routes that would create invalid
--- Rust identifiers.
---
test("page workflow rejects numeric-leading page names and route modules", function()
    with_stubbed_format(function()
        local root = path.join(temp_root, "page-create-invalid-identifiers")
        create_default_layout(root)

        local paths = {
            pages_dir = path.join(root, "src", "pages"),
            page_styles_dir = path.join(root, "styles", "pages"),
            app_path = path.join(root, "src", "app.rs"),
        }

        local result, err = page.create({
            route = "/reports",
            page_name = "123",
            paths = paths,
        })
        assert_equals(result, nil, "numeric page name should abort")
        assert_match(err, "Page name cannot start with a number.", "page-name error should explain invalid identifier")

        local route_result, route_err = page.create({
            route = "/2024/reports",
            page_name = "Reports",
            paths = paths,
        })
        assert_equals(route_result, nil, "numeric route module should abort")
        assert_match(
            route_err,
            "Route segment cannot start with a number:",
            "route error should explain invalid module"
        )
        assert_equals(fs.exists(path.join(paths.pages_dir, "2024")), false, "invalid route should not write files")
    end)
end)
