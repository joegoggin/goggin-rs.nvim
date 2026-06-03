--- Page Rust module maintenance helpers.
---
--- Maintains page `mod.rs` declarations, root page exports, module-layout
--- page re-exports, and flat-parent validation.

local fs = require("goggin-rs.infra.fs")
local line_utils = require("goggin-rs.infra.lines")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.infra.path")
local rust = require("goggin-rs.rust")
local touch = require("goggin-rs.infra.touch")

local M = {}

--- Ensures a module-layout page declares its private components module.
---
---@param page_mod_path string Page module `mod.rs` path.
---@return boolean changed Whether the file changed.
---
function M.ensure_page_components_module(page_mod_path)
    fs.ensure_file(page_mod_path)

    local lines = fs.read_lines(page_mod_path)
    if line_utils.has_trimmed(lines, "mod components;") or line_utils.has_trimmed(lines, "pub mod components;") then
        return false
    end

    local first_public_mod = nil
    for index, line in ipairs(lines) do
        if naming.trim(line):match("^pub%s+mod%s+") then
            first_public_mod = index
            break
        end
    end

    table.insert(lines, first_public_mod or (#lines + 1), "mod components;")
    fs.write_lines(page_mod_path, lines)
    return true
end

--- Checks whether root pages exports already wildcard-export a top segment.
---
---@param pages_root_mod string Root pages `mod.rs` path.
---@param top_segment string|nil Top filesystem route segment.
---@return boolean has_wildcard Whether `pub use segment::*;` exists.
---
local function has_root_wildcard_export(pages_root_mod, top_segment)
    if not top_segment then
        return false
    end

    return line_utils.has(fs.read_lines(pages_root_mod), "pub use " .. top_segment .. "::*;")
end

--- Ensures the generated page component is exported from page modules.
---
---@param paths table Resolved project paths.
---@param fs_segments string[] Filesystem route segments.
---@param component_name string Page component name.
---@param tracker table Touched-file tracker.
---
function M.ensure_page_export(paths, fs_segments, component_name, tracker)
    local pages_root_mod = path.join(paths.pages_dir, "mod.rs")
    local top_segment = fs_segments[1]
    local root_wildcard = has_root_wildcard_export(pages_root_mod, top_segment)

    if root_wildcard and #fs_segments > 1 then
        local tail_segments = {}
        for index = 2, #fs_segments do
            table.insert(tail_segments, fs_segments[index])
        end

        local top_mod = path.join(paths.pages_dir, top_segment, "mod.rs")
        local top_use = table.concat(tail_segments, "::") .. "::" .. component_name

        touch.mark_when_changed(tracker, top_mod, rust.ensure_use_declaration(top_mod, top_use))
        touch.mark_when_changed(tracker, top_mod, rust.normalize_mod_layout(top_mod))
        return
    end

    if not root_wildcard then
        local root_use = table.concat(fs_segments, "::") .. "::" .. component_name

        touch.mark_when_changed(tracker, pages_root_mod, rust.ensure_use_declaration(pages_root_mod, root_use))
        touch.mark_when_changed(tracker, pages_root_mod, rust.normalize_mod_layout(pages_root_mod))
    end
end

--- Ensures Rust module declarations for a generated page.
---
---@param paths table Resolved project paths.
---@param parent_segments string[] Parent route filesystem segments.
---@param leaf_segment string Leaf route filesystem segment.
---@param tracker table Touched-file tracker.
---
function M.update_page_modules(paths, parent_segments, leaf_segment, tracker)
    local current_pages_dir = paths.pages_dir

    for _, segment in ipairs(parent_segments) do
        local parent_mod = path.join(current_pages_dir, "mod.rs")
        touch.mark_when_changed(tracker, parent_mod, rust.ensure_mod_declaration(parent_mod, segment))
        touch.mark_when_changed(tracker, parent_mod, rust.normalize_mod_layout(parent_mod))

        current_pages_dir = path.join(current_pages_dir, segment)
        fs.ensure_directory(current_pages_dir)
        fs.ensure_file(path.join(current_pages_dir, "mod.rs"))
    end

    local leaf_parent_mod = path.join(current_pages_dir, "mod.rs")
    touch.mark_when_changed(tracker, leaf_parent_mod, rust.ensure_mod_declaration(leaf_parent_mod, leaf_segment))
    touch.mark_when_changed(tracker, leaf_parent_mod, rust.normalize_mod_layout(leaf_parent_mod))
end

--- Ensures the inner `mod.rs` for a generated module-layout page.
---
---@param page_dir string Directory containing the generated `page.rs`.
---@param component_name string Page component name.
---@param tracker table Touched-file tracker.
---
function M.update_module_layout_page_mod(page_dir, component_name, tracker)
    local page_mod = path.join(page_dir, "mod.rs")

    touch.mark_when_changed(tracker, page_mod, rust.ensure_mod_declaration(page_mod, "page"))
    touch.mark_when_changed(tracker, page_mod, rust.ensure_use_declaration(page_mod, "page::" .. component_name))
    touch.mark_when_changed(tracker, page_mod, rust.normalize_mod_layout(page_mod))
end

--- Returns parent route segments from a full route segment list.
---
---@param fs_segments string[] Full filesystem route segments.
---@return string[] parent_segments All route segments except the leaf.
---
function M.parent_segments_from(fs_segments)
    local parent_segments = {}

    for index = 1, #fs_segments - 1 do
        table.insert(parent_segments, fs_segments[index])
    end

    return parent_segments
end

--- Validates that nested generation is not being created under a flat page.
---
---@param paths table Resolved project paths.
---@param parent_segments string[] Parent route filesystem segments.
---@return string|nil err Error message when a flat page blocks nesting.
---
function M.validate_no_flat_parent_page(paths, parent_segments)
    local pages_cursor = paths.pages_dir

    for _, segment in ipairs(parent_segments) do
        local conflicting_flat_page = path.join(pages_cursor, segment .. ".rs")
        if fs.exists(conflicting_flat_page) then
            return "Cannot create nested page under flat page: "
                .. conflicting_flat_page
                .. ". Convert it to a module first."
        end

        pages_cursor = path.join(pages_cursor, segment)
    end

    return nil
end

return M
