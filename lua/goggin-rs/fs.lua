local M = {}

function M.exists(path)
    if not path or path == "" then
        return false
    end

    return vim.uv.fs_stat(path) ~= nil
end

function M.is_directory(path)
    if not path or path == "" then
        return false
    end

    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory"
end

function M.read_lines(path)
    if not M.exists(path) then
        return {}
    end

    return vim.fn.readfile(path)
end

function M.write_lines(path, lines)
    vim.fn.writefile(lines, path)
end

function M.ensure_directory(path)
    if path and path ~= "" and not M.is_directory(path) then
        vim.fn.mkdir(path, "p")
    end
end

function M.ensure_file(path)
    if not M.exists(path) then
        M.write_lines(path, {})
    end
end

return M
