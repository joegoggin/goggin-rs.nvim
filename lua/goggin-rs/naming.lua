--- Naming helpers for generated Rust, SCSS, and route artifacts.
---
--- Normalizes user-provided names and route segments into casing conventions
--- used by files, modules, component names, and URLs.

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
        local snake_segment = M.to_snake_case(segment)
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
    local cleaned = M.trim(segment)
    cleaned = cleaned:gsub("^:", "")
    cleaned = cleaned:gsub("%*", "all")

    local snake = M.to_snake_case(cleaned)
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
    local cleaned = M.trim(segment)
    if cleaned:sub(1, 1) == ":" then
        return cleaned
    end

    return M.to_kebab_case(cleaned)
end

return M
