--- Rust class-name setup helpers.
---
--- Extracts existing `ClassNameUtil` class names and inserts the import plus
--- root-class setup block into existing Leptos component functions.

local fs = require("goggin-rs.infra.fs")
local naming = require("goggin-rs.naming")

local M = {}

--- Extracts an existing `ClassNameUtil` class from a Rust source file.
---
---@param file_path string Rust file path.
---@return string|nil class_name Existing class name when one is found.
---
function M.extract_existing_class_name(file_path)
    for _, line in ipairs(fs.read_lines(file_path)) do
        local direct = line:match('ClassNameUtil::new%("([^"]+)"')
        if direct then
            return direct
        end

        local _, child = line:match('ClassNameUtil::new_with_parent%("([^"]+)",%s*"([^"]+)"')
        if child then
            return child
        end

        local layout = line:match('ClassNameUtil::new_layout_class_name%("([^"]+)"')
        if layout then
            return layout
        end
    end

    return nil
end

--- Checks whether Rust source already contains class-name setup.
---
---@param lines string[] Rust source lines.
---@return boolean has_setup Whether class setup exists.
---
function M.has_class_setup(lines)
    for _, line in ipairs(lines) do
        if
            line:find("ClassNameUtil::new(", 1, true)
            or line:find("ClassNameUtil::new_with_parent(", 1, true)
            or line:find("ClassNameUtil::new_layout_class_name(", 1, true)
        then
            return true
        end
    end

    return false
end

--- Ensures `ClassNameUtil` is imported in Rust source lines.
---
---@param lines string[] Rust source lines to mutate.
---@return boolean changed Whether the import was inserted.
---
function M.ensure_class_name_import(lines)
    for _, line in ipairs(lines) do
        if line:find("ClassNameUtil", 1, true) then
            return false
        end
    end

    local import_line = "use crate::utils::class_name::ClassNameUtil;"
    local last_use_index = nil

    for index, line in ipairs(lines) do
        if line:match("^%s*use%s+") then
            last_use_index = index
        end
    end

    if last_use_index then
        table.insert(lines, last_use_index + 1, import_line)
    else
        table.insert(lines, 1, import_line)
        table.insert(lines, 2, "")
    end

    return true
end

--- Locates the first `#[component]` function body.
---
---@param lines string[] Rust source lines.
---@return table|nil component_fn Component function metadata.
---
local function find_component_function(lines)
    local awaiting_component_fn = false
    local signature_start = nil
    local signature_lines = {}

    for index, line in ipairs(lines) do
        if line:match("^%s*#%s*%[%s*component%s*%]") then
            awaiting_component_fn = true
            signature_start = nil
            signature_lines = {}
        elseif awaiting_component_fn then
            if not signature_start then
                if line:match("^%s*pub%s+fn%s+") then
                    signature_start = index
                    table.insert(signature_lines, line)

                    if line:find("{", 1, true) then
                        return {
                            signature_start = signature_start,
                            body_start = index,
                            signature_text = table.concat(signature_lines, " "),
                            fn_indent = line:match("^(%s*)") or "",
                        }
                    end
                elseif not line:match("^%s*$") and not line:match("^%s*#") then
                    awaiting_component_fn = false
                end
            else
                table.insert(signature_lines, line)

                if line:find("{", 1, true) then
                    return {
                        signature_start = signature_start,
                        body_start = index,
                        signature_text = table.concat(signature_lines, " "),
                        fn_indent = lines[signature_start]:match("^(%s*)") or "",
                    }
                end
            end
        end
    end

    return nil
end

--- Inserts `ClassNameUtil` root-class setup into source lines.
---
---@param lines string[] Rust source lines to mutate.
---@param class_name string CSS class name.
---@return boolean inserted Whether setup was inserted.
---@return string|nil err Error message when insertion cannot be performed.
---
function M.insert_class_setup(lines, class_name)
    if M.has_class_setup(lines) then
        return false, nil
    end

    local component_fn = find_component_function(lines)
    if not component_fn then
        return false, "Could not locate #[component] function body for class setup."
    end

    local has_class_param = component_fn.signature_text:match("class%s*:%s*Option%s*<%s*String%s*>") ~= nil
    local class_arg = has_class_param and "class" or "None"
    local var_name = naming.to_snake_case(class_name)
    if var_name == "" then
        var_name = "component_class"
    end

    local body_indent = (component_fn.fn_indent or "") .. "    "
    local block = {
        body_indent .. "// Classes",
        string.format('%slet class_name = ClassNameUtil::new("%s", %s);', body_indent, class_name, class_arg),
        string.format("%slet %s = class_name.get_root_class();", body_indent, var_name),
        "",
    }

    local insert_at = component_fn.body_start + 1
    for offset, entry in ipairs(block) do
        table.insert(lines, insert_at + offset - 1, entry)
    end

    return true, nil
end

--- Ensures an existing Rust component has `ClassNameUtil` setup.
---
---@param rust_path string Rust file path.
---@param class_name string CSS class name.
---@return boolean changed Whether the file changed.
---@return string|nil err Warning-grade error when setup insertion fails.
---
function M.ensure_class_setup(rust_path, class_name)
    local lines = fs.read_lines(rust_path)
    if #lines == 0 then
        return false, "Rust file is empty or missing: " .. rust_path
    end

    local changed = false
    if M.ensure_class_name_import(lines) then
        changed = true
    end

    local inserted, insert_error = M.insert_class_setup(lines, class_name)
    if inserted then
        changed = true
    end

    if changed then
        fs.write_lines(rust_path, lines)
    end

    return changed, insert_error
end

return M
