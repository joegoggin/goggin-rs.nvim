local M = {}

function M.trim(value)
    return ((value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

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

function M.to_pascal_case(raw)
    local parts = {}

    for _, word in ipairs(M.split_words(raw)) do
        table.insert(parts, word:sub(1, 1):upper() .. word:sub(2))
    end

    return table.concat(parts, "")
end

function M.to_snake_case(raw)
    return table.concat(M.split_words(raw), "_")
end

function M.to_kebab_case(raw)
    return table.concat(M.split_words(raw), "-")
end

function M.split_path_segments(path)
    local segments = {}

    for segment in (path or ""):gmatch("[^/]+") do
        if segment ~= "" and segment ~= "." then
            table.insert(segments, segment)
        end
    end

    return segments
end

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

function M.route_segment_to_path(segment)
    local cleaned = M.trim(segment)
    if cleaned:sub(1, 1) == ":" then
        return cleaned
    end

    return M.to_kebab_case(cleaned)
end

return M
