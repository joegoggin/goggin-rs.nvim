--- Touched-file tracking and formatting helpers.
---
--- Tracks changed files in first-seen order and formats touched Rust and SCSS
--- files through Neovim's synchronous LSP formatting API.

local fs = require("goggin-rs.fs")

local M = {}

--- Creates an ordered touched-file tracker.
---
---@return table tracker Tracker with `mark` and `paths` methods.
---
function M.new()
    local tracker = {
        _seen = {},
        _paths = {},
    }

    --- Records a path if it has not already been seen.
    ---
    ---@param file_path string|nil Path to record.
    ---@return boolean marked Whether the path was newly recorded.
    ---
    function tracker:mark(file_path)
        if not file_path or file_path == "" or self._seen[file_path] then
            return false
        end

        self._seen[file_path] = true
        table.insert(self._paths, file_path)
        return true
    end

    --- Returns touched paths in first-seen order.
    ---
    ---@return string[] paths Copy of tracked paths.
    ---
    function tracker:paths()
        local copy = {}
        for _, file_path in ipairs(self._paths) do
            table.insert(copy, file_path)
        end

        return copy
    end

    return tracker
end

--- Marks a path on an optional touched-file tracker.
---
---@param tracker table|nil Touched-file tracker with a `mark` method.
---@param file_path string|nil Path to record.
---@return boolean marked Whether the path was newly recorded.
---
function M.mark(tracker, file_path)
    if tracker and type(tracker.mark) == "function" then
        return tracker:mark(file_path)
    end

    return false
end

--- Checks whether any LSP client attached to a buffer supports formatting.
---
---@param bufnr integer Buffer number to inspect.
---@return boolean supports Whether a formatting-capable LSP client is attached.
---
local function supports_buffer_formatting(bufnr)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.supports_method then
            local ok, supported = pcall(function()
                return client:supports_method("textDocument/formatting")
            end)

            if ok and supported then
                return true
            end
        end
    end

    return false
end

--- Formats an existing file through Neovim LSP and writes modifications.
---
--- Loads the file into a buffer when needed, runs synchronous formatting when a
--- formatting-capable LSP client is attached, writes formatter changes, and
--- deletes temporary hidden buffers opened only for formatting. Skips buffers
--- that already have unsaved changes to avoid writing unrelated edits.
---
---@param file_path string Path to the file to format.
---@param opts table|nil Formatting options.
---@return boolean formatted Whether LSP formatting ran successfully.
---
function M.format_file(file_path, opts)
    if not fs.exists(file_path) then
        return false
    end

    local options = opts or {}
    local bufnr = vim.fn.bufadd(file_path)
    local was_loaded = vim.api.nvim_buf_is_loaded(bufnr)

    if not was_loaded then
        vim.fn.bufload(bufnr)
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    if was_loaded and vim.bo[bufnr].modified then
        vim.notify("Skipping formatting for modified buffer " .. file_path, vim.log.levels.WARN)
        return false
    end

    local formatted = false
    if supports_buffer_formatting(bufnr) then
        local format_ok, format_err = pcall(vim.lsp.buf.format, {
            bufnr = bufnr,
            async = false,
            timeout_ms = options.timeout_ms or 5000,
        })

        if format_ok then
            formatted = true
        else
            vim.notify("Formatting failed for " .. file_path .. ":\n" .. tostring(format_err), vim.log.levels.WARN)
        end
    end

    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
        local write_ok, write_err = pcall(vim.api.nvim_buf_call, bufnr, function()
            vim.cmd("silent write")
        end)

        if not write_ok then
            vim.notify(
                "Failed to write formatted file " .. file_path .. ":\n" .. tostring(write_err),
                vim.log.levels.WARN
            )
        end
    end

    if
        not was_loaded
        and vim.api.nvim_buf_is_valid(bufnr)
        and vim.fn.bufwinnr(bufnr) == -1
        and not vim.bo[bufnr].modified
    then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end

    return formatted
end

--- Normalizes a tracker object or raw path list into paths.
---
---@param tracker_or_paths table|nil Touched-file tracker or raw path list.
---@return string[] paths Paths to consider for formatting.
---
local function tracked_paths(tracker_or_paths)
    if not tracker_or_paths then
        return {}
    end

    if type(tracker_or_paths.paths) == "function" then
        return tracker_or_paths:paths()
    end

    return tracker_or_paths
end

--- Formats touched Rust and SCSS files.
---
---@param tracker_or_paths table|nil Touched-file tracker or raw path list.
---@param opts table|nil Formatting options passed to `format_file`.
---@return integer count Number of files successfully formatted.
---
function M.format_touched(tracker_or_paths, opts)
    local seen = {}
    local formatted = 0

    for _, file_path in ipairs(tracked_paths(tracker_or_paths)) do
        local should_format = file_path:match("%.rs$") or file_path:match("%.scss$")
        if should_format and not seen[file_path] then
            seen[file_path] = true
            if M.format_file(file_path, opts) then
                formatted = formatted + 1
            end
        end
    end

    return formatted
end

return M
