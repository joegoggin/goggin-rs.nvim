--- Line-list helpers for source mutation modules.
---
--- Provides small shared predicates for modules that read, compare, and update
--- file contents as arrays of lines.

local naming = require("goggin-rs.naming")

local M = {}

--- Checks whether a line list contains an exact line.
---
---@param lines string[] Lines to inspect.
---@param expected string Exact line to find.
---@return boolean found Whether the line exists.
---
function M.has(lines, expected)
    for _, line in ipairs(lines) do
        if line == expected then
            return true
        end
    end

    return false
end

--- Checks whether a line list contains a line after trimming whitespace.
---
---@param lines string[] Lines to inspect.
---@param expected string Trimmed line text to find.
---@return boolean found Whether a trimmed line matches.
---
function M.has_trimmed(lines, expected)
    for _, line in ipairs(lines) do
        if naming.trim(line) == expected then
            return true
        end
    end

    return false
end

--- Compares two line lists for identical ordered contents.
---
---@param left string[] First line list.
---@param right string[] Second line list.
---@return boolean same Whether both lists contain the same lines.
---
function M.equals(left, right)
    if #left ~= #right then
        return false
    end

    for index, value in ipairs(left) do
        if right[index] ~= value then
            return false
        end
    end

    return true
end

return M
