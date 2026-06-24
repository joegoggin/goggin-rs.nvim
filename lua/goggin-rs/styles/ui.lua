--- Style picker workflows.
---
--- Provides Telescope add/delete flows for missing and existing styles.

local collect = require("goggin-rs.styles.collect")
local create = require("goggin-rs.styles.create")
local fs = require("goggin-rs.infra.fs")
local project = require("goggin-rs.project")
local telescope_loader = require("goggin-rs.infra.telescope")

local M = {}

--- Shows a warning notification.
---
---@param message string Message to display.
---
local function notify_warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

--- Checks that all source and style roots required by style workflows exist.
---
---@param paths table Resolved project paths.
---@return boolean ok Whether required directories exist.
---
local function ensure_required_directories(paths)
    if not fs.is_directory(paths.components_dir) or not fs.is_directory(paths.pages_dir) then
        notify_warn("Component or page directories were not found.")
        return false
    end

    if not fs.is_directory(paths.styles_components_dir) or not fs.is_directory(paths.page_styles_dir) then
        notify_warn("Component or page style directories were not found.")
        return false
    end

    return true
end

--- Loads Telescope modules required by style pickers.
---
---@return table|nil telescope Loaded Telescope dependencies.
---
local function load_telescope_for_styles()
    local telescope = telescope_loader.load()
    if not telescope then
        notify_warn("Telescope is required to pick styles.")
        return nil
    end

    return telescope
end

--- Opens a style-item picker and invokes a callback on selection.
---
---@param prompt_title string Picker title.
---@param items table[] Style items.
---@param telescope table Telescope dependencies.
---@param on_select fun(item:table) Callback invoked with the selected style item.
---
local function pick_items(prompt_title, items, telescope, on_select)
    telescope.pickers
        .new({}, {
            prompt_title = prompt_title,
            finder = telescope.finders.new_table({
                results = items,
                entry_maker = function(item)
                    return {
                        value = item,
                        display = string.format(
                            "[%s] %s  %s",
                            item.kind_label,
                            item.component_name,
                            item.rust_relative
                        ),
                        ordinal = item.kind_label .. " " .. item.component_name .. " " .. item.rust_relative,
                    }
                end,
            }),
            sorter = telescope.config.values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                telescope.actions.select_default:replace(function()
                    local selection = telescope.action_state.get_selected_entry()
                    telescope.actions.close(prompt_bufnr)

                    if selection and selection.value then
                        on_select(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

--- Confirms and deletes an existing style item.
---
---@param item table Style item from `collect`.
---
local function confirm_delete(item)
    vim.ui.select({ "No", "Yes" }, { prompt = "Delete style for " .. item.component_name .. "?" }, function(choice)
        if choice == "Yes" then
            create.delete_style(item)
        end
    end)
end

--- Opens the add/delete style picker with mode-specific options.
---
---@param opts table Picker options.
---
local function pick_style_items(opts)
    local paths =
        project.resolve_or_notify({ "components_dir", "styles_components_dir", "pages_dir", "page_styles_dir" })
    if not paths or not ensure_required_directories(paths) then
        return
    end

    local telescope = load_telescope_for_styles()
    if not telescope then
        return
    end

    local items = collect.collect({ paths = paths, include_existing = opts.include_existing })
    if #items == 0 then
        notify_warn(opts.empty_message)
        return
    end

    pick_items(opts.prompt_title, items, telescope, opts.on_select)
end

--- Opens a Telescope picker for pages/components missing styles.
---
function M.pick()
    pick_style_items({
        prompt_title = "Add Missing Style",
        include_existing = false,
        empty_message = "No pages or components are missing styles.",
        on_select = function(item)
            create.create_missing_style(item, { open = true })
        end,
    })
end

--- Opens a Telescope picker for pages/components with existing styles.
---
function M.pick_delete()
    pick_style_items({
        prompt_title = "Delete Style",
        include_existing = true,
        empty_message = "No pages or components with styles were found.",
        on_select = confirm_delete,
    })
end

return M
