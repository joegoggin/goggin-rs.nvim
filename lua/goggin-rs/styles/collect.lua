--- Style item collection and path planning.
---
--- Builds add/delete candidates for regular components, pages, and page-local
--- components while preserving the source config's SCSS naming conventions.

local fs = require("goggin-rs.infra.fs")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.infra.path")
local pages = require("goggin-rs.pages.collect")
local rust = require("goggin-rs.rust")

local M = {}

local TYPE_ORDER = {
    page = 1,
    page_component = 2,
    component = 3,
}

--- Copies a list of path segments.
---
---@param segments string[]|nil Segments to copy.
---@return string[] copy Copied segment list.
---
local function copy_segments(segments)
    local copy = {}
    for _, segment in ipairs(segments or {}) do
        table.insert(copy, segment)
    end

    return copy
end

--- Joins a root path with path segments.
---
---@param root string Root path.
---@param segments string[]|nil Path segments.
---@return string joined Joined path.
---
local function join_segments(root, segments)
    local current = root
    for _, segment in ipairs(segments or {}) do
        current = path.join(current, segment)
    end

    return current
end

--- Returns all but the final path segment.
---
---@param segments string[] Segment list.
---@return string[] parents Parent segments.
---
local function parent_segments(segments)
    local parents = {}
    for index = 1, math.max(#segments - 1, 0) do
        table.insert(parents, segments[index])
    end

    return parents
end

--- Reads forwarded targets from an SCSS index.
---
---@param index_path string SCSS index file path.
---@return table<string, boolean> forwards Set of forwarded targets.
---
local function collect_forward_targets(index_path)
    local forwards = {}

    for _, line in ipairs(fs.read_lines(index_path)) do
        local target = line:match('^%s*@forward%s+"([^"]+)"%s*;%s*$')
        if target then
            forwards[target] = true
        end
    end

    return forwards
end

--- Resolves or plans a direct or parent-prefixed SCSS partial.
---
---@param base_dir string Style directory.
---@param stem string Rust file stem.
---@return table plan Partial plan with `exists`, `path`, and `target`.
---
local function resolve_partial_style_plan(base_dir, stem)
    local kebab_stem = stem:gsub("_", "-")
    local direct_target = kebab_stem
    local direct_path = path.join(base_dir, "_" .. direct_target .. ".scss")
    if fs.exists(direct_path) then
        return {
            exists = true,
            path = direct_path,
            target = direct_target,
        }
    end

    local parent = path.basename(base_dir):gsub("_", "-")
    local prefixed_target = parent .. "-" .. kebab_stem
    local prefixed_path = path.join(base_dir, "_" .. prefixed_target .. ".scss")
    if fs.exists(prefixed_path) then
        return {
            exists = true,
            path = prefixed_path,
            target = prefixed_target,
        }
    end

    local prefer_prefixed = false
    if fs.is_directory(base_dir) then
        local pattern = path.join(base_dir, "_" .. parent .. "-*.scss")
        prefer_prefixed = #vim.fn.glob(pattern, true, true) > 0
    end

    if prefer_prefixed then
        return {
            exists = false,
            path = prefixed_path,
            target = prefixed_target,
        }
    end

    return {
        exists = false,
        path = direct_path,
        target = direct_target,
    }
end

--- Maps component Rust segments to style segments using root forwards.
---
---@param style_root string Component style root.
---@param rust_segments string[] Component Rust relative directory segments.
---@param root_forwards table<string, boolean> Root SCSS forward set.
---@return string[] style_segments Planned style segments.
---
local function map_component_style_segments(style_root, rust_segments, root_forwards)
    if #rust_segments == 0 then
        return {}
    end

    local mapped = copy_segments(rust_segments)
    local first = rust_segments[1]
    local singular = first:gsub("s$", "")
    local plural = first .. "s"

    if root_forwards[first] then
        mapped[1] = first
    elseif singular ~= first and root_forwards[singular] then
        mapped[1] = singular
    elseif root_forwards[plural] then
        mapped[1] = plural
    end

    local mapped_dir = join_segments(style_root, mapped)
    local original_dir = join_segments(style_root, rust_segments)
    if not fs.is_directory(mapped_dir) and fs.is_directory(original_dir) then
        return copy_segments(rust_segments)
    end

    return mapped
end

--- Builds a page class name from a page component symbol.
---
---@param page_component_name string Page component symbol.
---@return string|nil class_name Page CSS class name.
---
local function class_name_from_page_component(page_component_name)
    local base = (page_component_name or ""):gsub("Page$", "")
    local kebab = naming.to_kebab_case(base)
    if kebab == "" then
        return nil
    end

    return kebab .. "-page"
end

--- Returns whether a style plan should be included for this collection mode.
---
---@param exists boolean Whether the style exists.
---@param include_existing boolean Whether to collect existing styles.
---@return boolean include Whether to include the item.
---
local function should_include(exists, include_existing)
    return (include_existing and exists) or (not include_existing and not exists)
end

--- Appends an item when its style plan matches the collection mode.
---
---@param items table[] Item accumulator.
---@param include_existing boolean Whether to collect existing styles.
---@param item table Style item without class fallback normalization.
---@param style_plan table Style plan.
---
local function append_planned_item(items, include_existing, item, style_plan)
    if not should_include(style_plan.exists, include_existing) then
        return
    end

    local class_name = rust.extract_existing_class_name(item.rust_path)
    if not class_name or class_name == "" then
        class_name = item.class_name or style_plan.target
    end

    item.scss_path = style_plan.path
    item.style_target = style_plan.target
    item.class_name = class_name
    item.style_exists = style_plan.exists

    table.insert(items, item)
end

--- Collects Rust component files under a root with derived metadata.
---
---@param root string Root directory to scan.
---@return table[] sources Component source metadata.
---
local function collect_component_sources(root)
    local sources = {}

    for _, rust_path in ipairs(vim.fn.glob(path.join(root, "**/*.rs"), true, true)) do
        if path.basename(rust_path) ~= "mod.rs" then
            local component_name = rust.component_name_from_file(rust_path)
            if component_name then
                local rust_relative = path.relative(root, rust_path)
                local relative_dir = vim.fn.fnamemodify(rust_relative, ":h")
                if relative_dir == "." then
                    relative_dir = ""
                end

                table.insert(sources, {
                    component_name = component_name,
                    rust_path = rust_path,
                    rust_relative = rust_relative,
                    relative_dir = relative_dir,
                    stem = vim.fn.fnamemodify(rust_relative, ":t:r"),
                })
            end
        end
    end

    return sources
end

--- Collects regular component style items.
---
---@param paths table Resolved project paths.
---@param include_existing boolean Whether to collect existing styles.
---@return table[] items Component style items.
---
local function collect_regular_component_items(paths, include_existing)
    if not paths.components_dir or not paths.styles_components_dir then
        return {}
    end

    local root_forwards = collect_forward_targets(path.join(paths.styles_components_dir, "index.scss"))
    local items = {}

    for _, source in ipairs(collect_component_sources(paths.components_dir)) do
        local rust_segments = naming.split_path_segments(source.relative_dir)
        local style_segments = map_component_style_segments(paths.styles_components_dir, rust_segments, root_forwards)
        local style_base_dir = join_segments(paths.styles_components_dir, style_segments)
        local style_plan = resolve_partial_style_plan(style_base_dir, source.stem)

        append_planned_item(items, include_existing, {
            item_type = "component",
            kind_label = "Component",
            component_name = source.component_name,
            rust_path = source.rust_path,
            rust_relative = source.rust_relative,
            style_root = paths.styles_components_dir,
            style_segments = style_segments,
        }, style_plan)
    end

    return items
end

--- Builds the style plan for a page entry.
---
---@param page table Page entry.
---@param paths table Resolved project paths.
---@return table plan Page style plan.
---
local function resolve_page_style_plan(page, paths)
    local module_segments = naming.split_path_segments(page.module_relative_dir)

    if page.is_module_layout then
        local style_dir = join_segments(paths.page_styles_dir, module_segments)
        local scss_path = path.join(style_dir, "_page.scss")

        return {
            exists = fs.exists(scss_path),
            path = scss_path,
            target = "page",
            segments = module_segments,
        }
    end

    local style_segments = parent_segments(module_segments)
    local style_dir = join_segments(paths.page_styles_dir, style_segments)
    local style_target = naming.to_kebab_case(page.module_name)
    local scss_path = path.join(style_dir, "_" .. style_target .. ".scss")

    return {
        exists = fs.exists(scss_path),
        path = scss_path,
        target = style_target,
        segments = style_segments,
    }
end

--- Collects page-local component style items for a module-layout page.
---
---@param page table Page entry.
---@param paths table Resolved project paths.
---@param include_existing boolean Whether to collect existing styles.
---@param items table[] Item accumulator.
---
local function collect_page_component_items(page, paths, include_existing, items)
    if not page.is_module_layout then
        return
    end

    local components_dir = path.join(page.page_dir, "components")
    if not fs.is_directory(components_dir) then
        return
    end

    for _, source in ipairs(collect_component_sources(components_dir)) do
        local style_segments = naming.split_path_segments(page.module_relative_dir)
        table.insert(style_segments, "components")
        for _, segment in ipairs(naming.split_path_segments(source.relative_dir)) do
            table.insert(style_segments, segment)
        end

        local style_base_dir = join_segments(paths.page_styles_dir, style_segments)
        local style_plan = resolve_partial_style_plan(style_base_dir, source.stem)

        append_planned_item(items, include_existing, {
            item_type = "page_component",
            kind_label = "Page Component",
            component_name = source.component_name,
            rust_path = source.rust_path,
            rust_relative = path.relative(paths.pages_dir, source.rust_path),
            style_root = paths.page_styles_dir,
            style_segments = style_segments,
        }, style_plan)
    end
end

--- Collects page and page-local component style items.
---
---@param paths table Resolved project paths.
---@param include_existing boolean Whether to collect existing styles.
---@return table[] items Page-related style items.
---
local function collect_page_related_items(paths, include_existing)
    if not paths.pages_dir or not paths.page_styles_dir then
        return {}
    end

    local items = {}
    for _, page in ipairs(pages.collect(paths)) do
        local page_style = resolve_page_style_plan(page, paths)

        append_planned_item(items, include_existing, {
            item_type = "page",
            kind_label = "Page",
            component_name = page.page_component_name,
            rust_path = page.rust_path,
            rust_relative = page.rust_relative,
            style_root = paths.page_styles_dir,
            style_segments = page_style.segments,
            class_name = class_name_from_page_component(page.page_component_name),
        }, page_style)

        collect_page_component_items(page, paths, include_existing, items)
    end

    return items
end

--- Collects style items for missing-style add or existing-style delete flows.
---
---@param opts table Options containing `paths`; `include_existing = true` collects existing styles.
---@return table[] items Sorted style items.
---
function M.collect(opts)
    local options = opts or {}
    local paths = options.paths or {}
    local include_existing = options.include_existing == true
    local items = {}

    for _, item in ipairs(collect_page_related_items(paths, include_existing)) do
        table.insert(items, item)
    end

    for _, item in ipairs(collect_regular_component_items(paths, include_existing)) do
        table.insert(items, item)
    end

    table.sort(items, function(left, right)
        local left_order = TYPE_ORDER[left.item_type] or 99
        local right_order = TYPE_ORDER[right.item_type] or 99
        if left_order ~= right_order then
            return left_order < right_order
        end

        if left.component_name == right.component_name then
            return left.rust_relative < right.rust_relative
        end

        return left.component_name < right.component_name
    end)

    return items
end

return M
