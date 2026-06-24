--- Case conversion helpers for generated Rust and style names.
---
--- Splits free-form user input into words and converts it into PascalCase,
--- snake_case, kebab-case, and normalized relative paths.

local M = {}

--- Trims leading and trailing whitespace.
---
---@param value string|nil Value to trim.
---@return string trimmed Trimmed value, or an empty string for nil.
---
function M.trim(value)
    return ((value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Splits mixed-case, snake-case, kebab-case, or spaced input into words.
---
---@param raw string|nil Raw value to split.
---@return string[] words Lowercase words extracted from the input.
---
function M.split_words(raw)
    local value = M.trim(raw)
    if value == "" then
        return {}
    end

    value = value:gsub("[-_]+", " ")
    value = value:gsub("(%l)(%u)", "%1 %2")
    value = value:gsub("(%u)(%u%l)", "%1 %2")

    local words = {}
    for word in value:gmatch("[%w]+") do
        table.insert(words, word:lower())
    end

    return words
end

--- Converts input text to PascalCase.
---
---@param raw string|nil Raw value to convert.
---@return string pascal PascalCase value.
---
function M.to_pascal_case(raw)
    local parts = {}

    for _, word in ipairs(M.split_words(raw)) do
        table.insert(parts, word:sub(1, 1):upper() .. word:sub(2))
    end

    return table.concat(parts, "")
end

--- Converts input text to snake_case.
---
---@param raw string|nil Raw value to convert.
---@return string snake Snake-case value using underscores.
---
function M.to_snake_case(raw)
    return table.concat(M.split_words(raw), "_")
end

--- Converts input text to kebab-case.
---
---@param raw string|nil Raw value to convert.
---@return string kebab Kebab-case value using hyphens.
---
function M.to_kebab_case(raw)
    return table.concat(M.split_words(raw), "-")
end

return M
