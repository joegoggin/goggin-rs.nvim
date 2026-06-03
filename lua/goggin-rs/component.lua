--- Component picker and generator workflows.
---
--- Collects Leptos components, resolves paired SCSS partials, and creates new
--- component Rust/SCSS files while maintaining module and style indexes.

local fs = require("goggin-rs.fs")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.path")
local project = require("goggin-rs.project")
local rust = require("goggin-rs.rust")
local scss = require("goggin-rs.scss")
local touch = require("goggin-rs.touch")

local M = {}

--- Shows a warning notification when Neovim's notification API is available.
---
---@param message string Message to display.
---
local function notify_warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

--- Resolves project paths and warns when required paths are unavailable.
---
---@param required string[] Required project path keys.
---@return table|nil paths Resolved project paths.
---
local function resolve_paths(required)
    local paths, err = project.resolve(required)
    if not paths then
        notify_warn(err)
        return nil
    end

    return paths
end

--- Parses the first Leptos component function name from a Rust file.
---
---@param file_path string Rust file path.
---@return string|nil component_name Parsed component function name.
---
local function component_name_from_file(file_path)
    local awaiting_component_fn = false

    for _, line in ipairs(fs.read_lines(file_path)) do
        if line:match("^%s*#%s*%[%s*component%s*%]") then
            awaiting_component_fn = true
        elseif awaiting_component_fn then
            local component_name = line:match("^%s*pub%s+fn%s+([%w_]+)")
            if component_name then
                return component_name
            end

            local is_attribute = line:match("^%s*#") ~= nil
            local is_blank = line:match("^%s*$") ~= nil
            if not is_attribute and not is_blank then
                awaiting_component_fn = false
            end
        end
    end

    return nil
end

--- Returns the basename for a filesystem path.
---
---@param file_path string Path to inspect.
---@return string basename Final path component.
---
local function basename(file_path)
    return vim.fn.fnamemodify(file_path, ":t")
end

--- Resolves the paired SCSS partial for a component Rust file.
---
--- Direct partial names win first, then nested parent-prefixed names are
--- checked for compatibility with the source config behavior.
---
---@param rust_path string Component Rust file path.
---@param paths table Resolved project paths.
---@return string|nil scss_path Matching SCSS path when one exists.
---
function M.resolve_scss_path(rust_path, paths)
    if not paths or not paths.components_dir or not paths.styles_components_dir then
        return nil
    end

    local relative = path.relative(paths.components_dir, rust_path)
    if relative == rust_path then
        return nil
    end

    local relative_dir = vim.fn.fnamemodify(relative, ":h")
    if relative_dir == "." then
        relative_dir = ""
    end

    local stem = vim.fn.fnamemodify(relative, ":t:r")
    local kebab_stem = stem:gsub("_", "-")
    local base_dir = path.join(paths.styles_components_dir, relative_dir)

    local direct_match = path.join(base_dir, "_" .. kebab_stem .. ".scss")
    if fs.exists(direct_match) then
        return direct_match
    end

    if relative_dir ~= "" then
        local parent = vim.fn.fnamemodify(relative_dir, ":t"):gsub("_", "-")
        local prefixed_match = path.join(base_dir, "_" .. parent .. "-" .. kebab_stem .. ".scss")

        if fs.exists(prefixed_match) then
            return prefixed_match
        end
    end

    return nil
end

--- Collects Leptos components under the configured component root.
---
---@param paths table Resolved project paths.
---@return table[] components Sorted component entries.
---
function M.collect(paths)
    if not paths or not paths.components_dir then
        return {}
    end

    local rust_files = vim.fn.glob(path.join(paths.components_dir, "**/*.rs"), true, true)
    local components = {}

    for _, rust_path in ipairs(rust_files) do
        if basename(rust_path) ~= "mod.rs" then
            local component_name = component_name_from_file(rust_path)

            if component_name then
                local rust_relative = path.relative(paths.components_dir, rust_path)

                table.insert(components, {
                    component_name = component_name,
                    rust_path = rust_path,
                    rust_relative = rust_relative,
                    scss_path = M.resolve_scss_path(rust_path, paths),
                })
            end
        end
    end

    table.sort(components, function(left, right)
        if left.component_name == right.component_name then
            return left.rust_relative < right.rust_relative
        end

        return left.component_name < right.component_name
    end)

    return components
end

--- Opens a Rust component and its paired SCSS partial when present.
---
---@param component table Component entry containing `rust_path` and optional `scss_path`.
---
function M.open_pair(component)
    vim.cmd("edit " .. vim.fn.fnameescape(component.rust_path))

    if component.scss_path then
        vim.cmd("vsplit " .. vim.fn.fnameescape(component.scss_path))
        vim.cmd("wincmd h")
    end
end

--- Opens a newly-created component pair after the current UI callback returns.
---
---@param rust_path string Rust file path.
---@param scss_path string|nil SCSS file path.
---
local function open_created_pair(rust_path, scss_path)
    vim.schedule(function()
        if not fs.exists(rust_path) then
            notify_warn("Rust file not found: " .. rust_path)
            return
        end

        M.open_pair({
            rust_path = rust_path,
            scss_path = scss_path and fs.exists(scss_path) and scss_path or nil,
        })

        if scss_path and not fs.exists(scss_path) then
            notify_warn("Style file not found: " .. scss_path)
        end
    end)
end

--- Builds the Rust source template for a generated component.
---
---@param component_name string PascalCase component function name.
---@param module_name string snake_case module and local class variable name.
---@param class_name string kebab-case CSS class name.
---@return string[] lines Rust source lines.
---
local function build_rust_template(component_name, module_name, class_name)
    return {
        "use leptos::prelude::*;",
        "",
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        string.format("pub fn %s(#[prop(optional, into)] class: Option<String>) -> impl IntoView {", component_name),
        "    // Classes",
        string.format('    let class_name = ClassNameUtil::new("%s", class);', class_name),
        string.format("    let %s = class_name.get_root_class();", module_name),
        "",
        "    view! {",
        string.format("        <div class=%s></div>", module_name),
        "    }",
        "}",
    }
end

--- Builds the SCSS source template for a generated component.
---
---@param class_name string kebab-case CSS class name.
---@return string[] lines SCSS source lines.
---
local function build_scss_template(class_name)
    return {
        string.format(".%s {", class_name),
        "}",
    }
end

--- Records a changed Rust module file after a mutation helper returns true.
---
---@param tracker table Touched-file tracker.
---@param file_path string File path to mark.
---@param changed boolean Whether the file changed.
---
local function mark_when_changed(tracker, file_path, changed)
    if changed then
        touch.mark(tracker, file_path)
    end
end

--- Ensures Rust module declarations and exports for a generated component.
---
---@param paths table Resolved project paths.
---@param relative_dir string Normalized component subdirectory.
---@param module_name string Component module name.
---@param component_name string Component function name.
---@param tracker table Touched-file tracker.
---
local function update_rust_modules(paths, relative_dir, module_name, component_name, tracker)
    local rust_segments = relative_dir == "" and {} or naming.split_path_segments(relative_dir)
    local current_rust_dir = paths.components_dir

    for index, segment in ipairs(rust_segments) do
        local parent_mod = path.join(current_rust_dir, "mod.rs")
        mark_when_changed(tracker, parent_mod, rust.ensure_mod_declaration(parent_mod, segment))

        if index == 1 then
            local root_mod = path.join(paths.components_dir, "mod.rs")
            mark_when_changed(tracker, root_mod, rust.ensure_use_declaration(root_mod, segment .. "::*"))
        end

        current_rust_dir = path.join(current_rust_dir, segment)
        fs.ensure_directory(current_rust_dir)
        fs.ensure_file(path.join(current_rust_dir, "mod.rs"))
    end

    local target_mod = path.join(current_rust_dir, "mod.rs")
    mark_when_changed(tracker, target_mod, rust.ensure_mod_declaration(target_mod, module_name))
    mark_when_changed(
        tracker,
        target_mod,
        rust.ensure_use_declaration(target_mod, module_name .. "::" .. component_name)
    )
    mark_when_changed(tracker, target_mod, rust.normalize_mod_layout(target_mod))

    if #rust_segments > 0 then
        local root_mod = path.join(paths.components_dir, "mod.rs")
        mark_when_changed(tracker, root_mod, rust.normalize_mod_layout(root_mod))
    end
end

--- Creates Rust and SCSS files for a new component.
---
---@param opts table Options containing `input_name`; accepts `relative_dir`, `paths`, `open`, and `format_opts`.
---@return table|nil result Creation result with paths and touched files.
---@return string|nil err Error message when creation fails.
---
function M.create(opts)
    local options = opts or {}
    local input_name = options.input_name
    local component_name = naming.to_pascal_case(input_name)
    local module_name = naming.to_snake_case(input_name)
    local class_name = naming.to_kebab_case(input_name)

    if component_name == "" or module_name == "" or class_name == "" then
        local err = "Invalid component name."
        notify_warn(err)
        return nil, err
    end

    if component_name:match("^%d") then
        local err = "Component name cannot start with a number."
        notify_warn(err)
        return nil, err
    end

    local paths = options.paths or resolve_paths({ "components_dir", "styles_components_dir" })
    if not paths then
        return nil, "Could not resolve component project paths."
    end

    local relative_dir = naming.normalize_relative_dir(options.relative_dir or "")
    local rust_dir = path.join(paths.components_dir, relative_dir)
    local styles_dir = path.join(paths.styles_components_dir, relative_dir)
    local rust_path = path.join(rust_dir, module_name .. ".rs")
    local scss_path = path.join(styles_dir, "_" .. class_name .. ".scss")

    if fs.exists(rust_path) then
        local err = "Rust component already exists: " .. rust_path
        notify_warn(err)
        return nil, err
    end

    if fs.exists(scss_path) then
        local err = "SCSS component already exists: " .. scss_path
        notify_warn(err)
        return nil, err
    end

    fs.ensure_directory(rust_dir)
    fs.ensure_directory(styles_dir)

    fs.write_lines(rust_path, build_rust_template(component_name, module_name, class_name))
    fs.write_lines(scss_path, build_scss_template(class_name))

    local tracker = touch.new()
    touch.mark(tracker, rust_path)
    touch.mark(tracker, scss_path)

    update_rust_modules(paths, relative_dir, module_name, component_name, tracker)

    local style_segments = relative_dir == "" and {} or naming.split_path_segments(relative_dir)
    scss.ensure_forward_chain(paths.styles_components_dir, style_segments, class_name, tracker)

    local formatted = touch.format_touched(tracker, options.format_opts)

    if options.open then
        open_created_pair(rust_path, scss_path)
    end

    return {
        component_name = component_name,
        module_name = module_name,
        class_name = class_name,
        relative_dir = relative_dir,
        rust_path = rust_path,
        scss_path = scss_path,
        touched_paths = tracker:paths(),
        formatted_count = formatted,
    }
end

--- Collects existing component subdirectories for the generation prompt.
---
---@param paths table Resolved project paths.
---@return string[] directories Relative component directories.
---
local function collect_component_subdirectories(paths)
    local directories = vim.fn.glob(path.join(paths.components_dir, "**/"), true, true)
    local seen = {}
    local results = {}

    for _, directory in ipairs(directories) do
        local cleaned = directory:gsub("/$", "")
        if cleaned ~= paths.components_dir then
            local relative = path.relative(paths.components_dir, cleaned)

            if relative ~= "" and relative ~= cleaned and not seen[relative] then
                seen[relative] = true
                table.insert(results, relative)
            end
        end
    end

    table.sort(results)
    return results
end

--- Prompts for an existing or new component subdirectory.
---
---@param paths table Resolved project paths.
---@param input_name string Raw component name input.
---
local function choose_subdirectory(paths, input_name)
    local options = collect_component_subdirectories(paths)
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
                    notify_warn("Invalid sub-directory path.")
                    return
                end

                M.create({
                    input_name = input_name,
                    relative_dir = normalized,
                    paths = paths,
                    open = true,
                })
            end)
        else
            M.create({
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
    local paths = resolve_paths({ "components_dir" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.components_dir) then
        notify_warn("Components directory not found: " .. paths.components_dir)
        return
    end

    local ok_actions, actions = pcall(require, "telescope.actions")
    local ok_action_state, action_state = pcall(require, "telescope.actions.state")
    local ok_finders, finders = pcall(require, "telescope.finders")
    local ok_pickers, pickers = pcall(require, "telescope.pickers")
    local ok_config, telescope_config = pcall(require, "telescope.config")

    if not (ok_actions and ok_action_state and ok_finders and ok_pickers and ok_config) then
        notify_warn("Telescope is required to pick components.")
        return
    end

    local components = M.collect(paths)
    if #components == 0 then
        notify_warn("No Rust components found in " .. paths.components_dir)
        return
    end

    pickers
        .new({}, {
            prompt_title = "Open Component",
            finder = finders.new_table({
                results = components,
                entry_maker = function(component)
                    return {
                        value = component,
                        display = component.component_name .. "  " .. component.rust_relative,
                        ordinal = component.component_name .. " " .. component.rust_relative,
                    }
                end,
            }),
            sorter = telescope_config.values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)

                    if selection and selection.value then
                        M.open_pair(selection.value)
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
    local paths = resolve_paths({ "components_dir", "styles_components_dir" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.components_dir) then
        notify_warn("Components directory not found: " .. paths.components_dir)
        return
    end

    if not fs.is_directory(paths.styles_components_dir) then
        notify_warn("Component styles directory not found: " .. paths.styles_components_dir)
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
                M.create({
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
