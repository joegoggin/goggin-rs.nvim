--- Component file opening helpers.
---
--- Opens component Rust and SCSS files from picker and generation workflows,
--- deferring new-file opens until UI callbacks complete.

local fs = require("goggin-rs.infra.fs")

local M = {}

--- Shows a warning notification.
---
---@param message string Message to display.
---
function M.notify_warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

--- Opens a Rust component and its paired SCSS partial when present.
---
---@param component table Component entry containing `rust_path` and optional `scss_path`.
---
function M.open_pair(component)
    vim.cmd("edit " .. vim.fn.fnameescape(component.rust_path))

    if component.scss_path then
        vim.cmd("vsplit " .. vim.fn.fnameescape(component.scss_path))
        vim.cmd("wincmd h")
    end
end

--- Opens a newly-created component pair after the current UI callback returns.
---
---@param rust_path string Rust file path.
---@param scss_path string|nil SCSS file path.
---
function M.open_created_pair(rust_path, scss_path)
    vim.schedule(function()
        if not fs.exists(rust_path) then
            M.notify_warn("Rust file not found: " .. rust_path)
            return
        end

        M.open_pair({
            rust_path = rust_path,
            scss_path = scss_path and fs.exists(scss_path) and scss_path or nil,
        })

        if scss_path and not fs.exists(scss_path) then
            M.notify_warn("Style file not found: " .. scss_path)
        end
    end)
end

return M
