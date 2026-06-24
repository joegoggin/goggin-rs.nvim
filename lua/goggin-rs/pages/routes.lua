--- Page route input parsing.
---
--- Parses public route and optional sub-route input into URL route paths and
--- filesystem-safe page module segments.

local naming = require("goggin-rs.naming")

local M = {}

--- Appends a parsed route segment, validating Rust module safety.
---
---@param raw_segment string Raw route segment.
---@param path_segments string[] URL path segments accumulator.
---@param fs_segments string[] Filesystem segment accumulator.
---@return string|nil err Validation error.
---
local function append_route_segment(raw_segment, path_segments, fs_segments)
    local fs_segment = naming.route_segment_to_fs(raw_segment)
    if fs_segment:match("^%d") then
        return "Route segment cannot start with a number: " .. raw_segment
    end

    table.insert(path_segments, naming.route_segment_to_path(raw_segment))
    table.insert(fs_segments, fs_segment)
    return nil
end

--- Parses route and optional nested sub-route input into URL and file segments.
---
---@param route_value string Route input.
---@param subroute_value string|nil Optional nested route input.
---@return table|nil parsed Parsed route information.
---@return string|nil err Validation error.
---
function M.parse_route_segments(route_value, subroute_value)
    local raw_route = naming.trim(route_value)
    local raw_subroute = naming.trim(subroute_value)

    if raw_route == "" then
        return nil, "Route is required."
    end

    if raw_route == "/" and raw_subroute ~= "" then
        return nil, "Root route cannot include sub-route."
    end

    local route_segments = {}
    if raw_route ~= "/" then
        local normalized_route = raw_route:gsub("^/+", ""):gsub("/+$", "")
        for _, segment in ipairs(naming.split_path_segments(normalized_route)) do
            table.insert(route_segments, segment)
        end
    end

    local sub_segments = {}
    if raw_subroute ~= "" then
        local normalized_subroute = raw_subroute:gsub("^/+", ""):gsub("/+$", "")
        for _, segment in ipairs(naming.split_path_segments(normalized_subroute)) do
            table.insert(sub_segments, segment)
        end
    end

    local path_segments = {}
    local fs_segments = {}

    for _, segment in ipairs(route_segments) do
        local segment_error = append_route_segment(segment, path_segments, fs_segments)
        if segment_error then
            return nil, segment_error
        end
    end

    for _, segment in ipairs(sub_segments) do
        local segment_error = append_route_segment(segment, path_segments, fs_segments)
        if segment_error then
            return nil, segment_error
        end
    end

    local route_path = #path_segments == 0 and "/" or "/" .. table.concat(path_segments, "/")

    return {
        route_path = route_path,
        path_segments = path_segments,
        fs_segments = fs_segments,
        route_segments = route_segments,
        sub_segments = sub_segments,
    },
        nil
end

return M
