--- Public API compatibility tests.
---
--- Verifies legacy top-level require paths still load after the package
--- refactor and that the new infra package exposes focused helper modules.

local h = require("tests.helpers")

local assert_equals = h.assert_equals
local assert_list_equals = h.assert_list_equals
local test = h.test

local plugin = h.plugin

local telescope_extension_module = "telescope._extensions.goggin-rs"

local command_names = {
    "GogginRsPickComponent",
    "GogginRsGenerateComponent",
    "GogginRsPickPage",
    "GogginRsGeneratePage",
    "GogginRsAddStyle",
    "GogginRsDeleteStyle",
    "GogginRsPickColors",
}

local telescope_picker_names = {
    "pick_component",
    "generate_component",
    "pick_page",
    "generate_page",
    "add_style",
    "delete_style",
    "pick_colors",
}

--- Checks whether a user command is currently registered.
---
---@param name string User command name.
---@return boolean exists Whether the command exists.
---
local function command_exists(name)
    return vim.fn.exists(":" .. name) == 2
end

--- Runs a callback with a stubbed Telescope extension registrar.
---
---@param fn fun(extension:table) Callback receiving the loaded extension module.
---
local function with_telescope_extension_stub(fn)
    local saved_telescope = package.loaded.telescope
    local saved_telescope_preload = package.preload.telescope
    local saved_extension = package.loaded[telescope_extension_module]
    local saved_extension_preload = package.preload[telescope_extension_module]
    local telescope = {}

    function telescope.register_extension(extension)
        return extension
    end

    package.loaded.telescope = telescope
    package.preload.telescope = function()
        return telescope
    end
    package.loaded[telescope_extension_module] = nil
    package.preload[telescope_extension_module] = nil

    local ok, err = xpcall(function()
        fn(require(telescope_extension_module))
    end, debug.traceback)

    package.loaded.telescope = saved_telescope
    package.preload.telescope = saved_telescope_preload
    package.loaded[telescope_extension_module] = saved_extension
    package.preload[telescope_extension_module] = saved_extension_preload

    if not ok then
        error(err, 2)
    end
end

--- Runs a callback while forcing the top-level Telescope module to fail.
---
---@param fn fun() Callback run while Telescope fails to load.
---
local function with_missing_telescope(fn)
    local saved_telescope = package.loaded.telescope
    local saved_telescope_preload = package.preload.telescope
    local saved_extension = package.loaded[telescope_extension_module]
    local saved_extension_preload = package.preload[telescope_extension_module]

    package.loaded.telescope = nil
    package.preload.telescope = function()
        error("missing telescope")
    end
    package.loaded[telescope_extension_module] = nil
    package.preload[telescope_extension_module] = nil

    local ok, err = xpcall(fn, debug.traceback)

    package.loaded.telescope = saved_telescope
    package.preload.telescope = saved_telescope_preload
    package.loaded[telescope_extension_module] = saved_extension
    package.preload[telescope_extension_module] = saved_extension_preload

    if not ok then
        error(err, 2)
    end
end

--- Verifies legacy top-level require paths re-export refactored modules.
---
--- # Example Under Test
---
--- Legacy `goggin-rs.*` require paths and the new package modules are loaded
--- in the same headless Neovim process.
---
--- # Assertions
---
--- - Legacy component, page, and infrastructure aliases return the refactored modules.
--- - The aggregate infrastructure package exposes focused helper modules.
--- - The SCSS package exposes the color picker workflow.
---
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

--- Verifies setup registers and disables workflow commands idempotently.
---
--- # Example Under Test
---
--- Plugin setup is called with commands disabled, then with a path override,
--- then repeatedly with defaults and commands disabled again.
---
--- # Assertions
---
--- - Disabled setup removes all public workflow commands.
--- - Default setup registers each command and preserves merged path config.
--- - Repeated setup keeps commands registered without duplication.
---
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

--- Verifies workflow commands dispatch to extracted module entrypoints.
---
--- # Example Under Test
---
--- Public `:GogginRs*` commands are executed after their target module actions
--- are replaced with recording callbacks.
---
--- # Assertions
---
--- - Every command invokes the expected component, page, style, or SCSS action.
--- - Command dispatch preserves the command order exercised by the test.
---
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

--- Verifies the Telescope extension exports workflow picker names.
---
--- # Example Under Test
---
--- The Telescope extension is loaded with a stubbed extension registrar.
---
--- # Assertions
---
--- - The extension registers an exports table.
--- - Every public picker and generator export is present.
--- - Each exported workflow value is callable.
---
test("telescope extension exports workflow picker names", function()
    with_telescope_extension_stub(function(extension)
        assert_equals(type(extension.exports), "table", "extension should register exports")

        for _, picker_name in ipairs(telescope_picker_names) do
            assert_equals(type(extension.exports[picker_name]), "function", picker_name .. " should be exported")
        end
    end)
end)

--- Verifies the Telescope extension dispatches lazily to workflow entrypoints.
---
--- # Example Under Test
---
--- Extension exports are invoked after their target module actions are replaced
--- with recording callbacks.
---
--- # Assertions
---
--- - Every Telescope export invokes the expected workflow action.
--- - Export dispatch preserves the picker order exercised by the test.
---
test("telescope extension dispatches lazily to workflow entrypoints", function()
    local modules = {
        ["goggin-rs.components"] = require("goggin-rs.components"),
        ["goggin-rs.pages"] = require("goggin-rs.pages"),
        ["goggin-rs.styles"] = require("goggin-rs.styles"),
        ["goggin-rs.scss"] = require("goggin-rs.scss"),
    }

    local cases = {
        { picker = "pick_component", module = "goggin-rs.components", action = "pick", marker = "components.pick" },
        {
            picker = "generate_component",
            module = "goggin-rs.components",
            action = "generate",
            marker = "components.generate",
        },
        { picker = "pick_page", module = "goggin-rs.pages", action = "pick", marker = "pages.pick" },
        { picker = "generate_page", module = "goggin-rs.pages", action = "generate", marker = "pages.generate" },
        { picker = "add_style", module = "goggin-rs.styles", action = "pick", marker = "styles.pick" },
        {
            picker = "delete_style",
            module = "goggin-rs.styles",
            action = "pick_delete",
            marker = "styles.pick_delete",
        },
        { picker = "pick_colors", module = "goggin-rs.scss", action = "pick_colors", marker = "scss.pick_colors" },
    }

    with_telescope_extension_stub(function(extension)
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
            for _, case in ipairs(cases) do
                extension.exports[case.picker]()
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
        }, "extension exports should invoke workflow callbacks")
    end)
end)

--- Verifies the Telescope extension reports actionable missing dependency errors.
---
--- # Example Under Test
---
--- The extension module is required while the top-level Telescope module is
--- stubbed to fail loading.
---
--- # Assertions
---
--- - Requiring the extension fails when Telescope is unavailable.
--- - The error message names `nvim-telescope/telescope.nvim`.
---
test("telescope extension reports actionable missing dependency errors", function()
    with_missing_telescope(function()
        local ok, err = pcall(require, telescope_extension_module)

        assert_equals(ok, false, "extension should fail without Telescope")
        assert_equals(
            tostring(err):find("requires nvim-telescope/telescope.nvim", 1, true) ~= nil,
            true,
            "missing Telescope error should name the dependency"
        )
    end)
end)
