--- Leptos route mutation helpers for Rust app files.
---
--- Inserts and removes Leptos routes inside app `<Routes>` blocks while
--- maintaining route group comments and blank-line layout.

local fs = require("goggin-rs.infra.fs")
local line_utils = require("goggin-rs.infra.lines")
local naming = require("goggin-rs.naming")

local M = {}

--- Checks whether a line starts a Leptos route component.
---
---@param line string Source line to inspect.
---@return boolean is_route Whether the line starts `Route` or `PrivateRoute`.
---
local function is_route_start_line(line)
    return line:match("<%s*Route%f[%W]") ~= nil or line:match("<%s*PrivateRoute%f[%W]") ~= nil
end

--- Checks whether a collected route tag block is self-closing.
---
---@param block string[] Route tag lines.
---@return boolean is_self_closing Whether the tag ends with `/>`.
---
local function route_tag_is_self_closing(block)
    local last_line = block[#block] or ""
    return last_line:match("/>%s*$") ~= nil
end

--- Checks whether a line is a route-group comment.
---
---@param line string Source line to inspect.
---@return boolean is_comment Whether the line is a route-group comment.
---
local function is_group_comment_line(line)
    return line:match("^%s*//%s*.+") ~= nil
end

--- Finds the bounds of the first Leptos `<Routes>` block.
---
---@param lines string[] App source lines.
---@return integer|nil routes_start Start line index for the routes block.
---@return integer|nil routes_end End line index for the routes block.
---
local function find_routes_bounds(lines)
    local routes_start = nil
    local routes_end = nil

    for index, line in ipairs(lines) do
        if not routes_start and line:match("<%s*Routes%f[%W]") then
            routes_start = index
        elseif routes_start and line:match("^%s*</Routes>") then
            routes_end = index
            break
        end
    end

    return routes_start, routes_end
end

--- Removes route-group comments that no longer contain routes.
---
---@param lines string[] App source lines.
---@return string[] lines Updated lines.
---@return boolean changed Whether any comments were removed.
---
local function cleanup_orphan_route_group_comments(lines)
    local routes_start, routes_end = find_routes_bounds(lines)

    if not routes_start or not routes_end or routes_end <= routes_start then
        return lines, false
    end

    local remove_indexes = {}
    local changed = false
    local index = routes_start + 1

    while index < routes_end do
        local line = lines[index]
        if is_group_comment_line(line) then
            local has_route = false
            local next_index = index + 1

            while next_index < routes_end do
                local next_line = lines[next_index]
                if is_group_comment_line(next_line) then
                    break
                end

                if is_route_start_line(next_line) then
                    has_route = true
                    break
                end

                next_index = next_index + 1
            end

            if not has_route then
                remove_indexes[index] = true
                changed = true

                local blank_index = index + 1
                while blank_index < routes_end and naming.trim(lines[blank_index]) == "" do
                    remove_indexes[blank_index] = true
                    blank_index = blank_index + 1
                end
            end

            index = next_index
        else
            index = index + 1
        end
    end

    if not changed then
        return lines, false
    end

    local updated = {}
    for line_index, line in ipairs(lines) do
        if not remove_indexes[line_index] then
            table.insert(updated, line)
        end
    end

    return updated, true
end

--- Normalizes blank lines inside the first Leptos `<Routes>` block.
---
---@param lines string[] lines Updated lines.
---@return string[] lines Updated lines.
---@return boolean changed Whether blank lines changed.
---
local function normalize_routes_blank_lines(lines)
    local routes_start, routes_end = find_routes_bounds(lines)

    if not routes_start or not routes_end or routes_end <= routes_start then
        return lines, false
    end

    local section = {}
    for index = routes_start + 1, routes_end - 1 do
        table.insert(section, lines[index])
    end

    while #section > 0 and naming.trim(section[1]) == "" do
        table.remove(section, 1)
    end

    while #section > 0 and naming.trim(section[#section]) == "" do
        table.remove(section, #section)
    end

    local compact = {}
    local previous_blank = false
    for _, line in ipairs(section) do
        local is_blank = naming.trim(line) == ""
        if not (is_blank and previous_blank) then
            table.insert(compact, line)
        end
        previous_blank = is_blank
    end

    local updated = {}
    for index = 1, routes_start do
        table.insert(updated, lines[index])
    end

    for _, line in ipairs(compact) do
        table.insert(updated, line)
    end

    for index = routes_end, #lines do
        table.insert(updated, lines[index])
    end

    return updated, not line_utils.equals(lines, updated)
end

--- Converts a route segment into a title-cased group label.
---
---@param segment string Route segment to convert.
---@return string title Human-readable route group label.
---
local function title_case(segment)
    local parts = {}
    for _, word in ipairs(naming.split_words(segment)) do
        table.insert(parts, word:sub(1, 1):upper() .. word:sub(2))
    end

    return table.concat(parts, " ")
end

--- Inserts a Leptos route into an app file.
---
--- Adds the route under an existing top-level route group when one is present,
--- or creates a new group before the closing `</Routes>` line.
---
---@param app_path string Path to the Rust app file.
---@param route_path string Route path for the `path!` macro.
---@param view_name string View component name for the route.
---@param opts table|nil Options; `private = true` writes `PrivateRoute`.
---@return boolean changed Whether the file changed.
---
function M.insert_route(app_path, route_path, view_name, opts)
    if not fs.exists(app_path) then
        return false
    end

    local options = opts or {}
    local lines = fs.read_lines(app_path)
    local indent = options.indent or "                    "
    local route_tag = options.private and "PrivateRoute" or "Route"
    local macro_path = route_path

    if route_path:sub(1, 6) == "/auth/" then
        macro_path = route_path:sub(2)
    elseif route_path == "/auth" then
        macro_path = "auth"
    end

    local route_line = string.format('%s<%s path=path!("%s") view=%s />', indent, route_tag, macro_path, view_name)
    if line_utils.has(lines, route_line) then
        return false
    end

    local top_segment = "home"
    if route_path ~= "/" then
        top_segment = naming.split_path_segments(route_path:gsub("^/+", ""):gsub("/+$", ""))[1] or "home"
    end

    local group_label
    if route_path == "/" then
        group_label = "Home"
    elseif top_segment == "auth" then
        group_label = "Auth routes"
    else
        group_label = title_case(top_segment)
    end

    local comment_line = indent .. "// " .. group_label
    local comment_index = nil
    local routes_end_index = nil

    for index, line in ipairs(lines) do
        if line:match("^%s*</Routes>") then
            routes_end_index = index
            break
        end

        if line == comment_line then
            comment_index = index
        end
    end

    if not routes_end_index then
        return false
    end

    if comment_index then
        local insert_at = routes_end_index
        for index = comment_index + 1, routes_end_index do
            if lines[index] and lines[index]:match("^%s*// ") then
                insert_at = index
                break
            end
        end

        while insert_at > comment_index + 1 and lines[insert_at - 1]:match("^%s*$") do
            insert_at = insert_at - 1
        end

        table.insert(lines, insert_at, route_line)
    else
        local block = {
            "",
            comment_line,
            route_line,
        }

        for index = #block, 1, -1 do
            table.insert(lines, routes_end_index, block[index])
        end
    end

    fs.write_lines(app_path, lines)
    return true
end

--- Removes Leptos routes that render a view component.
---
--- Handles single-line and multi-line route blocks, then removes orphan route
--- group comments and normalizes blank lines inside the routes block.
---
---@param app_path string Path to the Rust app file.
---@param view_name string View component name whose route should be removed.
---@return boolean changed Whether the file changed.
---
function M.remove_route_view(app_path, view_name)
    if not fs.exists(app_path) then
        return false
    end

    local view_pattern = "view%s*=%s*" .. vim.pesc(view_name) .. "%f[%W]"
    local lines = fs.read_lines(app_path)
    local updated = {}
    local changed = false
    local index = 1

    while index <= #lines do
        local line = lines[index]
        if not is_route_start_line(line) then
            table.insert(updated, line)
            index = index + 1
        else
            local block = {}
            local block_index = index
            local has_view = false

            while block_index <= #lines do
                local block_line = lines[block_index]
                table.insert(block, block_line)

                if block_line:match(view_pattern) then
                    has_view = true
                end

                if block_line:match("/>%s*$") or block_line:match(">%s*$") then
                    break
                end

                block_index = block_index + 1
            end

            if has_view and route_tag_is_self_closing(block) then
                changed = true
            else
                for _, block_line in ipairs(block) do
                    table.insert(updated, block_line)
                end
            end

            index = block_index + 1
        end
    end

    if not changed then
        return false
    end

    updated = cleanup_orphan_route_group_comments(updated)
    updated = normalize_routes_blank_lines(updated)

    fs.write_lines(app_path, updated)
    return true
end

return M
