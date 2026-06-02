local M = {}

function M.join(...)
    local parts = {}

    for index = 1, select("#", ...) do
        local part = select(index, ...)
        if part and part ~= "" then
            table.insert(parts, part)
        end
    end

    return table.concat(parts, "/")
end

function M.relative(root, path)
    local prefix = root .. "/"
    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end

    if path == root then
        return ""
    end

    return path
end

function M.is_absolute(path)
    if not path or path == "" then
        return false
    end

    return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

function M.normalize_dir(path)
    if not path or path == "" then
        return nil
    end

    local normalized = vim.fn.fnamemodify(path, ":p")
    if normalized == "" then
        return nil
    end

    normalized = normalized:gsub("/+$", "")
    if normalized == "" then
        return "/"
    end

    return normalized
end

return M
