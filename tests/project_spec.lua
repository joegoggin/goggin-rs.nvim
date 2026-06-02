--- Headless fixture tests for goggin-rs.nvim helpers.
---
--- Runs without a plugin manager by extending `package.path`, creating
--- temporary project layouts, and exercising path, naming, project discovery,
--- Rust mutation, SCSS mutation, pruning, and touched-file formatting helpers.

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local plugin = require("goggin-rs")
local fs = require("goggin-rs.fs")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.path")
local project = require("goggin-rs.project")
local rust = require("goggin-rs.rust")
local scss = require("goggin-rs.scss")
local touch = require("goggin-rs.touch")

local temp_root = vim.fn.tempname()
local original_cwd = vim.fn.getcwd()
local passed = 0

--- Creates a directory and missing parents.
---
---@param path string Directory path to create.
---
local function mkdir(path)
    vim.fn.mkdir(path, "p")
end

--- Writes lines to a file, creating the parent directory first.
---
---@param path string File path to write.
---@param lines string[]|nil Lines to write, or an empty file when nil.
---
local function write_file(path, lines)
    mkdir(vim.fn.fnamemodify(path, ":h"))
    vim.fn.writefile(lines or {}, path)
end

--- Creates the default web project layout expected by project resolution.
---
---@param web_root string Directory that should contain web project paths.
---
local function create_default_layout(web_root)
    mkdir(path.join(web_root, "src", "components"))
    mkdir(path.join(web_root, "styles", "components"))
    mkdir(path.join(web_root, "src", "pages"))
    mkdir(path.join(web_root, "styles", "pages"))
    write_file(path.join(web_root, "src", "app.rs"), { "fn main() {}" })
end

--- Resets plugin state and Neovim cwd for a test fixture.
---
---@param root string Directory to make the current working directory.
---
local function reset(root)
    plugin.setup({})
    vim.cmd("enew!")
    mkdir(root)
    vim.fn.chdir(root)
end

--- Asserts that two scalar values are equal.
---
---@param actual any Actual value.
---@param expected any Expected value.
---@param message string Failure message.
---
local function assert_equals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s\nexpected: %s\nactual:   %s", message, tostring(expected), tostring(actual)), 2)
    end
end

--- Asserts that a string contains a literal pattern.
---
---@param value any Value converted to a string.
---@param pattern string Literal text expected in the value.
---@param message string Failure message.
---
local function assert_match(value, pattern, message)
    if not tostring(value):find(pattern, 1, true) then
        error(
            string.format("%s\nexpected to contain: %s\nactual:              %s", message, pattern, tostring(value)),
            2
        )
    end
end

--- Asserts that two array-like tables contain the same ordered values.
---
---@param actual any[] Actual list.
---@param expected any[] Expected list.
---@param message string Failure message.
---
local function assert_list_equals(actual, expected, message)
    if #actual ~= #expected then
        error(
            string.format(
                "%s\nexpected length: %s\nactual length:   %s",
                message,
                tostring(#expected),
                tostring(#actual)
            ),
            2
        )
    end

    for index, expected_value in ipairs(expected) do
        if actual[index] ~= expected_value then
            error(
                string.format(
                    "%s\nindex:    %s\nexpected: %s\nactual:   %s",
                    message,
                    tostring(index),
                    tostring(expected_value),
                    tostring(actual[index])
                ),
                2
            )
        end
    end
end

--- Runs a named test and exits the process on failure.
---
---@param name string Test name printed in TAP-like output.
---@param fn fun() Test body.
---
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)

    if not ok then
        io.stderr:write(string.format("not ok - %s\n%s\n", name, err))
        vim.fn.chdir(original_cwd)
        vim.fn.delete(temp_root, "rf")
        os.exit(1)
    end

    passed = passed + 1
    print("ok - " .. name)
end

mkdir(temp_root)

--- Verifies path helper behavior for representative inputs.
---
--- # Example Under Test
---
--- A temporary root is joined, relativized, tested for absoluteness, and
--- normalized with and without trailing slashes.
---
--- # Assertions
---
--- - Empty path parts are skipped when joining.
--- - Child paths are returned relative to the root.
--- - Non-child paths are left unchanged.
--- - Unix and Windows absolute paths are detected.
--- - Directory normalization handles nil, blank, trailing slash, and root paths.
---
test("path helpers preserve join normalize and relative behavior", function()
    local root = path.join(temp_root, "path-helpers")
    mkdir(root)

    assert_equals(path.join(root, nil, "", "src", "pages"), root .. "/src/pages", "join should skip empty parts")
    assert_equals(path.relative(root, root), "", "relative should strip matching root")
    assert_equals(
        path.relative(root, path.join(root, "src", "pages")),
        "src/pages",
        "relative should strip root prefix"
    )
    assert_equals(
        path.relative(root, root .. "-other/file.rs"),
        root .. "-other/file.rs",
        "relative should leave non-child paths alone"
    )
    assert_equals(path.is_absolute(root), true, "absolute unix path should be detected")
    assert_equals(path.is_absolute("C:/web/src"), true, "absolute windows path should be detected")
    assert_equals(path.is_absolute("src/pages"), false, "relative path should not be absolute")
    assert_equals(path.normalize_dir(nil), nil, "nil directory should normalize to nil")
    assert_equals(path.normalize_dir(""), nil, "empty directory should normalize to nil")
    assert_equals(path.normalize_dir(root .. "/"), root, "directory normalization should strip trailing slash")
    assert_equals(path.normalize_dir("/"), "/", "directory normalization should preserve root")
end)

--- Verifies filesystem helpers for missing, existing, and ensured paths.
---
--- # Example Under Test
---
--- A temporary nested directory and files are created through the filesystem
--- helper module.
---
--- # Assertions
---
--- - Missing files report non-existence and read as an empty line list.
--- - Nested directories are created on demand.
--- - Written files exist and read back with the same lines.
--- - Ensured files are created empty when missing.
---
test("filesystem helpers read write and ensure paths", function()
    local root = path.join(temp_root, "fs-helpers")
    local nested = path.join(root, "nested")
    local file_path = path.join(nested, "notes.txt")

    assert_equals(fs.exists(file_path), false, "missing file should not exist")
    assert_list_equals(fs.read_lines(file_path), {}, "missing file should read as empty lines")

    fs.ensure_directory(nested)
    assert_equals(fs.is_directory(nested), true, "ensure_directory should create nested directories")

    fs.write_lines(file_path, { "one", "two" })
    assert_equals(fs.exists(file_path), true, "written file should exist")
    assert_list_equals(fs.read_lines(file_path), { "one", "two" }, "read_lines should return written lines")

    local empty_file = path.join(root, "empty.txt")
    fs.ensure_file(empty_file)
    assert_equals(fs.exists(empty_file), true, "ensure_file should create missing file")
    assert_list_equals(fs.read_lines(empty_file), {}, "ensure_file should create an empty file")
end)

--- Verifies general naming conversions.
---
--- # Example Under Test
---
--- Mixed acronym, PascalCase, snake_case, kebab-case, spaced, blank, and
--- relative directory inputs are normalized.
---
--- # Assertions
---
--- - Outer whitespace is trimmed.
--- - Mixed input splits into lowercase words.
--- - Pascal, snake, and kebab conversions match expected casing.
--- - Path splitting ignores empty and dot segments.
--- - Relative directory normalization snake-cases each segment.
---
test("naming helpers convert words and relative paths", function()
    assert_equals(naming.trim("  Account Settings  "), "Account Settings", "trim should remove outer whitespace")
    assert_list_equals(
        naming.split_words("HTTPServer_page-name"),
        { "http", "server", "page", "name" },
        "split_words should normalize representative input"
    )
    assert_equals(
        naming.to_pascal_case("account-settings page"),
        "AccountSettingsPage",
        "pascal case should convert spaced kebab input"
    )
    assert_equals(
        naming.to_snake_case("AccountSettingsPage"),
        "account_settings_page",
        "snake case should split pascal input"
    )
    assert_equals(
        naming.to_kebab_case("account_settings Page"),
        "account-settings-page",
        "kebab case should convert mixed input"
    )
    assert_equals(naming.to_pascal_case("   "), "", "blank pascal input should be empty")
    assert_list_equals(
        naming.split_path_segments("/admin/./User Settings//"),
        { "admin", "User Settings" },
        "path segments should ignore empty and dot segments"
    )
    assert_equals(
        naming.normalize_relative_dir("/Admin Tools/./UserSettings//"),
        "admin_tools/user_settings",
        "relative directory normalization should snake-case segments"
    )
end)

--- Verifies route segment normalization.
---
--- # Example Under Test
---
--- Static, dynamic, wildcard, and blank route segments are converted for file
--- paths and URL paths.
---
--- # Assertions
---
--- - Static route segments use snake_case for files and kebab-case for URLs.
--- - Dynamic route markers are stripped for files and preserved for URLs.
--- - Wildcards become `all` for file paths.
--- - Blank file segments fall back to `index`.
---
test("naming helpers preserve route-safe segment behavior", function()
    assert_equals(
        naming.route_segment_to_fs("BlogPost"),
        "blog_post",
        "route fs segment should snake-case static names"
    )
    assert_equals(naming.route_segment_to_fs(":postId"), "post_id", "route fs segment should strip dynamic marker")
    assert_equals(naming.route_segment_to_fs("*"), "all", "route fs segment should convert wildcard")
    assert_equals(naming.route_segment_to_fs("   "), "index", "empty route fs segment should fall back to index")
    assert_equals(
        naming.route_segment_to_path("BlogPost"),
        "blog-post",
        "route path segment should kebab-case static names"
    )
    assert_equals(
        naming.route_segment_to_path(":postId"),
        ":postId",
        "route path segment should preserve dynamic marker"
    )
end)

--- Verifies project resolution for a repo-root web layout.
---
--- # Example Under Test
---
--- A temporary directory contains the default source, style, page, and app
--- paths directly at the root.
---
--- # Assertions
---
--- - Resolution returns no error.
--- - The resolved web root is the temporary root.
--- - Component and app paths point to the expected locations.
---
test("resolves repo-root layout", function()
    local root = path.join(temp_root, "repo-root")
    create_default_layout(root)
    reset(root)

    local paths, err = project.resolve({
        "components_dir",
        "styles_components_dir",
        "pages_dir",
        "page_styles_dir",
        "app_path",
    })

    assert_equals(err, nil, "repo-root layout should not return an error")
    assert_equals(paths.web_root, root, "repo-root web root should be the current root")
    assert_equals(paths.components_dir, path.join(root, "src", "components"), "components path should resolve")
    assert_equals(paths.app_path, path.join(root, "src", "app.rs"), "app path should resolve")
end)

--- Verifies project resolution for a nested `web` layout.
---
--- # Example Under Test
---
--- A temporary repository contains the default web layout inside a `web`
--- directory.
---
--- # Assertions
---
--- - Resolution returns no error.
--- - The resolved web root is the nested `web` directory.
--- - Required component paths resolve under the nested web root.
---
test("resolves nested web layout", function()
    local root = path.join(temp_root, "nested-web")
    local web_root = path.join(root, "web")
    create_default_layout(web_root)
    reset(root)

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(err, nil, "nested web layout should not return an error")
    assert_equals(paths.web_root, web_root, "nested web root should resolve")
    assert_equals(
        paths.components_dir,
        path.join(web_root, "src", "components"),
        "nested components path should resolve"
    )
end)

--- Verifies nested web layout precedence.
---
--- # Example Under Test
---
--- A temporary repository contains both root-level and nested `web` layouts.
---
--- # Assertions
---
--- - The nested `web` layout is selected before the repo-root layout.
---
--- # Why
---
--- Repositories may contain support files at the root while the application
--- lives in `web`.
---
test("prefers nested web layout over repo-root layout", function()
    local root = path.join(temp_root, "layout-precedence")
    local web_root = path.join(root, "web")
    create_default_layout(root)
    create_default_layout(web_root)
    reset(root)

    local paths = assert(project.resolve({ "components_dir", "app_path" }))

    assert_equals(paths.web_root, web_root, "nested web layout should be checked first")
end)

--- Verifies configured path overrides are merged with defaults.
---
--- # Example Under Test
---
--- Plugin setup overrides the component and app paths while leaving other
--- paths unspecified.
---
--- # Assertions
---
--- - Resolution returns no error.
--- - Overridden paths resolve to configured locations.
--- - Unspecified paths still use default values.
---
test("merges configured path overrides", function()
    local root = path.join(temp_root, "overrides")
    reset(root)

    mkdir(path.join(root, "ui", "components"))
    write_file(path.join(root, "app", "main.rs"), { "fn main() {}" })

    plugin.setup({
        paths = {
            components_dir = "ui/components",
            app_path = "app/main.rs",
        },
    })

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(err, nil, "configured layout should not return an error")
    assert_equals(paths.components_dir, path.join(root, "ui", "components"), "components override should resolve")
    assert_equals(paths.app_path, path.join(root, "app", "main.rs"), "app override should resolve")
    assert_equals(paths.pages_dir, path.join(root, "src", "pages"), "defaults should remain merged")
end)

--- Verifies project resolution diagnostics for missing required paths.
---
--- # Example Under Test
---
--- A temporary root has no required component or app paths.
---
--- # Assertions
---
--- - Resolution returns nil paths.
--- - The warning names the missing required labels.
--- - The warning describes both supported layout shapes.
---
--- # Why
---
--- User-facing project discovery warnings should point at actionable missing
--- paths.
---
test("returns clear warning for missing required paths", function()
    local root = path.join(temp_root, "missing-required")
    mkdir(root)
    reset(root)

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(paths, nil, "missing required paths should not resolve")
    assert_match(
        err,
        "Could not locate web project paths for src/app.rs, src/components.",
        "warning should name missing labels"
    )
    assert_match(
        err,
        "Expected either ./web/... from the repo root or ./... from the web root.",
        "warning should describe supported layouts"
    )
end)

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

--- Verifies SCSS forward mutations and nested forward chains.
---
--- # Example Under Test
---
--- An SCSS index starts with one forward, then a nested pages chain is created.
---
--- # Assertions
---
--- - New forwards are added once.
--- - Replacements update or add the requested target.
--- - Removed forwards disappear and missing forwards are ignored.
--- - The touched tracker records each changed index once.
--- - Nested indexes forward from root to child to leaf target.
---
test("scss helpers update forwards and forward chains", function()
    local root = path.join(temp_root, "scss-forwards")
    local index_path = path.join(root, "styles", "components", "index.scss")
    local tracker = touch.new()
    write_file(index_path, {
        '@forward "existing";',
    })

    assert_equals(scss.ensure_forward(index_path, "buttons", tracker), true, "forward should be added")
    assert_equals(scss.ensure_forward(index_path, "buttons", tracker), false, "forward should not duplicate")
    assert_equals(scss.replace_forward(index_path, "existing", "base", tracker), true, "forward should be replaced")
    assert_equals(
        scss.replace_forward(index_path, "missing", "layout", tracker),
        true,
        "missing forward should be added"
    )
    assert_equals(scss.remove_forward(index_path, "buttons", tracker), true, "forward should be removed")
    assert_equals(scss.remove_forward(index_path, "buttons", tracker), false, "missing forward should not change file")

    assert_list_equals(fs.read_lines(index_path), {
        '@forward "base";',
        '@forward "layout";',
    }, "forward mutations should produce expected index")

    local spaced_index_path = path.join(root, "styles", "components", "spaced.scss")
    write_file(spaced_index_path, {
        '  @forward   "existing"  ;',
        '@forward   "base"  ;',
    })

    assert_equals(
        scss.replace_forward(spaced_index_path, "existing", "base"),
        true,
        "replace_forward should parse whitespace-tolerant forwards"
    )
    assert_list_equals(fs.read_lines(spaced_index_path), {
        '@forward   "base"  ;',
    }, "replace_forward should not duplicate an existing target with spacing")

    assert_list_equals(tracker:paths(), {
        index_path,
    }, "tracker should record changed index once")

    local chain_root = path.join(root, "styles", "pages")
    local chain_tracker = touch.new()
    scss.ensure_forward_chain(chain_root, { "admin", "settings" }, "profile", chain_tracker)

    assert_list_equals(fs.read_lines(path.join(chain_root, "index.scss")), {
        '@forward "admin";',
    }, "root forward chain index should point to child")
    assert_list_equals(fs.read_lines(path.join(chain_root, "admin", "index.scss")), {
        '@forward "settings";',
    }, "nested forward chain index should point to child")
    assert_list_equals(fs.read_lines(path.join(chain_root, "admin", "settings", "index.scss")), {
        '@forward "profile";',
    }, "leaf forward chain index should point to target")
end)

--- Verifies Rust and SCSS empty-directory pruning.
---
--- # Example Under Test
---
--- Empty generated Rust and SCSS child directories each contain only an empty
--- marker file and have parent references.
---
--- # Assertions
---
--- - Empty child directories are deleted.
--- - Parent Rust module declarations and SCSS forwards are removed.
--- - Trackers record deleted marker files, directories, and updated parents.
---
--- # Why
---
--- Delete workflows should not leave empty generated directories or stale
--- parent references behind.
---
test("rust and scss helpers prune empty directories", function()
    local root = path.join(temp_root, "prune")
    local rust_root = path.join(root, "src", "pages")
    local rust_child = path.join(rust_root, "admin")
    local style_root = path.join(root, "styles", "pages")
    local style_child = path.join(style_root, "admin")

    write_file(path.join(rust_root, "mod.rs"), {
        "pub mod admin;",
        "pub use admin::AdminPage;",
    })
    write_file(path.join(rust_child, "mod.rs"), {})
    write_file(path.join(style_root, "index.scss"), {
        '@forward "admin";',
    })
    write_file(path.join(style_child, "index.scss"), {})

    local rust_tracker = touch.new()
    local style_tracker = touch.new()
    rust.prune_empty_dirs(rust_child, rust_root, rust_tracker)
    scss.prune_empty_dirs(style_child, style_root, style_tracker)

    assert_equals(fs.exists(rust_child), false, "empty rust directory should be removed")
    assert_equals(fs.exists(style_child), false, "empty style directory should be removed")
    assert_list_equals(fs.read_lines(path.join(rust_root, "mod.rs")), {}, "parent mod should remove empty child")
    assert_list_equals(fs.read_lines(path.join(style_root, "index.scss")), {}, "parent index should remove empty child")
    assert_list_equals(rust_tracker:paths(), {
        path.join(rust_child, "mod.rs"),
        rust_child,
        path.join(rust_root, "mod.rs"),
    }, "rust prune should track deleted child and updated parent")
    assert_list_equals(style_tracker:paths(), {
        path.join(style_child, "index.scss"),
        style_child,
        path.join(style_root, "index.scss"),
    }, "style prune should track deleted child and updated parent")
end)

--- Verifies touched-file tracking and formatting dispatch.
---
--- # Example Under Test
---
--- A touched-file tracker records Rust, SCSS, and text paths while formatting
--- is stubbed to avoid requiring an attached LSP formatter.
---
--- # Assertions
---
--- - First-seen paths are recorded in order.
--- - Duplicate paths are ignored.
--- - Only Rust and SCSS files are formatted.
--- - Formatting options are passed through unchanged.
---
test("touch helpers dedupe paths and dispatch format targets", function()
    local tracker = touch.new()
    local rust_path = path.join(temp_root, "touch", "component.rs")
    local scss_path = path.join(temp_root, "touch", "_component.scss")
    local text_path = path.join(temp_root, "touch", "notes.txt")

    assert_equals(tracker:mark(rust_path), true, "first rust mark should be recorded")
    assert_equals(tracker:mark(scss_path), true, "first scss mark should be recorded")
    assert_equals(tracker:mark(text_path), true, "first text mark should be recorded")
    assert_equals(tracker:mark(rust_path), false, "duplicate mark should be ignored")
    assert_list_equals(tracker:paths(), {
        rust_path,
        scss_path,
        text_path,
    }, "tracker should preserve first-seen order")

    local original_format_file = touch.format_file
    local formatted = {}
    touch.format_file = function(file_path, opts)
        table.insert(formatted, file_path .. ":" .. tostring(opts.timeout_ms))
        return true
    end

    local count = touch.format_touched(tracker, { timeout_ms = 25 })
    touch.format_file = original_format_file

    assert_equals(count, 2, "only rust and scss files should be formatted")
    assert_list_equals(formatted, {
        rust_path .. ":25",
        scss_path .. ":25",
    }, "format dispatch should preserve touched-file order")
end)

vim.fn.chdir(original_cwd)
vim.fn.delete(temp_root, "rf")
print(string.format("passed %d tests", passed))
