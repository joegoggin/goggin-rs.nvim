--- Page generation workflow.
---
--- Creates flat or module-layout pages with paired styles, page module exports,
--- route insertion, and touched-file formatting.

local fs = require("goggin-rs.infra.fs")
local modules = require("goggin-rs.pages.modules")
local naming = require("goggin-rs.naming")
local open = require("goggin-rs.pages.open")
local path = require("goggin-rs.infra.path")
local project = require("goggin-rs.project")
local routes = require("goggin-rs.pages.routes")
local rust = require("goggin-rs.rust")
local scss = require("goggin-rs.scss")
local templates = require("goggin-rs.pages.templates")
local touch = require("goggin-rs.infra.touch")

local M = {}

--- Creates Rust and SCSS files for a new page and inserts its app route.
---
---@param opts table Options containing `route` and `page_name`; accepts `subroute`, `private`, `module_layout`, `paths`, `open`, and `format_opts`.
---@return table|nil result Creation result with paths and touched files.
---@return string|nil err Error message when creation fails.
---
function M.create(opts)
    local options = opts or {}
    local parsed, parse_error = routes.parse_route_segments(options.route, options.subroute)
    if parse_error then
        open.notify_warn(parse_error)
        return nil, parse_error
    end

    local component_name = templates.build_page_component_name(options.page_name)
    if not component_name then
        local err = "Invalid page name."
        open.notify_warn(err)
        return nil, err
    end

    if component_name:match("^%d") then
        local err = "Page name cannot start with a number."
        open.notify_warn(err)
        return nil, err
    end

    if #parsed.fs_segments == 0 then
        local err = "Root route generation is not supported by this generator."
        open.notify_warn(err)
        return nil, err
    end

    local class_name = templates.class_name_from_component(component_name)
    if not class_name then
        local err = "Invalid page class name."
        open.notify_warn(err)
        return nil, err
    end

    local paths = options.paths or project.resolve_or_notify({ "pages_dir", "page_styles_dir", "app_path" })
    if not paths then
        return nil, "Could not resolve page project paths."
    end

    local leaf_segment = parsed.fs_segments[#parsed.fs_segments]
    local parent_segments = modules.parent_segments_from(parsed.fs_segments)
    local flat_parent_error = modules.validate_no_flat_parent_page(paths, parent_segments)
    if flat_parent_error then
        open.notify_warn(flat_parent_error)
        return nil, flat_parent_error
    end

    local current_pages_dir = paths.pages_dir
    local current_style_dir = paths.page_styles_dir
    for _, segment in ipairs(parent_segments) do
        current_pages_dir = path.join(current_pages_dir, segment)
        current_style_dir = path.join(current_style_dir, segment)
    end

    fs.ensure_directory(current_pages_dir)
    fs.ensure_directory(current_style_dir)

    local module_layout = options.module_layout == true
    local flat_rust_path = path.join(current_pages_dir, leaf_segment .. ".rs")
    local module_page_path = path.join(current_pages_dir, leaf_segment, "page.rs")
    local scss_stem = naming.to_kebab_case(leaf_segment)
    local flat_scss_path = path.join(current_style_dir, "_" .. scss_stem .. ".scss")
    local module_scss_path = path.join(current_style_dir, leaf_segment, "_page.scss")
    local rust_path = module_layout and module_page_path or flat_rust_path
    local scss_path = module_layout and module_scss_path or flat_scss_path

    if fs.exists(flat_rust_path) or fs.exists(module_page_path) then
        local err = "Page already exists: " .. flat_rust_path
        open.notify_warn(err)
        return nil, err
    end

    if fs.exists(flat_scss_path) or fs.exists(module_scss_path) then
        local err = "Page style already exists: " .. flat_scss_path
        open.notify_warn(err)
        return nil, err
    end

    if module_layout then
        fs.ensure_directory(path.join(current_pages_dir, leaf_segment))
        fs.ensure_directory(path.join(current_style_dir, leaf_segment))
    end

    fs.write_lines(rust_path, templates.build_page_rust_template(component_name, class_name))
    fs.write_lines(scss_path, scss.build_class_template(class_name))

    local tracker = touch.new()
    touch.mark(tracker, rust_path)
    touch.mark(tracker, scss_path)

    modules.update_page_modules(paths, parent_segments, leaf_segment, tracker)
    if module_layout then
        modules.update_module_layout_page_mod(path.join(current_pages_dir, leaf_segment), component_name, tracker)
    end

    modules.ensure_page_export(paths, parsed.fs_segments, component_name, tracker)
    if module_layout then
        scss.ensure_forward_chain(paths.page_styles_dir, parent_segments, leaf_segment, tracker)
        scss.ensure_forward(path.join(current_style_dir, leaf_segment, "index.scss"), "page", tracker)
    else
        scss.ensure_forward_chain(paths.page_styles_dir, parent_segments, scss_stem, tracker)
    end

    touch.mark_when_changed(
        tracker,
        paths.app_path,
        rust.insert_route(paths.app_path, parsed.route_path, component_name, { private = options.private == true })
    )

    local formatted = touch.format_touched(tracker, options.format_opts)

    if options.open then
        open.open_created_pair(rust_path, scss_path)
    end

    return {
        component_name = component_name,
        class_name = class_name,
        module_name = leaf_segment,
        is_module_layout = module_layout,
        relative_dir = table.concat(parsed.fs_segments, "/"),
        route_path = parsed.route_path,
        private = options.private == true,
        rust_path = rust_path,
        scss_path = scss_path,
        touched_paths = tracker:paths(),
        formatted_count = formatted,
    }
end

return M
