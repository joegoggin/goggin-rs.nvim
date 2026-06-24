--- Component picker and prompt workflows.
---
--- Coordinates project discovery, Telescope selection, subdirectory prompts,
--- and component generation prompts for user-facing component commands.

local collect = require("goggin-rs.components.collect")
local create = require("goggin-rs.components.create")
local fs = require("goggin-rs.infra.fs")
local naming = require("goggin-rs.naming")
local open = require("goggin-rs.components.open")
local project = require("goggin-rs.project")
local telescope_loader = require("goggin-rs.infra.telescope")

local M = {}

--- Prompts for an existing or new component subdirectory.
---
---@param paths table Resolved project paths.
---@param input_name string Raw component name input.
---
local function choose_subdirectory(paths, input_name)
    local options = fs.relative_subdirectories(paths.components_dir)
    table.insert(options, "+ Create new sub-directory")

    vim.ui.select(options, { prompt = "Select components sub-directory" }, function(choice)
        if not choice then
            return
        end

        if choice == "+ Create new sub-directory" then
            vim.ui.input({ prompt = "New sub-directory (relative to components): " }, function(new_path)
                if not new_path or naming.trim(new_path) == "" then
                    return
                end

                local normalized = naming.normalize_relative_dir(new_path)
                if normalized == "" then
                    open.notify_warn("Invalid sub-directory path.")
                    return
                end

                create.create({
                    input_name = input_name,
                    relative_dir = normalized,
                    paths = paths,
                    open = true,
                })
            end)
        else
            create.create({
                input_name = input_name,
                relative_dir = choice,
                paths = paths,
                open = true,
            })
        end
    end)
end

--- Opens a Telescope picker for existing components.
---
function M.pick()
    local paths = project.resolve_or_notify({ "components_dir" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.components_dir) then
        open.notify_warn("Components directory not found: " .. paths.components_dir)
        return
    end

    local telescope = telescope_loader.load()
    if not telescope then
        open.notify_warn("Telescope is required to pick components.")
        return
    end

    local components = collect.collect(paths)
    if #components == 0 then
        open.notify_warn("No Rust components found in " .. paths.components_dir)
        return
    end

    telescope.pickers
        .new({}, {
            prompt_title = "Open Component",
            finder = telescope.finders.new_table({
                results = components,
                entry_maker = function(component)
                    return {
                        value = component,
                        display = component.component_name .. "  " .. component.rust_relative,
                        ordinal = component.component_name .. " " .. component.rust_relative,
                    }
                end,
            }),
            sorter = telescope.config.values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                telescope.actions.select_default:replace(function()
                    local selection = telescope.action_state.get_selected_entry()
                    telescope.actions.close(prompt_bufnr)

                    if selection and selection.value then
                        open.open_pair(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

--- Prompts for a component name and creates a new component pair.
---
function M.generate()
    local paths = project.resolve_or_notify({ "components_dir", "styles_components_dir" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.components_dir) then
        open.notify_warn("Components directory not found: " .. paths.components_dir)
        return
    end

    if not fs.is_directory(paths.styles_components_dir) then
        open.notify_warn("Component styles directory not found: " .. paths.styles_components_dir)
        return
    end

    vim.ui.input({ prompt = "Component name: " }, function(input_name)
        if not input_name or naming.trim(input_name) == "" then
            return
        end

        vim.ui.select({ "No", "Yes" }, { prompt = "Nest component in a sub-directory?" }, function(choice)
            if not choice then
                return
            end

            if choice == "Yes" then
                choose_subdirectory(paths, input_name)
            else
                create.create({
                    input_name = input_name,
                    relative_dir = "",
                    paths = paths,
                    open = true,
                })
            end
        end)
    end)
end

return M
