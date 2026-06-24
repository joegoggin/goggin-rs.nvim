--- Page-local component generation.
---
--- Generates components inside module-layout pages, converting flat pages first
--- when needed and maintaining page-local modules and style forwards.

local convert = require("goggin-rs.pages.convert")
local fs = require("goggin-rs.infra.fs")
local modules = require("goggin-rs.pages.modules")
local naming = require("goggin-rs.naming")
local open = require("goggin-rs.pages.open")
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

--- Creates Rust and SCSS files for a page-local component.
---
---@param opts table Options containing `page` and `input_name`; accepts `relative_dir`, `paths`, `open`, and `format_opts`.
---@return table|nil result Creation result with paths and touched files.
---@return string|nil err Error message when creation fails.
---
function M.create_component(opts)
    local options = opts or {}
    local page = options.page

    if not page then
        local err = "Page is required."
        open.notify_warn(err)
        return nil, err
    end

    local paths = options.paths or project.resolve_or_notify({ "pages_dir", "page_styles_dir" })
    if not paths then
        return nil, "Could not resolve page project paths."
    end

    local normalized_input = naming.to_pascal_case(options.input_name)
    if normalized_input == "" then
        local err = "Invalid component name."
        open.notify_warn(err)
        return nil, err
    end

    local suffix = normalized_input
    if normalized_input:sub(1, #page.page_component_name) == page.page_component_name then
        suffix = normalized_input:sub(#page.page_component_name + 1)
    end

    if suffix == "" then
        local err = "Component name must add a suffix to " .. page.page_component_name
        open.notify_warn(err)
        return nil, err
    end

    local relative_dir = naming.normalize_relative_dir(options.relative_dir or "") or ""
    local numeric_segment = first_numeric_segment(relative_dir)
    if numeric_segment then
        local err = "Page component sub-directory cannot start with a number: " .. numeric_segment
        open.notify_warn(err)
        return nil, err
    end

    local module_name = naming.to_snake_case(suffix)
    if module_name:match("^%d") then
        local err = "Component suffix cannot start with a number."
        open.notify_warn(err)
        return nil, err
    end

    local suffix_kebab = naming.to_kebab_case(suffix)
    local page_prefix = naming.to_kebab_case(page.page_component_name:gsub("Page$", "")) .. "-page"
    local class_name = page_prefix .. "-" .. suffix_kebab
    local component_name = page.page_component_name .. suffix
    local base_rust_dir = path.join(page.page_dir, "components")
    local base_style_dir = path.join(paths.page_styles_dir, page.relative_dir, "components")
    local rust_dir = path.join(base_rust_dir, relative_dir)
    local style_dir = path.join(base_style_dir, relative_dir)
    local rust_path = path.join(rust_dir, module_name .. ".rs")
    local scss_path = path.join(style_dir, "_" .. suffix_kebab .. ".scss")

    if fs.exists(rust_path) then
        local err = "Page component already exists: " .. rust_path
        open.notify_warn(err)
        return nil, err
    end

    if fs.exists(scss_path) then
        local err = "Page component style already exists: " .. scss_path
        open.notify_warn(err)
        return nil, err
    end

    local tracker = touch.new()
    local converted = false

    if not page.is_module_layout then
        local conversion, conversion_error = convert.convert_to_module_layout({
            page = page,
            paths = paths,
            format_opts = options.format_opts,
            format = false,
        })

        if not conversion then
            return nil, conversion_error
        end

        converted = conversion.converted == true
        for _, touched_path in ipairs(conversion.touched_paths) do
            touch.mark(tracker, touched_path)
        end
    end

    fs.ensure_directory(rust_dir)
    fs.ensure_directory(style_dir)

    fs.write_lines(rust_path, rust.build_component_template(component_name, class_name, module_name))
    fs.write_lines(scss_path, scss.build_class_template(class_name))

    touch.mark(tracker, rust_path)
    touch.mark(tracker, scss_path)

    local page_mod = path.join(page.page_dir, "mod.rs")
    touch.mark_when_changed(tracker, page_mod, modules.ensure_page_components_module(page_mod))
    touch.mark_when_changed(tracker, page_mod, rust.normalize_mod_layout(page_mod))

    local components_segments = relative_dir == "" and {} or naming.split_path_segments(relative_dir)
    local current_components_dir = base_rust_dir
    fs.ensure_directory(current_components_dir)

    for _, segment in ipairs(components_segments) do
        local parent_mod = path.join(current_components_dir, "mod.rs")
        touch.mark_when_changed(tracker, parent_mod, rust.ensure_mod_declaration(parent_mod, segment))
        touch.mark_when_changed(tracker, parent_mod, rust.normalize_mod_layout(parent_mod))

        current_components_dir = path.join(current_components_dir, segment)
        fs.ensure_directory(current_components_dir)
    end

    local components_mod = path.join(current_components_dir, "mod.rs")
    touch.mark_when_changed(tracker, components_mod, rust.ensure_mod_declaration(components_mod, module_name))
    touch.mark_when_changed(
        tracker,
        components_mod,
        rust.ensure_use_declaration(components_mod, module_name .. "::" .. component_name)
    )
    touch.mark_when_changed(tracker, components_mod, rust.normalize_mod_layout(components_mod))

    scss.ensure_forward(path.join(paths.page_styles_dir, page.relative_dir, "index.scss"), "components", tracker)
    scss.ensure_forward_chain(base_style_dir, components_segments, suffix_kebab, tracker)

    local formatted = touch.format_touched(tracker, options.format_opts)

    if options.open then
        open.open_created_pair(rust_path, scss_path)
    end

    return {
        page = page,
        converted_page = converted,
        component_name = component_name,
        suffix = suffix,
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
