--- Shared empty-directory pruning helpers.
---
--- Deletes empty generated directories that contain at most one empty marker
--- file, then lets callers update parent references for their domain.

local fs = require("goggin-rs.fs")
local path = require("goggin-rs.path")
local touch = require("goggin-rs.touch")

local M = {}

--- Checks whether a normalized path is inside a normalized root.
---
---@param current string Normalized path to inspect.
---@param root string Normalized boundary root.
---@return boolean descendant Whether current is below root.
---
local function is_descendant(current, root)
    if root == "/" then
        return current ~= "/"
    end

    return current:sub(1, #root + 1) == root .. "/"
end

--- Checks whether directory entries include anything beyond a marker file.
---
---@param entries string[] Directory entry names.
---@param marker_name string Marker file allowed in an otherwise empty directory.
---@return boolean has_other_entries Whether any non-marker entry exists.
---
local function has_entries_other_than(entries, marker_name)
    for _, entry in ipairs(entries) do
        if entry ~= marker_name then
            return true
        end
    end

    return false
end

--- Prunes empty directories upward until the configured root boundary.
---
--- Deletes an empty marker file before deleting the containing directory. After
--- each directory deletion, calls `on_pruned_parent` so callers can remove the
--- corresponding parent module declaration or SCSS forward.
---
---@param start_dir string Directory where pruning starts.
---@param root_dir string Boundary directory that is never deleted.
---@param opts table|nil Pruning options.
---@return nil
---
function M.empty_dirs(start_dir, root_dir, opts)
    local options = opts or {}
    local marker_name = options.marker_name
    if not marker_name or marker_name == "" then
        return
    end

    local root = path.normalize_dir(root_dir)
    local current = path.normalize_dir(start_dir)

    while current and root and current ~= root and is_descendant(current, root) do
        if not fs.is_directory(current) then
            current = path.normalize_dir(vim.fn.fnamemodify(current, ":h"))
        else
            local entries = vim.fn.readdir(current)
            if has_entries_other_than(entries, marker_name) then
                break
            end

            local marker_path = path.join(current, marker_name)
            if fs.exists(marker_path) then
                local marker_lines = fs.read_lines(marker_path)
                if fs.has_non_blank_lines(marker_lines) then
                    break
                end

                local removed_marker, marker_error = fs.delete_path(marker_path, false)
                if not removed_marker then
                    vim.notify(marker_error, vim.log.levels.WARN)
                    break
                end

                touch.mark(options.tracker, marker_path)
            end

            local removed_dir, dir_error = fs.delete_path(current, false)
            if not removed_dir then
                vim.notify(dir_error, vim.log.levels.WARN)
                break
            end

            touch.mark(options.tracker, current)

            local parent = path.normalize_dir(vim.fn.fnamemodify(current, ":h"))
            if not parent or parent == current then
                break
            end

            local child_name = vim.fn.fnamemodify(current, ":t")
            if type(options.on_pruned_parent) == "function" then
                options.on_pruned_parent(parent, child_name, options.tracker)
            end

            current = parent
        end
    end
end

return M
