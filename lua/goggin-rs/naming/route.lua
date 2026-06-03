--- Path and route segment naming helpers.
---
--- Converts route and filesystem path segments into safe Rust module names,
--- URL path segments, and normalized nested directories.

local case = require("goggin-rs.naming.case")

local M = {}

--- Splits a slash-delimited path into meaningful segments.
---
---@param path string|nil Path-like value to split.
---@return string[] segments Non-empty path segments excluding dot segments.
---
function M.split_path_segments(path)
    local segments = {}

    for segment in (path or ""):gmatch("[^/]+") do
        if segment ~= "" and segment ~= "." then
            table.insert(segments, segment)
        end
    end

    return segments
end

--- Normalizes a relative directory path into snake_case segments.
---
---@param input string|nil Raw relative directory path.
---@return string normalized Normalized relative directory path.
---
function M.normalize_relative_dir(input)
    local normalized = {}

    for _, segment in ipairs(M.split_path_segments(input)) do
        local snake_segment = case.to_snake_case(segment)
        if snake_segment ~= "" then
            table.insert(normalized, snake_segment)
        end
    end

    return table.concat(normalized, "/")
end

--- Converts a route segment into a filesystem-safe snake_case segment.
---
---@param segment string|nil Route segment to convert.
---@return string fs_segment Filesystem segment, or `index` for blank input.
---
function M.route_segment_to_fs(segment)
    local cleaned = case.trim(segment)
    cleaned = cleaned:gsub("^:", "")
    cleaned = cleaned:gsub("%*", "all")

    local snake = case.to_snake_case(cleaned)
    if snake == "" then
        return "index"
    end

    return snake
end

--- Converts a route segment into a URL path segment.
---
---@param segment string|nil Route segment to convert.
---@return string path_segment URL path segment, preserving dynamic route markers.
---
function M.route_segment_to_path(segment)
    local cleaned = case.trim(segment)
    if cleaned:sub(1, 1) == ":" then
        return cleaned
    end

    return case.to_kebab_case(cleaned)
end

return M
