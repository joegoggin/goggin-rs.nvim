--- Rust public-use declaration mutation helpers.
---
--- Adds public exports and removes symbols from direct, path-terminal, grouped,
--- and tree-scanned Rust `pub use` declarations.

local fs = require("goggin-rs.infra.fs")
local line_utils = require("goggin-rs.infra.lines")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.infra.path")
local touch = require("goggin-rs.infra.touch")

local M = {}

--- Checks whether a trimmed line is a Rust public-use declaration.
---
---@param trimmed string Trimmed source line.
---@return boolean is_declaration Whether the line is a public-use declaration.
---
function M.is_pub_use_declaration(trimmed)
    return trimmed:match("^pub%s+use%s+.+;$") ~= nil
end

--- Extracts the expression from a trimmed Rust public-use declaration.
---
---@param trimmed string Trimmed source line.
---@return string|nil expression Expression after `pub use`, excluding the semicolon.
---
function M.pub_use_expression(trimmed)
    return trimmed:match("^pub%s+use%s+(.+);$")
end

--- Checks whether a trimmed line is a Rust attribute.
---
---@param trimmed string Trimmed source line.
---@return boolean is_attribute Whether the line is an outer or inner attribute.
---
local function is_attribute_line(trimmed)
    return trimmed:match("^#%!%[.*%]$") ~= nil or trimmed:match("^#%[.*%]$") ~= nil
end

--- Appends pending attribute lines before the next preserved item.
---
---@param updated string[] Output line accumulator.
---@param pending_attributes string[] Attribute lines waiting for their item.
---@return string[] pending_attributes Cleared pending attribute list.
---
local function flush_pending_attributes(updated, pending_attributes)
    for _, attribute_line in ipairs(pending_attributes) do
        table.insert(updated, attribute_line)
    end

    return {}
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
        if M.is_pub_use_declaration(naming.trim(line)) then
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
    local pending_attributes = {}

    for _, line in ipairs(lines) do
        local trimmed = naming.trim(line)
        if is_attribute_line(trimmed) or (#pending_attributes > 0 and trimmed == "") then
            table.insert(pending_attributes, line)
        else
            local expression = M.pub_use_expression(trimmed)
            if expression then
                local next_expression, did_change = remove_symbol_from_use_expression(naming.trim(expression), symbol)
                if did_change then
                    changed = true
                end

                if next_expression then
                    pending_attributes = flush_pending_attributes(updated, pending_attributes)
                    table.insert(updated, "pub use " .. next_expression .. ";")
                else
                    pending_attributes = {}
                end
            else
                pending_attributes = flush_pending_attributes(updated, pending_attributes)
                table.insert(updated, line)
            end
        end
    end

    flush_pending_attributes(updated, pending_attributes)

    if not changed then
        return false
    end

    fs.write_lines(mod_path, updated)
    require("goggin-rs.rust.modules").normalize_mod_layout(mod_path)
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

return M
