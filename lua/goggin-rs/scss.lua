--- SCSS index mutation helpers.
---
--- Maintains generated `index.scss` files by adding, replacing, removing, and
--- pruning `@forward` declarations for components and pages.

local fs = require("goggin-rs.fs")
local path = require("goggin-rs.path")
local prune = require("goggin-rs.prune")
local touch = require("goggin-rs.touch")

local M = {}

--- Checks whether a line list contains an exact line.
---
---@param lines string[] Lines to inspect.
---@param expected string Exact line to find.
---@return boolean found Whether the line exists.
---
local function has_line(lines, expected)
    for _, line in ipairs(lines) do
        if line == expected then
            return true
        end
    end

    return false
end

--- Checks whether an SCSS index forwards a target.
---
---@param lines string[] SCSS index lines to inspect.
---@param target string Forward target to find.
---@return boolean found Whether the target is already forwarded.
---
local function has_forward(lines, target)
    for _, line in ipairs(lines) do
        local forward_target = line:match('^%s*@forward%s+"([^"]+)"%s*;%s*$')
        if forward_target == target then
            return true
        end
    end

    return false
end

--- Builds a canonical SCSS forward line.
---
---@param target string Forward target.
---@return string line SCSS `@forward` declaration.
---
local function forward_line(target)
    return string.format('@forward "%s";', target)
end

--- Ensures an SCSS index forwards a target.
---
---@param index_path string Path to the SCSS index file.
---@param target string Forward target to add.
---@param tracker table|nil Touched-file tracker to mark on change.
---@return boolean changed Whether the file changed.
---
function M.ensure_forward(index_path, target, tracker)
    fs.ensure_file(index_path)

    local line = forward_line(target)
    local lines = fs.read_lines(index_path)
    if has_forward(lines, target) then
        return false
    end

    table.insert(lines, line)
    fs.write_lines(index_path, lines)
    touch.mark(tracker, index_path)
    return true
end

--- Replaces one SCSS forward target with another.
---
--- Adds the new target when the old target is missing, and avoids duplicating
--- the new target when it already exists.
---
---@param index_path string Path to the SCSS index file.
---@param old_target string Forward target to replace.
---@param new_target string Forward target to ensure.
---@param tracker table|nil Touched-file tracker to mark on change.
---@return boolean changed Whether the file changed.
---
function M.replace_forward(index_path, old_target, new_target, tracker)
    fs.ensure_file(index_path)

    local old_line = forward_line(old_target)
    local new_line = forward_line(new_target)
    local lines = fs.read_lines(index_path)
    local has_new = has_line(lines, new_line)
    local updated = {}
    local changed = false

    for _, line in ipairs(lines) do
        if old_target ~= new_target and line == old_line then
            if not has_new then
                table.insert(updated, new_line)
                has_new = true
            end
            changed = true
        else
            table.insert(updated, line)
        end
    end

    if not has_new then
        table.insert(updated, new_line)
        changed = true
    end

    if changed then
        fs.write_lines(index_path, updated)
        touch.mark(tracker, index_path)
    end

    return changed
end

--- Removes an SCSS forward target from an index.
---
---@param index_path string Path to the SCSS index file.
---@param target string Forward target to remove.
---@param tracker table|nil Touched-file tracker to mark on change.
---@return boolean changed Whether the file changed.
---
function M.remove_forward(index_path, target, tracker)
    if not fs.exists(index_path) then
        return false
    end

    local lines = fs.read_lines(index_path)
    local updated = {}
    local changed = false

    for _, line in ipairs(lines) do
        local forward_target = line:match('^%s*@forward%s+"([^"]+)"%s*;%s*$')
        if forward_target == target then
            changed = true
        else
            table.insert(updated, line)
        end
    end

    if not changed then
        return false
    end

    fs.write_lines(index_path, updated)
    touch.mark(tracker, index_path)
    return true
end

--- Ensures nested SCSS indexes forward through a directory chain.
---
---@param style_root string Root style directory for the chain.
---@param segments string[]|nil Directory segments to link with index forwards.
---@param target string Leaf forward target.
---@param tracker table|nil Touched-file tracker to mark changed indexes.
---
function M.ensure_forward_chain(style_root, segments, target, tracker)
    local current = style_root

    for _, segment in ipairs(segments or {}) do
        fs.ensure_directory(current)
        M.ensure_forward(path.join(current, "index.scss"), segment, tracker)

        current = path.join(current, segment)
        fs.ensure_directory(current)
    end

    M.ensure_forward(path.join(current, "index.scss"), target, tracker)
end

--- Prunes empty SCSS directories and removes parent forwards.
---
---@param start_dir string Directory where pruning starts.
---@param root_dir string Boundary directory that is never deleted.
---@param tracker table|nil Touched-file tracker for deleted paths and updated parents.
---
function M.prune_empty_dirs(start_dir, root_dir, tracker)
    prune.empty_dirs(start_dir, root_dir, {
        marker_name = "index.scss",
        tracker = tracker,
        on_pruned_parent = function(parent, child_name, active_tracker)
            M.remove_forward(path.join(parent, "index.scss"), child_name, active_tracker)
        end,
    })
end

return M
