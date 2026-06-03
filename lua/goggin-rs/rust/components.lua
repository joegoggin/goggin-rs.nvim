--- Rust component source parsing helpers.
---
--- Reads Rust source files and extracts Leptos component function names while
--- skipping attributes and non-component files.

local fs = require("goggin-rs.infra.fs")

local M = {}

--- Parses the first Leptos component function name from a Rust file.
---
---@param file_path string Rust file path.
---@return string|nil component_name Parsed component function name.
---
function M.component_name_from_file(file_path)
    local awaiting_component_fn = false

    for _, line in ipairs(fs.read_lines(file_path)) do
        if line:match("^%s*#%s*%[%s*component%s*%]") then
            awaiting_component_fn = true
        elseif awaiting_component_fn then
            local component_name = line:match("^%s*pub%s+fn%s+([%w_]+)")
            if component_name then
                return component_name
            end

            local is_attribute = line:match("^%s*#") ~= nil
            local is_blank = line:match("^%s*$") ~= nil
            if not is_attribute and not is_blank then
                awaiting_component_fn = false
            end
        end
    end

    return nil
end

return M
