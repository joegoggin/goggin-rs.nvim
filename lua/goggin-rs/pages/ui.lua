--- Page picker and prompt workflows.
---
--- Coordinates project discovery, Telescope selection, page creation prompts,
--- page-local component prompts, and picker entry actions.

local collect = require("goggin-rs.pages.collect")
local components = require("goggin-rs.pages.components")
local create = require("goggin-rs.pages.create")
local entries = require("goggin-rs.pages.entries")
local fs = require("goggin-rs.infra.fs")
local naming = require("goggin-rs.naming")
local open = require("goggin-rs.pages.open")
local path = require("goggin-rs.infra.path")
local project = require("goggin-rs.project")
local telescope_loader = require("goggin-rs.infra.telescope")

local M = {}

--- Collects existing page subdirectories for the generation prompt.
---
---@param paths table Resolved project paths.
---@return string[] directories Relative page directories.
---
local function collect_page_subdirectories(paths)
    local results = {}

    for _, relative in ipairs(fs.relative_subdirectories(paths.pages_dir)) do
        local is_components_path = relative == "components"
            or relative:match("^components/")
            or relative:match("/components$")
            or relative:match("/components/")

        if not is_components_path then
            table.insert(results, relative)
        end
    end

    return results
end

--- Prompts for an existing or new page subdirectory.
---
---@param paths table Resolved project paths.
---@param on_select fun(relative_dir:string) Callback invoked with the selected relative directory.
---
local function choose_page_subdirectory(paths, on_select)
    local options = collect_page_subdirectories(paths)
    table.insert(options, "+ Create new sub-directory")

    vim.ui.select(options, { prompt = "Select page sub-directory" }, function(choice)
        if not choice then
            return
        end

        if choice == "+ Create new sub-directory" then
            vim.ui.input({ prompt = "New sub-directory (relative to pages): " }, function(new_dir)
                if not new_dir or naming.trim(new_dir) == "" then
                    return
                end

                local normalized = naming.normalize_relative_dir(new_dir)
                if normalized == "" then
                    open.notify_warn("Invalid sub-directory.")
                    return
                end

                on_select(normalized)
            end)
        else
            on_select(choice)
        end
    end)
end

--- Prompts for an existing or new page-local component subdirectory.
---
---@param page table Page entry from `collect`.
---@param on_select fun(relative_dir:string) Callback invoked with the selected relative directory.
---
local function choose_page_component_subdirectory(page, on_select)
    local base_dir = path.join(page.page_dir, "components")
    fs.ensure_directory(base_dir)

    local options = fs.relative_subdirectories(base_dir)
    table.insert(options, "+ Create new sub-directory")

    vim.ui.select(options, { prompt = "Select page components sub-directory" }, function(choice)
        if not choice then
            return
        end

        if choice == "+ Create new sub-directory" then
            vim.ui.input({ prompt = "New sub-directory (relative to page components): " }, function(new_dir)
                if not new_dir or naming.trim(new_dir) == "" then
                    return
                end

                local normalized = naming.normalize_relative_dir(new_dir)
                if normalized == "" then
                    open.notify_warn("Invalid sub-directory.")
                    return
                end

                on_select(normalized)
            end)
        else
            on_select(choice)
        end
    end)
end

--- Prompts for page route metadata and creates a page pair.
---
---@param paths table Resolved project paths.
---
local function prompt_create_page(paths)
    vim.ui.input({ prompt = "Route: " }, function(route_value)
        if not route_value or naming.trim(route_value) == "" then
            return
        end

        vim.ui.select({ "Private", "Public" }, { prompt = "Route visibility" }, function(visibility)
            if not visibility then
                return
            end

            vim.ui.input({ prompt = "Page name (without Page): " }, function(page_name)
                if not page_name or naming.trim(page_name) == "" then
                    return
                end

                vim.ui.select({ "Flat", "Module" }, { prompt = "Page layout" }, function(layout)
                    if not layout then
                        return
                    end

                    local module_layout = layout == "Module"

                    vim.ui.select({ "No", "Yes" }, { prompt = "Nest page in a sub-directory?" }, function(choice)
                        if not choice then
                            return
                        end

                        if choice == "No" then
                            create.create({
                                route = route_value,
                                private = visibility == "Private",
                                page_name = page_name,
                                subroute = "",
                                module_layout = module_layout,
                                paths = paths,
                                open = true,
                            })
                        else
                            choose_page_subdirectory(paths, function(subroute)
                                create.create({
                                    route = route_value,
                                    private = visibility == "Private",
                                    page_name = page_name,
                                    subroute = subroute,
                                    module_layout = module_layout,
                                    paths = paths,
                                    open = true,
                                })
                            end)
                        end
                    end)
                end)
            end)
        end)
    end)
end

--- Loads Telescope modules required by page pickers.
---
---@return table|nil telescope Loaded Telescope dependencies.
---
local function load_telescope_for_pages()
    local telescope = telescope_loader.load()
    if not telescope then
        open.notify_warn("Telescope is required to pick pages.")
        return nil
    end

    return telescope
end

--- Prompts for a selected page and creates a page-local component.
---
---@param paths table Resolved project paths.
---
local function prompt_for_page_component_target(paths)
    local telescope = load_telescope_for_pages()
    if not telescope then
        return
    end

    local pages = collect.collect(paths)
    if #pages == 0 then
        open.notify_warn("No page components found in " .. paths.pages_dir)
        return
    end

    telescope.pickers
        .new({}, {
            prompt_title = "Select Page",
            finder = telescope.finders.new_table({
                results = pages,
                entry_maker = function(page)
                    return {
                        value = page,
                        display = page.display_name .. "  " .. page.rust_relative,
                        ordinal = page.display_name .. " " .. page.page_component_name .. " " .. page.rust_relative,
                    }
                end,
            }),
            sorter = telescope.config.values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                telescope.actions.select_default:replace(function()
                    local selection = telescope.action_state.get_selected_entry()
                    telescope.actions.close(prompt_bufnr)

                    if not selection or not selection.value then
                        return
                    end

                    local selected_page = selection.value

                    vim.schedule(function()
                        vim.ui.input({ prompt = "Component name (e.g. Workflow): " }, function(component_input)
                            if not component_input or naming.trim(component_input) == "" then
                                return
                            end

                            vim.ui.select(
                                { "No", "Yes" },
                                { prompt = "Nest component in a sub-directory?" },
                                function(choice)
                                    if not choice then
                                        return
                                    end

                                    if choice == "No" then
                                        components.create_component({
                                            page = selected_page,
                                            input_name = component_input,
                                            relative_dir = "",
                                            paths = paths,
                                            open = true,
                                        })
                                    else
                                        choose_page_component_subdirectory(selected_page, function(relative_dir)
                                            components.create_component({
                                                page = selected_page,
                                                input_name = component_input,
                                                relative_dir = relative_dir,
                                                paths = paths,
                                                open = true,
                                            })
                                        end)
                                    end
                                end
                            )
                        end)
                    end)
                end)

                return true
            end,
        })
        :find()
end

--- Opens or prompts for entries inside a selected page.
---
---@param page table Page entry from `collect`.
---@param paths table Resolved project paths.
---@param telescope table Telescope dependency table.
---
local function pick_page_entries(page, paths, telescope)
    local page_entries = entries.collect_entries(page, paths)

    if #page_entries == 1 and page_entries[1].entry_type == "page" then
        open.open_pair(page_entries[1])
        return
    end

    telescope.pickers
        .new({}, {
            prompt_title = "Open Page Component: " .. page.display_name,
            finder = telescope.finders.new_table({
                results = page_entries,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry.label .. "  " .. entry.rust_relative,
                        ordinal = entry.label .. " " .. entry.rust_relative,
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

--- Opens a Telescope picker for existing pages.
---
function M.pick()
    local paths = project.resolve_or_notify({ "pages_dir" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.pages_dir) then
        open.notify_warn("Pages directory not found: " .. paths.pages_dir)
        return
    end

    local telescope = load_telescope_for_pages()
    if not telescope then
        return
    end

    local pages = collect.collect(paths)
    if #pages == 0 then
        open.notify_warn("No page components found in " .. paths.pages_dir)
        return
    end

    telescope.pickers
        .new({}, {
            prompt_title = "Open Page",
            finder = telescope.finders.new_table({
                results = pages,
                entry_maker = function(page)
                    return {
                        value = page,
                        display = page.display_name .. "  " .. page.rust_relative,
                        ordinal = page.display_name .. " " .. page.page_component_name .. " " .. page.relative_dir,
                    }
                end,
            }),
            sorter = telescope.config.values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                telescope.actions.select_default:replace(function()
                    local selection = telescope.action_state.get_selected_entry()
                    telescope.actions.close(prompt_bufnr)

                    if selection and selection.value then
                        pick_page_entries(selection.value, paths, telescope)
                    end
                end)

                return true
            end,
        })
        :find()
end

--- Prompts for a page route and creates a new page pair.
---
function M.generate()
    local paths = project.resolve_or_notify({ "pages_dir", "page_styles_dir" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.pages_dir) then
        open.notify_warn("Pages directory not found: " .. paths.pages_dir)
        return
    end

    if not fs.is_directory(paths.page_styles_dir) then
        open.notify_warn("Page styles directory not found: " .. paths.page_styles_dir)
        return
    end

    vim.ui.select(
        { "Create Page", "Create Page Component" },
        { prompt = "What would you like to create?" },
        function(choice)
            if not choice then
                return
            end

            if choice == "Create Page" then
                if not fs.exists(paths.app_path) then
                    open.notify_warn("App file not found: " .. paths.app_path)
                    return
                end

                prompt_create_page(paths)
            else
                prompt_for_page_component_target(paths)
            end
        end
    )
end

return M
