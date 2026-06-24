--- Rust route mutation tests.
---
--- Verifies Leptos route insertion, route removal, grouped route comments,
--- duplicate handling, and non-self-closing parent routes.

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

--- Verifies Leptos route insertion and removal.
---
--- # Example Under Test
---
--- A Rust app fixture contains grouped auth and blog routes inside a `<Routes>`
--- block.
---
--- # Assertions
---
--- - A private auth route is inserted with the expected macro path.
--- - Duplicate route insertion is ignored.
--- - A new top-level route group is created.
--- - Removing a route by view deletes the route and orphan group comment.
--- - Removing a missing route leaves the file unchanged.
---
test("rust helpers insert and remove app routes", function()
    local root = path.join(temp_root, "rust-routes")
    local app_path = path.join(root, "src", "app.rs")
    write_file(app_path, {
        "view! {",
        "    <Router>",
        "        <Routes fallback=|| view! { <NotFoundPage /> }>",
        "                    // Auth routes",
        '                    <PrivateRoute path=path!("auth/login") view=LoginPage />',
        "",
        "                    // Blog",
        '                    <Route path=path!("/blog") view=BlogIndexPage />',
        "        </Routes>",
        "    </Router>",
        "}",
    })

    assert_equals(
        rust.insert_route(app_path, "/auth/settings", "SettingsPage", { private = true }),
        true,
        "auth private route should be inserted"
    )
    assert_equals(
        rust.insert_route(app_path, "/auth/settings", "SettingsPage", { private = true }),
        false,
        "duplicate route should not be inserted"
    )
    assert_equals(rust.insert_route(app_path, "/reports", "ReportsPage"), true, "new route group should be inserted")

    assert_list_equals(fs.read_lines(app_path), {
        "view! {",
        "    <Router>",
        "        <Routes fallback=|| view! { <NotFoundPage /> }>",
        "                    // Auth routes",
        '                    <PrivateRoute path=path!("auth/login") view=LoginPage />',
        '                    <PrivateRoute path=path!("auth/settings") view=SettingsPage />',
        "",
        "                    // Blog",
        '                    <Route path=path!("/blog") view=BlogIndexPage />',
        "",
        "                    // Reports",
        '                    <Route path=path!("/reports") view=ReportsPage />',
        "        </Routes>",
        "    </Router>",
        "}",
    }, "route insertion should preserve grouped route layout")

    assert_equals(rust.remove_route_view(app_path, "BlogIndexPage"), true, "route should be removed by view")
    assert_equals(rust.remove_route_view(app_path, "MissingPage"), false, "missing route should not change file")

    assert_list_equals(fs.read_lines(app_path), {
        "view! {",
        "    <Router>",
        "        <Routes fallback=|| view! { <NotFoundPage /> }>",
        "                    // Auth routes",
        '                    <PrivateRoute path=path!("auth/login") view=LoginPage />',
        '                    <PrivateRoute path=path!("auth/settings") view=SettingsPage />',
        "",
        "                    // Reports",
        '                    <Route path=path!("/reports") view=ReportsPage />',
        "        </Routes>",
        "    </Router>",
        "}",
    }, "orphan route group comments should be cleaned up")
end)

--- Verifies route removal does not consume non-self-closing parent routes.
---
--- # Example Under Test
---
--- A `<Routes>` fixture contains a parent route with a nested self-closing
--- child route.
---
--- # Assertions
---
--- - Removing the child route leaves the parent route tags balanced.
--- - The route group comment remains because the parent route still exists.
---
test("rust route removal preserves non-self-closing parent routes", function()
    local root = path.join(temp_root, "rust-nested-routes")
    local app_path = path.join(root, "src", "app.rs")
    write_file(app_path, {
        "view! {",
        "    <Router>",
        "        <Routes>",
        "                    // Admin",
        '                    <Route path=path!("/admin") view=AdminLayout>',
        '                        <Route path=path!("users") view=AdminUsersPage />',
        "                    </Route>",
        "        </Routes>",
        "    </Router>",
        "}",
    })

    assert_equals(rust.remove_route_view(app_path, "AdminUsersPage"), true, "nested child route should be removed")
    assert_list_equals(fs.read_lines(app_path), {
        "view! {",
        "    <Router>",
        "        <Routes>",
        "                    // Admin",
        '                    <Route path=path!("/admin") view=AdminLayout>',
        "                    </Route>",
        "        </Routes>",
        "    </Router>",
        "}",
    }, "parent route tags should remain balanced")
end)
