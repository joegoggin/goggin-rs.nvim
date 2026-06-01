local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = repo_root .. "/lua/?.lua;" .. repo_root .. "/lua/?/init.lua;" .. package.path

local plugin = require("goggin-rs")
local project = require("goggin-rs.project")

local temp_root = vim.fn.tempname()
local original_cwd = vim.fn.getcwd()
local passed = 0

local function path_join(...)
    local parts = {}

    for _, part in ipairs({ ... }) do
        if part and part ~= "" then
            table.insert(parts, part)
        end
    end

    return table.concat(parts, "/")
end

local function mkdir(path)
    vim.fn.mkdir(path, "p")
end

local function write_file(path, lines)
    mkdir(vim.fn.fnamemodify(path, ":h"))
    vim.fn.writefile(lines or {}, path)
end

local function create_default_layout(web_root)
    mkdir(path_join(web_root, "src", "components"))
    mkdir(path_join(web_root, "styles", "components"))
    mkdir(path_join(web_root, "src", "pages"))
    mkdir(path_join(web_root, "styles", "pages"))
    write_file(path_join(web_root, "src", "app.rs"), { "fn main() {}" })
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
        error(string.format("%s\nexpected to contain: %s\nactual:              %s", message, pattern, tostring(value)), 2)
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

test("resolves repo-root layout", function()
    local root = path_join(temp_root, "repo-root")
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
    assert_equals(paths.components_dir, path_join(root, "src", "components"), "components path should resolve")
    assert_equals(paths.app_path, path_join(root, "src", "app.rs"), "app path should resolve")
end)

test("resolves nested web layout", function()
    local root = path_join(temp_root, "nested-web")
    local web_root = path_join(root, "web")
    create_default_layout(web_root)
    reset(root)

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(err, nil, "nested web layout should not return an error")
    assert_equals(paths.web_root, web_root, "nested web root should resolve")
    assert_equals(paths.components_dir, path_join(web_root, "src", "components"), "nested components path should resolve")
end)

test("prefers nested web layout over repo-root layout", function()
    local root = path_join(temp_root, "layout-precedence")
    local web_root = path_join(root, "web")
    create_default_layout(root)
    create_default_layout(web_root)
    reset(root)

    local paths = assert(project.resolve({ "components_dir", "app_path" }))

    assert_equals(paths.web_root, web_root, "nested web layout should be checked first")
end)

test("merges configured path overrides", function()
    local root = path_join(temp_root, "overrides")
    reset(root)

    mkdir(path_join(root, "ui", "components"))
    write_file(path_join(root, "app", "main.rs"), { "fn main() {}" })

    plugin.setup({
        paths = {
            components_dir = "ui/components",
            app_path = "app/main.rs",
        },
    })

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(err, nil, "configured layout should not return an error")
    assert_equals(paths.components_dir, path_join(root, "ui", "components"), "components override should resolve")
    assert_equals(paths.app_path, path_join(root, "app", "main.rs"), "app override should resolve")
    assert_equals(paths.pages_dir, path_join(root, "src", "pages"), "defaults should remain merged")
end)

test("returns clear warning for missing required paths", function()
    local root = path_join(temp_root, "missing-required")
    mkdir(root)
    reset(root)

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(paths, nil, "missing required paths should not resolve")
    assert_match(err, "Could not locate web project paths for src/app.rs, src/components.", "warning should name missing labels")
    assert_match(err, "Expected either ./web/... from the repo root or ./... from the web root.", "warning should describe supported layouts")
end)

vim.fn.chdir(original_cwd)
vim.fn.delete(temp_root, "rf")
print(string.format("passed %d tests", passed))
