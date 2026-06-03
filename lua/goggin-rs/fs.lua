--- Filesystem helpers for goggin-rs.nvim.
---
--- Wraps Neovim filesystem primitives with small, nil-safe helpers used by
--- project discovery, source mutation, and cleanup code.

local M = {}

local path = require("goggin-rs.path")

--- Checks whether a filesystem path exists.
---
---@param path string|nil Path to inspect.
---@return boolean exists Whether the path exists.
---
function M.exists(path)
    if not path or path == "" then
        return false
    end

    return vim.uv.fs_stat(path) ~= nil
end

--- Checks whether a filesystem path is a directory.
---
---@param path string|nil Path to inspect.
---@return boolean is_directory Whether the path exists and is a directory.
---
function M.is_directory(path)
    if not path or path == "" then
        return false
    end

    local stat = vim.uv.fs_stat(path)
    return stat ~= nil and stat.type == "directory"
end

--- Reads all lines from an existing file.
---
---@param path string Path to read.
---@return string[] lines File lines, or an empty list when the file is missing.
---
function M.read_lines(path)
    if not M.exists(path) then
        return {}
    end

    return vim.fn.readfile(path)
end

--- Writes lines to a file.
---
---@param path string Path to write.
---@param lines string[] Lines to write.
---
function M.write_lines(path, lines)
    vim.fn.writefile(lines, path)
end

--- Creates a directory and missing parents when needed.
---
---@param path string|nil Directory path to ensure.
---
function M.ensure_directory(path)
    if path and path ~= "" and not M.is_directory(path) then
        vim.fn.mkdir(path, "p")
    end
end

--- Creates an empty file when it does not already exist.
---
---@param path string Path to ensure.
---
function M.ensure_file(path)
    if not M.exists(path) then
        M.write_lines(path, {})
    end
end

--- Checks whether any line contains non-whitespace content.
---
---@param lines string[] Lines to inspect.
---@return boolean has_content Whether any line contains non-whitespace text.
---
function M.has_non_blank_lines(lines)
    for _, line in ipairs(lines) do
        if line:match("%S") then
            return true
        end
    end

    return false
end

--- Collects relative subdirectory paths below a base directory.
---
---@param base_dir string Directory whose descendants should be collected.
---@return string[] directories Sorted relative subdirectory paths.
---
function M.relative_subdirectories(base_dir)
    local directories = vim.fn.glob(path.join(base_dir, "**/"), true, true)
    local seen = {}
    local results = {}

    for _, directory in ipairs(directories) do
        local cleaned = directory:gsub("/$", "")
        if cleaned ~= base_dir then
            local relative = path.relative(base_dir, cleaned)

            if relative ~= "" and relative ~= cleaned and not seen[relative] then
                seen[relative] = true
                table.insert(results, relative)
            end
        end
    end

    table.sort(results)
    return results
end

--- Deletes a file or directory if it exists.
---
---@param path string Path to delete.
---@param recursive boolean Whether directory deletion should be recursive.
---@return boolean ok Whether deletion succeeded or the path was already gone.
---@return string|nil err Deletion error message when deletion fails.
---
function M.delete_path(path, recursive)
    local stat = vim.uv.fs_stat(path)
    if not stat then
        return true, nil
    end

    local ok
    if stat.type == "directory" then
        ok = vim.fn.delete(path, recursive and "rf" or "d") == 0
    else
        ok = vim.fn.delete(path) == 0
    end

    if ok then
        return true, nil
    end

    return false, "Failed to delete " .. path
end

return M
