--- Rust source mutation helpers.
---
--- Maintains generated Rust module declarations, exports, Leptos route entries,
--- and empty module directories for Rust/Leptos project workflows.

local fs = require("goggin-rs.fs")
local line_utils = require("goggin-rs.lines")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.path")
local prune = require("goggin-rs.prune")
local touch = require("goggin-rs.touch")

local M = {}

--- Checks whether a string starts with a prefix.
---
---@param value string String to inspect.
---@param prefix string Prefix to match.
---@return boolean starts Whether the value starts with the prefix.
---
local function starts_with(value, prefix)
    return value:sub(1, #prefix) == prefix
end

--- Checks whether a trimmed line is a Rust module declaration.
---
---@param trimmed string Trimmed source line.
---@return boolean is_declaration Whether the line declares a module.
---
local function is_mod_declaration(trimmed)
    return trimmed:match("^pub%s+mod%s+") ~= nil or trimmed:match("^mod%s+") ~= nil
end

--- Checks whether a trimmed line declares a specific Rust module.
---
---@param trimmed string Trimmed source line.
---@param module_name string Module name to match.
---@return boolean is_declaration Whether the line declares the module.
---
local function is_module_declaration_for(trimmed, module_name)
    local module_pattern = vim.pesc(module_name)
    return trimmed:match("^pub%s+mod%s+" .. module_pattern .. "%s*;$") ~= nil
        or trimmed:match("^mod%s+" .. module_pattern .. "%s*;$") ~= nil
end

--- Checks whether a trimmed line is a Rust public-use declaration.
---
---@param trimmed string Trimmed source line.
---@return boolean is_declaration Whether the line is a public-use declaration.
---
local function is_pub_use_declaration(trimmed)
    return trimmed:match("^pub%s+use%s+") ~= nil
end

--- Extracts the expression from a trimmed Rust public-use declaration.
---
---@param trimmed string Trimmed source line.
---@return string|nil expression Expression after `pub use`, excluding the semicolon.
---
local function pub_use_expression(trimmed)
    return trimmed:match("^pub%s+use%s+(.+);$")
end

--- Normalizes a Rust `mod.rs` file layout.
---
--- Rebuilds the file with module declarations first, public exports second,
--- and other content last, inserting blank lines between groups.
---
---@param mod_path string Path to the `mod.rs` file.
---@return boolean changed Whether the file changed.
---
function M.normalize_mod_layout(mod_path)
    local lines = fs.read_lines(mod_path)
    local mod_lines = {}
    local use_lines = {}
    local other_lines = {}

    for _, line in ipairs(lines) do
        local trimmed = naming.trim(line)
        if is_mod_declaration(trimmed) then
            table.insert(mod_lines, trimmed)
        elseif is_pub_use_declaration(trimmed) then
            table.insert(use_lines, trimmed)
        elseif trimmed:match("^%s*$") then
            -- Blank lines are rebuilt below.
        else
            table.insert(other_lines, line)
        end
    end

    local normalized = {}
    for _, line in ipairs(mod_lines) do
        table.insert(normalized, line)
    end

    if #mod_lines > 0 and (#use_lines > 0 or #other_lines > 0) then
        table.insert(normalized, "")
    end

    for _, line in ipairs(use_lines) do
        table.insert(normalized, line)
    end

    if #other_lines > 0 then
        if #normalized > 0 and normalized[#normalized] ~= "" then
            table.insert(normalized, "")
        end

        for _, line in ipairs(other_lines) do
            table.insert(normalized, line)
        end
    end

    if line_utils.equals(lines, normalized) then
        return false
    end

    fs.write_lines(mod_path, normalized)
    return true
end

--- Ensures a Rust module declaration exists.
---
--- Treats public and private declarations for the same module as equivalent to
--- avoid adding duplicate declarations with opposite visibility.
---
---@param mod_path string Path to the `mod.rs` file.
---@param module_name string Rust module name to declare.
---@param opts table|nil Options; `private = true` writes `mod name;`.
---@return boolean changed Whether the file changed.
---
function M.ensure_mod_declaration(mod_path, module_name, opts)
    fs.ensure_file(mod_path)

    local private = opts and opts.private == true
    local declaration = (private and "mod " or "pub mod ") .. module_name .. ";"
    local opposite = (private and "pub mod " or "mod ") .. module_name .. ";"
    local lines = fs.read_lines(mod_path)

    if line_utils.has_trimmed(lines, declaration) or line_utils.has_trimmed(lines, opposite) then
        return false
    end

    local last_mod_index = nil
    local first_use_index = nil
    for index, line in ipairs(lines) do
        local trimmed = naming.trim(line)
        if is_mod_declaration(trimmed) then
            last_mod_index = index
        end

        if is_pub_use_declaration(trimmed) then
            first_use_index = index
            break
        end
    end

    if last_mod_index then
        table.insert(lines, last_mod_index + 1, declaration)
    elseif first_use_index then
        table.insert(lines, first_use_index, declaration)
    else
        table.insert(lines, declaration)
    end

    fs.write_lines(mod_path, lines)
    return true
end

--- Ensures a Rust public export declaration exists.
---
---@param mod_path string Path to the `mod.rs` file.
---@param use_expression string Expression placed after `pub use`.
---@return boolean changed Whether the file changed.
---
function M.ensure_use_declaration(mod_path, use_expression)
    fs.ensure_file(mod_path)

    local lines = fs.read_lines(mod_path)
    local declaration = "pub use " .. use_expression .. ";"
    if line_utils.has_trimmed(lines, declaration) then
        return false
    end

    local last_use_index = nil
    for index, line in ipairs(lines) do
        if is_pub_use_declaration(naming.trim(line)) then
            last_use_index = index
        end
    end

    if last_use_index then
        table.insert(lines, last_use_index + 1, declaration)
    else
        table.insert(lines, declaration)
    end

    fs.write_lines(mod_path, lines)
    return true
end

--- Removes a module declaration and direct exports for a module.
---
---@param mod_path string Path to the `mod.rs` file.
---@param module_name string Rust module name to remove.
---@return boolean changed Whether the file changed.
---
function M.remove_module_reference(mod_path, module_name)
    if not fs.exists(mod_path) then
        return false
    end

    local lines = fs.read_lines(mod_path)
    local updated = {}
    local changed = false

    for _, line in ipairs(lines) do
        local trimmed = naming.trim(line)
        if is_module_declaration_for(trimmed, module_name) then
            changed = true
        else
            local expression = pub_use_expression(trimmed)
            if expression then
                expression = naming.trim(expression)
                if expression == module_name or starts_with(expression, module_name .. "::") then
                    changed = true
                else
                    table.insert(updated, line)
                end
            else
                table.insert(updated, line)
            end
        end
    end

    if not changed then
        return false
    end

    fs.write_lines(mod_path, updated)
    M.normalize_mod_layout(mod_path)
    return true
end

--- Removes a symbol from a Rust public-use expression.
---
--- Supports direct symbols, terminal path symbols, and grouped imports such as
--- `module::{One, Two}`.
---
---@param expression string Use expression without `pub use` or trailing semicolon.
---@param symbol string Symbol name to remove.
---@return string|nil expression Updated expression, or nil when the entire use should be removed.
---@return boolean changed Whether the expression changed.
---
local function remove_symbol_from_use_expression(expression, symbol)
    local prefix, body = expression:match("^(.-)::%s*{%s*(.-)%s*}$")
    if prefix and body then
        local items = {}
        for item in body:gmatch("[^,]+") do
            table.insert(items, naming.trim(item))
        end

        local kept = {}
        local changed = false
        for _, item in ipairs(items) do
            if item == symbol then
                changed = true
            else
                table.insert(kept, item)
            end
        end

        if not changed then
            return expression, false
        end

        if #kept == 0 then
            return nil, true
        end

        if #kept == 1 then
            return prefix .. "::" .. kept[1], true
        end

        return prefix .. "::{" .. table.concat(kept, ", ") .. "}", true
    end

    local symbol_pattern = vim.pesc(symbol)
    if expression == symbol or expression:match("::" .. symbol_pattern .. "$") then
        return nil, true
    end

    return expression, false
end

--- Removes a symbol from Rust public export declarations.
---
---@param mod_path string Path to the `mod.rs` file.
---@param symbol string Symbol name to remove.
---@return boolean changed Whether the file changed.
---
function M.remove_use_symbol(mod_path, symbol)
    if not fs.exists(mod_path) then
        return false
    end

    local lines = fs.read_lines(mod_path)
    local updated = {}
    local changed = false

    for _, line in ipairs(lines) do
        local trimmed = naming.trim(line)
        local expression = pub_use_expression(trimmed)
        if expression then
            local next_expression, did_change = remove_symbol_from_use_expression(naming.trim(expression), symbol)
            if did_change then
                changed = true
            end

            if next_expression then
                table.insert(updated, "pub use " .. next_expression .. ";")
            end
        else
            table.insert(updated, line)
        end
    end

    if not changed then
        return false
    end

    fs.write_lines(mod_path, updated)
    M.normalize_mod_layout(mod_path)
    return true
end

--- Removes a symbol from every `mod.rs` file under a root.
---
---@param root_dir string Directory tree to scan.
---@param symbol string Symbol name to remove.
---@param tracker table|nil Touched-file tracker to mark changed modules.
---@return integer changed Number of module files changed.
---
function M.remove_use_symbol_tree(root_dir, symbol, tracker)
    local mod_files = vim.fn.glob(path.join(root_dir, "**/mod.rs"), true, true)
    local root_mod = path.join(root_dir, "mod.rs")
    if fs.exists(root_mod) then
        table.insert(mod_files, root_mod)
    end

    local seen = {}
    local changed = 0
    for _, mod_path in ipairs(mod_files) do
        if not seen[mod_path] then
            seen[mod_path] = true
            if M.remove_use_symbol(mod_path, symbol) then
                touch.mark(tracker, mod_path)
                changed = changed + 1
            end
        end
    end

    return changed
end

--- Checks whether a line starts a Leptos route component.
---
---@param line string Source line to inspect.
---@return boolean is_route Whether the line starts `Route` or `PrivateRoute`.
---
local function is_route_start_line(line)
    return line:match("<%s*Route%f[%W]") ~= nil or line:match("<%s*PrivateRoute%f[%W]") ~= nil
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
---@param lines string[] App source lines.
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

                if block_line:match("/>%s*$") then
                    break
                end

                block_index = block_index + 1
            end

            if has_view then
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

--- Prunes empty Rust module directories and removes parent references.
---
---@param start_dir string Directory where pruning starts.
---@param root_dir string Boundary directory that is never deleted.
---@param tracker table|nil Touched-file tracker for deleted paths and updated parents.
---
function M.prune_empty_dirs(start_dir, root_dir, tracker)
    prune.empty_dirs(start_dir, root_dir, {
        marker_name = "mod.rs",
        tracker = tracker,
        on_pruned_parent = function(parent, module_name, active_tracker)
            local mod_path = path.join(parent, "mod.rs")
            if M.remove_module_reference(mod_path, module_name) then
                touch.mark(active_tracker, mod_path)
            end
        end,
    })
end

return M
