--- Public API compatibility tests.
---
--- Verifies legacy top-level require paths still load after the package
--- refactor and that the new infra package exposes focused helper modules.

local h = require("tests.helpers")

local assert_equals = h.assert_equals
local assert_list_equals = h.assert_list_equals
local test = h.test

local plugin = h.plugin

local command_names = {
    "GogginRsPickComponent",
    "GogginRsGenerateComponent",
    "GogginRsPickPage",
    "GogginRsGeneratePage",
    "GogginRsAddStyle",
    "GogginRsDeleteStyle",
    "GogginRsPickColors",
}

--- Checks whether a user command is currently registered.
---
---@param name string User command name.
---@return boolean exists Whether the command exists.
---
local function command_exists(name)
    return vim.fn.exists(":" .. name) == 2
end

test("legacy top-level require paths re-export refactored modules", function()
    assert_equals(require("goggin-rs.component"), require("goggin-rs.components"), "component alias should load")
    assert_equals(require("goggin-rs.page"), require("goggin-rs.pages"), "page alias should load")
    assert_equals(require("goggin-rs.fs"), require("goggin-rs.infra.fs"), "fs alias should load")
    assert_equals(require("goggin-rs.lines"), require("goggin-rs.infra.lines"), "lines alias should load")
    assert_equals(require("goggin-rs.path"), require("goggin-rs.infra.path"), "path alias should load")
    assert_equals(require("goggin-rs.prune"), require("goggin-rs.infra.prune"), "prune alias should load")
    assert_equals(require("goggin-rs.telescope"), require("goggin-rs.infra.telescope"), "telescope alias should load")
    assert_equals(require("goggin-rs.touch"), require("goggin-rs.infra.touch"), "touch alias should load")
    assert_equals(type(require("goggin-rs.infra").fs.exists), "function", "infra package should expose helpers")
    assert_equals(type(require("goggin-rs.scss").pick_colors), "function", "scss package should expose color picker")
end)

test("setup registers workflow commands idempotently and supports disabling them", function()
    plugin.setup({ commands = { enabled = false } })

    for _, name in ipairs(command_names) do
        assert_equals(command_exists(name), false, name .. " should start disabled")
    end

    local active_config = plugin.setup({
        paths = {
            components_dir = "ui/components",
        },
    })

    assert_equals(active_config.commands.enabled, true, "commands should default to enabled")
    assert_equals(
        plugin.config().paths.components_dir,
        "ui/components",
        "path overrides should remain merged through setup"
    )
    assert_equals(plugin.config().paths.pages_dir, "src/pages", "path defaults should remain merged")

    for _, name in ipairs(command_names) do
        assert_equals(command_exists(name), true, name .. " should be registered")
    end

    plugin.setup({})

    for _, name in ipairs(command_names) do
        assert_equals(command_exists(name), true, name .. " should remain registered after repeated setup")
    end

    plugin.setup({ commands = { enabled = false } })

    for _, name in ipairs(command_names) do
        assert_equals(command_exists(name), false, name .. " should be removed when commands are disabled")
    end

    plugin.setup({})
end)

test("workflow commands dispatch to extracted module entrypoints", function()
    local modules = {
        ["goggin-rs.components"] = require("goggin-rs.components"),
        ["goggin-rs.pages"] = require("goggin-rs.pages"),
        ["goggin-rs.styles"] = require("goggin-rs.styles"),
        ["goggin-rs.scss"] = require("goggin-rs.scss"),
    }

    local cases = {
        {
            command = "GogginRsPickComponent",
            module = "goggin-rs.components",
            action = "pick",
            marker = "components.pick",
        },
        {
            command = "GogginRsGenerateComponent",
            module = "goggin-rs.components",
            action = "generate",
            marker = "components.generate",
        },
        { command = "GogginRsPickPage", module = "goggin-rs.pages", action = "pick", marker = "pages.pick" },
        {
            command = "GogginRsGeneratePage",
            module = "goggin-rs.pages",
            action = "generate",
            marker = "pages.generate",
        },
        { command = "GogginRsAddStyle", module = "goggin-rs.styles", action = "pick", marker = "styles.pick" },
        {
            command = "GogginRsDeleteStyle",
            module = "goggin-rs.styles",
            action = "pick_delete",
            marker = "styles.pick_delete",
        },
        {
            command = "GogginRsPickColors",
            module = "goggin-rs.scss",
            action = "pick_colors",
            marker = "scss.pick_colors",
        },
    }

    local originals = {}
    local called = {}

    for _, case in ipairs(cases) do
        local target = modules[case.module]
        local marker = case.marker

        originals[marker] = target[case.action]
        rawset(target, case.action, function()
            table.insert(called, marker)
        end)
    end

    local ok, err = xpcall(function()
        plugin.setup({})

        for _, case in ipairs(cases) do
            vim.cmd(case.command)
        end
    end, debug.traceback)

    for _, case in ipairs(cases) do
        rawset(modules[case.module], case.action, originals[case.marker])
    end

    if not ok then
        error(err, 2)
    end

    assert_list_equals(called, {
        "components.pick",
        "components.generate",
        "pages.pick",
        "pages.generate",
        "styles.pick",
        "styles.pick_delete",
        "scss.pick_colors",
    }, "commands should invoke their workflow callbacks")
end)
