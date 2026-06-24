--- Flat page to module-layout conversion.
---
--- Moves flat page Rust and SCSS files into module-layout paths while updating
--- page module exports and style forward chains.

local fs = require("goggin-rs.infra.fs")
local modules = require("goggin-rs.pages.modules")
local naming = require("goggin-rs.naming")
local open = require("goggin-rs.pages.open")
local path = require("goggin-rs.infra.path")
local project = require("goggin-rs.project")
local scss = require("goggin-rs.scss")
local styles = require("goggin-rs.pages.styles")
local templates = require("goggin-rs.pages.templates")
local touch = require("goggin-rs.infra.touch")

local M = {}

--- Moves a file or directory and returns a user-facing error on failure.
---
---@param source string Source path.
---@param destination string Destination path.
---@return boolean ok Whether the move succeeded.
---@return string|nil err Error message when moving fails.
---
local function move_path(source, destination)
    if source == destination then
        return true, nil
    end

    if vim.fn.rename(source, destination) == 0 then
        return true, nil
    end

    return false, string.format("Failed to move %s to %s", source, destination)
end

--- Converts a flat page file into module layout.
---
---@param opts table Options containing `page`; accepts `paths`, `format_opts`, and `open`.
---@return table|nil result Conversion result with paths and touched files.
---@return string|nil err Error message when conversion fails.
---
function M.convert_to_module_layout(opts)
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

    if page.is_module_layout then
        return {
            page = page,
            converted = false,
            rust_path = page.page_rs or page.rust_path,
            scss_path = page.page_style_path or page.scss_path,
            touched_paths = {},
            formatted_count = 0,
        }
    end

    local source_rust_path = page.page_rs or page.rust_path
    local target_page_dir = page.page_dir
    local target_rust_path = path.join(target_page_dir, "page.rs")
    local module_style_dir = path.join(paths.page_styles_dir, page.module_relative_dir)
    local target_style_path = path.join(module_style_dir, "_page.scss")
    local existing_style_path = page.page_style_path or page.scss_path

    if not fs.exists(source_rust_path) then
        local err = "Page file not found: " .. source_rust_path
        open.notify_warn(err)
        return nil, err
    end

    if fs.exists(target_rust_path) then
        local err = "Cannot convert page. Target already exists: " .. target_rust_path
        open.notify_warn(err)
        return nil, err
    end

    if
        existing_style_path
        and fs.exists(existing_style_path)
        and existing_style_path ~= target_style_path
        and fs.exists(target_style_path)
    then
        local err = "Cannot convert page style. Target already exists: " .. target_style_path
        open.notify_warn(err)
        return nil, err
    end

    fs.ensure_directory(target_page_dir)
    fs.ensure_directory(module_style_dir)

    local moved_page, page_move_error = move_path(source_rust_path, target_rust_path)
    if not moved_page then
        open.notify_warn(page_move_error)
        return nil, page_move_error
    end

    local tracker = touch.new()
    touch.mark(tracker, target_rust_path)

    modules.update_module_layout_page_mod(target_page_dir, page.page_component_name, tracker)

    if existing_style_path and fs.exists(existing_style_path) then
        if existing_style_path ~= target_style_path then
            local moved_style, style_move_error = move_path(existing_style_path, target_style_path)
            if not moved_style then
                open.notify_warn(style_move_error)
                return nil, style_move_error
            end
        end
    elseif not fs.exists(target_style_path) then
        local class_name = templates.class_name_from_component(page.page_component_name)
        fs.write_lines(target_style_path, class_name and scss.build_class_template(class_name) or {})
    end

    touch.mark(tracker, target_style_path)
    scss.ensure_forward(path.join(module_style_dir, "index.scss"), "page", tracker)

    local parent_style_dir = path.join(paths.page_styles_dir, page.rust_parent_relative)
    local parent_style_index = path.join(parent_style_dir, "index.scss")
    local previous_forward_target = existing_style_path and styles.style_forward_target_from_path(existing_style_path)
        or naming.to_kebab_case(page.module_name)
    scss.replace_forward(parent_style_index, previous_forward_target, page.module_name, tracker)

    page.page_rs = target_rust_path
    page.rust_path = target_rust_path
    page.rust_relative = path.relative(paths.pages_dir, target_rust_path)
    page.rust_parent_relative = page.module_relative_dir
    page.is_module_layout = true
    page.page_style_path = target_style_path
    page.scss_path = target_style_path

    local formatted = 0
    if options.format ~= false then
        formatted = touch.format_touched(tracker, options.format_opts)
    end

    if options.open then
        open.open_created_pair(target_rust_path, target_style_path)
    end

    return {
        page = page,
        converted = true,
        rust_path = target_rust_path,
        scss_path = target_style_path,
        touched_paths = tracker:paths(),
        formatted_count = formatted,
    }
end

return M
