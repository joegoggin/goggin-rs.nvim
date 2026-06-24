--- Component generation workflow.
---
--- Creates Rust component modules, SCSS partials, Rust module declarations,
--- style forwards, and touched-file formatting for generated components.

local fs = require("goggin-rs.infra.fs")
local modules = require("goggin-rs.components.modules")
local naming = require("goggin-rs.naming")
local open = require("goggin-rs.components.open")
local path = require("goggin-rs.infra.path")
local project = require("goggin-rs.project")
local rust = require("goggin-rs.rust")
local scss = require("goggin-rs.scss")
local touch = require("goggin-rs.infra.touch")

local M = {}

--- Returns the first path segment that would be an invalid Rust module name.
---
---@param relative_dir string Normalized relative directory.
---@return string|nil segment Numeric-leading segment when present.
---
local function first_numeric_segment(relative_dir)
    for _, segment in ipairs(naming.split_path_segments(relative_dir)) do
        if segment:match("^%d") then
            return segment
        end
    end

    return nil
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
        open.notify_warn(err)
        return nil, err
    end

    if component_name:match("^%d") then
        local err = "Component name cannot start with a number."
        open.notify_warn(err)
        return nil, err
    end

    local paths = options.paths or project.resolve_or_notify({ "components_dir", "styles_components_dir" })
    if not paths then
        return nil, "Could not resolve component project paths."
    end

    local relative_dir = naming.normalize_relative_dir(options.relative_dir or "")
    local numeric_segment = first_numeric_segment(relative_dir)
    if numeric_segment then
        local err = "Component sub-directory cannot start with a number: " .. numeric_segment
        open.notify_warn(err)
        return nil, err
    end

    local rust_dir = path.join(paths.components_dir, relative_dir)
    local styles_dir = path.join(paths.styles_components_dir, relative_dir)
    local rust_path = path.join(rust_dir, module_name .. ".rs")
    local scss_path = path.join(styles_dir, "_" .. class_name .. ".scss")

    if fs.exists(rust_path) then
        local err = "Rust component already exists: " .. rust_path
        open.notify_warn(err)
        return nil, err
    end

    if fs.exists(scss_path) then
        local err = "SCSS component already exists: " .. scss_path
        open.notify_warn(err)
        return nil, err
    end

    fs.ensure_directory(rust_dir)
    fs.ensure_directory(styles_dir)

    fs.write_lines(rust_path, rust.build_component_template(component_name, class_name, module_name))
    fs.write_lines(scss_path, scss.build_class_template(class_name))

    local tracker = touch.new()
    touch.mark(tracker, rust_path)
    touch.mark(tracker, scss_path)

    modules.update_rust_modules(paths, relative_dir, module_name, component_name, tracker)

    local style_segments = relative_dir == "" and {} or naming.split_path_segments(relative_dir)
    scss.ensure_forward_chain(paths.styles_components_dir, style_segments, class_name, tracker)

    local formatted = touch.format_touched(tracker, options.format_opts)

    if options.open then
        open.open_created_pair(rust_path, scss_path)
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

return M
