--- SCSS color picker workflows.
---
--- Provides the Telescope UI for collected SCSS color variables, including
--- swatch previews and copy-on-select behavior.

local colors = require("goggin-rs.scss.colors")
local telescope_loader = require("goggin-rs.infra.telescope")

local M = {}

local PREVIEW_NS = vim.api.nvim_create_namespace("goggin_telescope_color_picker")
local SQUARE_WIDTH = 28
local SQUARE_HEIGHT = 12

--- Shows a warning notification.
---
---@param message string Message to display.
---
local function notify_warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

--- Builds the preview buffer lines for a color entry.
---
---@param color table Color entry.
---@return string[] lines Preview buffer lines.
---
local function preview_lines(color)
    local lines = {}

    for _ = 1, SQUARE_HEIGHT do
        table.insert(lines, string.rep(" ", SQUARE_WIDTH))
    end

    table.insert(lines, "")
    table.insert(lines, "Variable: " .. color.name)
    table.insert(lines, "Value: " .. color.raw_value)

    if color.resolved_value then
        table.insert(lines, "Preview: " .. color.resolved_value)
    else
        table.insert(lines, "Preview: unresolved")
    end

    table.insert(lines, "Source: " .. color.source_relative .. ":" .. color.line_number)

    return lines
end

--- Creates a Telescope entry for a color.
---
---@param color table Color entry.
---@return table entry Telescope entry.
---
local function make_entry(color)
    return {
        value = color,
        display = color.name .. "  " .. color.display_value,
        ordinal = color.name .. " " .. color.raw_value .. " " .. color.display_value,
    }
end

--- Creates the color previewer.
---
---@param telescope table Loaded Telescope dependencies.
---@return table previewer Telescope buffer previewer.
---
local function color_previewer(telescope)
    return telescope.previewers.new_buffer_previewer({
        title = "Color Preview",
        define_preview = function(self, entry)
            local color = entry.value
            local bufnr = self.state.bufnr

            vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
            vim.api.nvim_buf_clear_namespace(bufnr, PREVIEW_NS, 0, -1)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preview_lines(color))
            vim.api.nvim_set_option_value("filetype", "scss", { buf = bufnr })

            if color.hex then
                local group = "GogginTelescopeColorPicker" .. color.hex:gsub("#", "")
                vim.api.nvim_set_hl(0, group, { bg = color.hex })

                for line = 0, SQUARE_HEIGHT - 1 do
                    vim.api.nvim_buf_add_highlight(bufnr, PREVIEW_NS, group, line, 0, SQUARE_WIDTH)
                end
            end

            vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
        end,
    })
end

--- Copies the selected color name to the system clipboard when available.
---
---@param color table Color entry.
---
local function copy_color_name(color)
    local ok = pcall(vim.fn.setreg, "+", color.name)
    if ok then
        vim.notify("Copied " .. color.name)
        return
    end

    vim.fn.setreg('"', color.name)
    vim.notify(
        "Copied " .. color.name .. " to the unnamed register; system clipboard unavailable.",
        vim.log.levels.WARN
    )
end

--- Opens the SCSS color picker.
---
function M.pick()
    local paths, err = colors.resolve_color_paths()
    if not paths then
        notify_warn(err or "Could not locate web project paths.")
        return
    end

    local telescope = telescope_loader.load()
    if not telescope then
        notify_warn("Telescope is required to pick SCSS colors.")
        return
    end

    local collected_colors, color_files = colors.collect_colors(paths)
    if #color_files == 0 then
        notify_warn("No _colors.scss file found under " .. paths.web_root)
        return
    end

    if #collected_colors == 0 then
        notify_warn("No usable color variables found in _colors.scss.")
        return
    end

    telescope.pickers
        .new({}, {
            prompt_title = "SCSS Colors",
            finder = telescope.finders.new_table({
                results = collected_colors,
                entry_maker = make_entry,
            }),
            sorter = telescope.config.values.generic_sorter({}),
            previewer = color_previewer(telescope),
            attach_mappings = function(prompt_bufnr)
                telescope.actions.select_default:replace(function()
                    local selection = telescope.action_state.get_selected_entry()
                    telescope.actions.close(prompt_bufnr)

                    if selection and selection.value then
                        copy_color_name(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

return M
