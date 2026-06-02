local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local plugin = require("goggin-rs")
local fs = require("goggin-rs.fs")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.path")
local project = require("goggin-rs.project")

local temp_root = vim.fn.tempname()
local original_cwd = vim.fn.getcwd()
local passed = 0

local function mkdir(path)
    vim.fn.mkdir(path, "p")
end

local function write_file(path, lines)
    mkdir(vim.fn.fnamemodify(path, ":h"))
    vim.fn.writefile(lines or {}, path)
end

local function create_default_layout(web_root)
    mkdir(path.join(web_root, "src", "components"))
    mkdir(path.join(web_root, "styles", "components"))
    mkdir(path.join(web_root, "src", "pages"))
    mkdir(path.join(web_root, "styles", "pages"))
    write_file(path.join(web_root, "src", "app.rs"), { "fn main() {}" })
end

local function reset(root)
    plugin.setup({})
    vim.cmd("enew!")
    mkdir(root)
    vim.fn.chdir(root)
end

local function assert_equals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s\nexpected: %s\nactual:   %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_match(value, pattern, message)
    if not tostring(value):find(pattern, 1, true) then
        error(
            string.format("%s\nexpected to contain: %s\nactual:              %s", message, pattern, tostring(value)),
            2
        )
    end
end

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

test("prefers nested web layout over repo-root layout", function()
    local root = path.join(temp_root, "layout-precedence")
    local web_root = path.join(root, "web")
    create_default_layout(root)
    create_default_layout(web_root)
    reset(root)

    local paths = assert(project.resolve({ "components_dir", "app_path" }))

    assert_equals(paths.web_root, web_root, "nested web layout should be checked first")
end)

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

vim.fn.chdir(original_cwd)
vim.fn.delete(temp_root, "rf")
print(string.format("passed %d tests", passed))
