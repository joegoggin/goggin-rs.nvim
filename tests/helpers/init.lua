--- Shared headless test helpers for goggin-rs.nvim.
---
--- Sets up package paths, fixture roots, module shortcuts, assertions, and
--- formatting stubs used by the headless Lua test suite.

local H = {}

H.repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
package.path = H.repo_root
    .. "/?.lua;"
    .. H.repo_root
    .. "/?/init.lua;"
    .. H.repo_root
    .. "/lua/?.lua;"
    .. H.repo_root
    .. "/lua/?/init.lua;"
    .. package.path

H.component = require("goggin-rs.components")
H.page = require("goggin-rs.pages")
H.plugin = require("goggin-rs")
H.fs = require("goggin-rs.infra.fs")
H.naming = require("goggin-rs.naming")
H.path = require("goggin-rs.infra.path")
H.project = require("goggin-rs.project")
H.rust = require("goggin-rs.rust")
H.scss = require("goggin-rs.scss")
H.styles = require("goggin-rs.styles")
H.touch = require("goggin-rs.infra.touch")

H.temp_root = vim.fn.tempname()
H.original_cwd = vim.fn.getcwd()
H.passed = 0

--- Creates a directory and missing parents.
---
---@param directory string Directory path to create.
---
function H.mkdir(directory)
    vim.fn.mkdir(directory, "p")
end

--- Writes lines to a file, creating the parent directory first.
---
---@param file_path string File path to write.
---@param lines string[]|nil Lines to write, or an empty file when nil.
---
function H.write_file(file_path, lines)
    H.mkdir(vim.fn.fnamemodify(file_path, ":h"))
    vim.fn.writefile(lines or {}, file_path)
end

--- Creates the default web project layout expected by project resolution.
---
---@param web_root string Directory that should contain web project paths.
---
function H.create_default_layout(web_root)
    H.mkdir(H.path.join(web_root, "src", "components"))
    H.mkdir(H.path.join(web_root, "styles", "components"))
    H.mkdir(H.path.join(web_root, "src", "pages"))
    H.mkdir(H.path.join(web_root, "styles", "pages"))
    H.write_file(H.path.join(web_root, "src", "app.rs"), { "fn main() {}" })
end

--- Resets plugin state and Neovim cwd for a test fixture.
---
---@param root string Directory to make the current working directory.
---
function H.reset(root)
    H.plugin.setup({})
    vim.cmd("enew!")
    H.mkdir(root)
    vim.fn.chdir(root)
end

--- Asserts that two scalar values are equal.
---
---@param actual any Actual value.
---@param expected any Expected value.
---@param message string Failure message.
---
function H.assert_equals(actual, expected, message)
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
function H.assert_match(value, pattern, message)
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
function H.assert_list_equals(actual, expected, message)
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
function H.test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)

    if not ok then
        io.stderr:write(string.format("not ok - %s\n%s\n", name, err))
        H.finish(1)
    end

    H.passed = H.passed + 1
    print("ok - " .. name)
end

--- Runs a function while stubbing touched-file formatting.
---
---@param fn fun(formatted: string[])
---
function H.with_stubbed_format(fn)
    local original_format_file = H.touch.format_file
    local formatted = {}

    rawset(H.touch, "format_file", function(file_path, opts)
        table.insert(formatted, file_path .. ":" .. tostring(opts and opts.timeout_ms))
        return true
    end)

    local ok, err = xpcall(function()
        fn(formatted)
    end, debug.traceback)

    rawset(H.touch, "format_file", original_format_file)

    if not ok then
        error(err, 2)
    end
end

--- Cleans up test state and exits when requested.
---
---@param exit_code integer|nil Exit code to use, or nil to keep running.
---
function H.finish(exit_code)
    vim.fn.chdir(H.original_cwd)
    vim.fn.delete(H.temp_root, "rf")

    if exit_code then
        os.exit(exit_code)
    end
end

H.mkdir(H.temp_root)

return H
