--- Candidate root discovery from the active Neovim context.
---
--- Collects ordered project-root candidates from the current buffer path,
--- current working directory, and their ancestors.

local path = require("goggin-rs.infra.path")

local M = {}

--- Appends a directory and its ancestors to an ordered search-root list.
---
---@param start_dir string|nil Directory where ancestor collection starts.
---@param roots string[] Ordered search-root accumulator.
---@param seen table<string, boolean> Set of already-added normalized roots.
---
local function append_ancestors(start_dir, roots, seen)
    local current = path.normalize_dir(start_dir)

    while current and not seen[current] do
        seen[current] = true
        table.insert(roots, current)

        local parent = path.normalize_dir(vim.fn.fnamemodify(current, ":h"))
        if not parent or parent == current then
            break
        end

        current = parent
    end
end

--- Collects candidate project roots from the current Neovim context.
---
---@return string[] roots Ordered, de-duplicated candidate root directories.
---
function M.collect_search_roots()
    local roots = {}
    local seen = {}

    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file ~= "" then
        append_ancestors(vim.fn.fnamemodify(current_file, ":p:h"), roots, seen)
    end

    append_ancestors(vim.fn.getcwd(), roots, seen)

    local expanded = vim.fn.expand("%:p:h")
    if expanded ~= "" then
        append_ancestors(expanded, roots, seen)
    end

    return roots
end

return M
