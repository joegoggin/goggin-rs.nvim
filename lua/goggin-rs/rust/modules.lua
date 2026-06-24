--- Rust `mod.rs` declaration and module reference mutation helpers.
---
--- Adds, removes, and normalizes Rust module declarations and direct exports
--- while preserving attributed and inline module content.

local fs = require("goggin-rs.infra.fs")
local line_utils = require("goggin-rs.infra.lines")
local naming = require("goggin-rs.naming")
local uses = require("goggin-rs.rust.uses")

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
    return trimmed:match("^pub%s+mod%s+[%a_][%w_]*%s*;$") ~= nil or trimmed:match("^mod%s+[%a_][%w_]*%s*;$") ~= nil
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

    local previous_was_attribute = false
    for _, line in ipairs(lines) do
        local trimmed = naming.trim(line)
        if is_attribute_line(trimmed) then
            table.insert(other_lines, line)
            previous_was_attribute = true
        elseif not previous_was_attribute and is_mod_declaration(trimmed) then
            table.insert(mod_lines, trimmed)
            previous_was_attribute = false
        elseif not previous_was_attribute and uses.is_pub_use_declaration(trimmed) then
            table.insert(use_lines, trimmed)
            previous_was_attribute = false
        elseif trimmed:match("^%s*$") then
            -- Blank lines are rebuilt below.
        else
            table.insert(other_lines, line)
            previous_was_attribute = false
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

        if uses.is_pub_use_declaration(trimmed) then
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
    local pending_attributes = {}

    for _, line in ipairs(lines) do
        local trimmed = naming.trim(line)
        if is_attribute_line(trimmed) or (#pending_attributes > 0 and trimmed == "") then
            table.insert(pending_attributes, line)
        elseif is_module_declaration_for(trimmed, module_name) then
            pending_attributes = {}
            changed = true
        else
            local expression = uses.pub_use_expression(trimmed)
            if expression then
                expression = naming.trim(expression)
                if expression == module_name or starts_with(expression, module_name .. "::") then
                    pending_attributes = {}
                    changed = true
                else
                    pending_attributes = flush_pending_attributes(updated, pending_attributes)
                    table.insert(updated, line)
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
    M.normalize_mod_layout(mod_path)
    return true
end

return M
