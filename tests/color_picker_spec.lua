--- SCSS color picker UI tests.
---
--- Verifies the Telescope-facing color picker entry formatting, preview buffer
--- rendering, copy behavior, and user-facing warning paths.

local h = require("tests.helpers")

local path = h.path
local scss = h.scss

local temp_root = h.temp_root
local create_default_layout = h.create_default_layout
local reset = h.reset
local write_file = h.write_file
local assert_equals = h.assert_equals
local assert_list_equals = h.assert_list_equals
local test = h.test

local TELESCOPE_MODULES = {
    "telescope.actions",
    "telescope.actions.state",
    "telescope.finders",
    "telescope.pickers",
    "telescope.previewers",
    "telescope.config",
}

--- Runs a callback with stubbed Telescope modules.
---
---@param fn fun(captured:table) Callback receiving captured Telescope state.
---
local function with_telescope_stub(fn)
    local saved_loaded = {}
    local saved_preload = {}
    local captured = {}

    for _, module_name in ipairs(TELESCOPE_MODULES) do
        saved_loaded[module_name] = package.loaded[module_name]
        saved_preload[module_name] = package.preload[module_name]
    end

    local stubs = {
        ["telescope.actions"] = {
            select_default = {
                replace = function(_, replacement)
                    captured.select_default = replacement
                end,
            },
            close = function(prompt_bufnr)
                captured.closed_prompt_bufnr = prompt_bufnr
            end,
        },
        ["telescope.actions.state"] = {
            get_selected_entry = function()
                return captured.selected_entry
            end,
        },
        ["telescope.finders"] = {
            new_table = function(opts)
                captured.finder_opts = opts
                return opts
            end,
        },
        ["telescope.pickers"] = {
            new = function(_, picker_opts)
                captured.picker_opts = picker_opts
                return {
                    find = function()
                        captured.find_called = true
                    end,
                }
            end,
        },
        ["telescope.previewers"] = {
            new_buffer_previewer = function(opts)
                captured.previewer_opts = opts
                return opts
            end,
        },
        ["telescope.config"] = {
            values = {
                generic_sorter = function(opts)
                    captured.sorter_opts = opts
                    return "sorter"
                end,
            },
        },
    }

    for module_name, stub in pairs(stubs) do
        package.loaded[module_name] = stub
        package.preload[module_name] = function()
            return stub
        end
    end

    local ok, err = xpcall(function()
        fn(captured)
    end, debug.traceback)

    for _, module_name in ipairs(TELESCOPE_MODULES) do
        package.loaded[module_name] = saved_loaded[module_name]
        package.preload[module_name] = saved_preload[module_name]
    end

    if not ok then
        error(err, 2)
    end
end

--- Runs a callback with Telescope module loading forced to fail.
---
---@param fn fun() Callback run while Telescope modules fail to load.
---
local function with_missing_telescope(fn)
    local saved_loaded = {}
    local saved_preload = {}

    for _, module_name in ipairs(TELESCOPE_MODULES) do
        saved_loaded[module_name] = package.loaded[module_name]
        saved_preload[module_name] = package.preload[module_name]
        package.loaded[module_name] = nil
        package.preload[module_name] = function()
            error("missing " .. module_name)
        end
    end

    local ok, err = xpcall(fn, debug.traceback)

    for _, module_name in ipairs(TELESCOPE_MODULES) do
        package.loaded[module_name] = saved_loaded[module_name]
        package.preload[module_name] = saved_preload[module_name]
    end

    if not ok then
        error(err, 2)
    end
end

--- Runs a callback while capturing notifications.
---
---@param fn fun(notifications:table[]) Callback receiving captured notifications.
---
local function with_notifications(fn)
    local original_notify = vim.notify
    local notifications = {}

    vim.notify = function(message, level)
        table.insert(notifications, {
            message = message,
            level = level,
        })
    end

    local ok, err = xpcall(function()
        fn(notifications)
    end, debug.traceback)

    vim.notify = original_notify

    if not ok then
        error(err, 2)
    end
end

--- Finds a collected color by name.
---
---@param colors table[] Color entries.
---@param name string Color variable name.
---@return table|nil color Matching color entry.
---
local function find_color(colors, name)
    for _, color in ipairs(colors) do
        if color.name == name then
            return color
        end
    end

    return nil
end

--- Verifies the resolved and unresolved color previews.
---
---@param previewer table Telescope previewer.
---@param color table Color entry.
---@return string[] lines Preview buffer lines.
---@return table[] highlights Preview namespace extmarks.
---
local function render_preview(previewer, color)
    local bufnr = vim.api.nvim_create_buf(false, true)

    previewer.define_preview({ state = { bufnr = bufnr } }, {
        value = color,
    })

    local namespace = vim.api.nvim_get_namespaces().goggin_telescope_color_picker
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
end

--- Verifies picker entry formatting, preview rendering, and copy behavior.
---
--- # Example Under Test
---
--- A default project contains `_colors.scss` entries for resolved colors and an
--- unresolved CSS variable, while Telescope and notifications are stubbed.
---
--- # Assertions
---
--- - Picker entries preserve collected color sorting and historical display text.
--- - Preview buffers render a 28x12 swatch plus the expected metadata lines.
--- - Resolved colors receive swatch highlights; unresolved colors do not.
--- - Selecting an entry copies to `+`, or falls back to the unnamed register.
---
test("scss color picker renders entries previews and copy actions", function()
    local root = path.join(temp_root, "color-picker")
    create_default_layout(root)
    reset(root)

    write_file(path.join(root, "_colors.scss"), {
        "$z-color: #000000;",
        "$brand-color: rgb(1, 2, 3);",
        "$missing-color: rgba(var(--color-missing-rgb), 0.5);",
    })

    with_telescope_stub(function(captured)
        with_notifications(function(notifications)
            scss.pick_colors()

            assert_equals(captured.find_called, true, "picker should be opened")
            assert_equals(captured.picker_opts.prompt_title, "SCSS Colors", "prompt title should match source behavior")
            assert_equals(captured.picker_opts.sorter, "sorter", "generic sorter should be configured")
            assert_equals(captured.previewer_opts.title, "Color Preview", "preview title should match source behavior")

            local results = captured.finder_opts.results
            assert_list_equals(
                { results[1].name, results[2].name, results[3].name },
                { "$brand-color", "$missing-color", "$z-color" },
                "picker results should keep collected sorting"
            )

            local entry = captured.finder_opts.entry_maker(results[1])
            assert_equals(entry.value, results[1], "entry value should be the color table")
            assert_equals(
                entry.display,
                "$brand-color  rgb(1, 2, 3)",
                "entry display should include name and display value"
            )
            assert_equals(
                entry.ordinal,
                "$brand-color rgb(1, 2, 3) rgb(1, 2, 3)",
                "entry ordinal should include searchable name and values"
            )

            local resolved_lines, resolved_highlights = render_preview(captured.picker_opts.previewer, results[1])
            assert_equals(#resolved_lines, 17, "resolved preview should include swatch and metadata")
            assert_equals(resolved_lines[14], "Variable: $brand-color", "preview should include color name")
            assert_equals(resolved_lines[15], "Value: rgb(1, 2, 3)", "preview should include raw value")
            assert_equals(resolved_lines[16], "Preview: rgb(1, 2, 3)", "preview should include resolved value")
            assert_equals(
                resolved_lines[17],
                "Source: _colors.scss:2",
                "preview should include source-relative path and line"
            )
            assert_equals(#resolved_highlights, 12, "resolved swatch should highlight each swatch line")
            assert_equals(
                vim.fn.hlexists("GogginTelescopeColorPicker010203"),
                1,
                "preview should create a hex-specific highlight group"
            )

            local unresolved = assert(find_color(results, "$missing-color"))
            local unresolved_lines, unresolved_highlights = render_preview(captured.picker_opts.previewer, unresolved)
            assert_equals(unresolved_lines[16], "Preview: unresolved", "unresolved color preview should say unresolved")
            assert_equals(#unresolved_highlights, 0, "unresolved swatch should not create highlights")

            local original_setreg = vim.fn.setreg
            local setreg_calls = {}
            vim.fn.setreg = function(register, value)
                table.insert(setreg_calls, register .. ":" .. value)
            end

            captured.selected_entry = { value = results[1] }
            assert_equals(captured.picker_opts.attach_mappings(42), true, "attach_mappings should allow defaults")
            captured.select_default()

            assert_list_equals(setreg_calls, { "+:$brand-color" }, "selection should copy to the system clipboard")
            assert_equals(captured.closed_prompt_bufnr, 42, "selection should close the picker")
            assert_equals(notifications[1].message, "Copied $brand-color", "successful copy should notify")

            setreg_calls = {}
            vim.fn.setreg = function(register, value)
                if register == "+" then
                    error("clipboard unavailable")
                end

                table.insert(setreg_calls, register .. ":" .. value)
            end

            captured.select_default()
            vim.fn.setreg = original_setreg

            assert_list_equals(setreg_calls, { '":$brand-color' }, "selection should fall back to unnamed register")
            assert_equals(
                notifications[2].message,
                "Copied $brand-color to the unnamed register; system clipboard unavailable.",
                "fallback copy should notify"
            )
            assert_equals(notifications[2].level, vim.log.levels.WARN, "fallback copy should warn")
        end)
    end)
end)

--- Verifies warning paths before opening Telescope.
---
--- # Example Under Test
---
--- Picker setup is attempted with missing Telescope modules, no `_colors.scss`
--- files, and a color file containing no usable color variables.
---
--- # Assertions
---
--- - Missing Telescope warns and does not open a picker.
--- - Missing `_colors.scss` files warn and do not open a picker.
--- - `_colors.scss` files without color variables warn and do not open a picker.
---
test("scss color picker warns for unavailable picker inputs", function()
    local missing_telescope_root = path.join(temp_root, "color-picker-missing-telescope")
    create_default_layout(missing_telescope_root)
    reset(missing_telescope_root)
    write_file(path.join(missing_telescope_root, "_colors.scss"), {
        "$brand-color: #010203;",
    })

    with_missing_telescope(function()
        with_notifications(function(notifications)
            scss.pick_colors()
            assert_equals(
                notifications[1].message,
                "Telescope is required to pick SCSS colors.",
                "missing Telescope should warn"
            )
            assert_equals(notifications[1].level, vim.log.levels.WARN, "missing Telescope should use warning level")
        end)
    end)

    local no_files_root = path.join(temp_root, "color-picker-no-files")
    create_default_layout(no_files_root)
    reset(no_files_root)

    with_telescope_stub(function(captured)
        with_notifications(function(notifications)
            scss.pick_colors()
            assert_equals(
                notifications[1].message,
                "No _colors.scss file found under " .. no_files_root,
                "missing color files should warn"
            )
            assert_equals(captured.find_called, nil, "picker should not open without color files")
        end)
    end)

    local no_colors_root = path.join(temp_root, "color-picker-no-colors")
    create_default_layout(no_colors_root)
    reset(no_colors_root)
    write_file(path.join(no_colors_root, "_colors.scss"), {
        "$spacing: 1rem;",
    })

    with_telescope_stub(function(captured)
        with_notifications(function(notifications)
            scss.pick_colors()
            assert_equals(
                notifications[1].message,
                "No usable color variables found in _colors.scss.",
                "color files without usable colors should warn"
            )
            assert_equals(captured.find_called, nil, "picker should not open without usable colors")
        end)
    end)
end)
