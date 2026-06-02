--- Path helpers for goggin-rs.nvim.
---
--- Provides small string-based path utilities for building project paths and
--- comparing normalized directories.

local M = {}

--- Joins non-empty path parts with forward slashes.
---
---@param ... string|nil Path parts to join.
---@return string path Joined path.
---
function M.join(...)
    local parts = {}

    for index = 1, select("#", ...) do
        local part = select(index, ...)
        if part and part ~= "" then
            table.insert(parts, part)
        end
    end

    return table.concat(parts, "/")
end

--- Returns a child path relative to a root when possible.
---
---@param root string Root path.
---@param path string Path to relativize.
---@return string relative_path Relative path, empty string for the root, or the original path.
---
function M.relative(root, path)
    local prefix = root .. "/"
    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end

    if path == root then
        return ""
    end

    return path
end

--- Checks whether a path is absolute on Unix or Windows.
---
---@param path string|nil Path to inspect.
---@return boolean is_absolute Whether the path is absolute.
---
function M.is_absolute(path)
    if not path or path == "" then
        return false
    end

    return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

--- Normalizes a directory path to an absolute path without trailing slashes.
---
---@param path string|nil Directory path to normalize.
---@return string|nil normalized Normalized absolute path, or nil for blank input.
---
function M.normalize_dir(path)
    if not path or path == "" then
        return nil
    end

    local normalized = vim.fn.fnamemodify(path, ":p")
    if normalized == "" then
        return nil
    end

    normalized = normalized:gsub("/+$", "")
    if normalized == "" then
        return "/"
    end

    return normalized
end

return M
