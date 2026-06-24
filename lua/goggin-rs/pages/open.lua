--- Page file opening helpers.
---
--- Opens page Rust and SCSS files from picker and generation workflows,
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

--- Opens a Rust page and its paired SCSS partial when present.
---
---@param page table Page entry containing `page_rs` and optional `page_style_path`.
---
function M.open_pair(page)
    local rust_path = page.page_rs or page.rust_path
    local scss_path = page.page_style_path or page.scss_path

    vim.cmd("edit " .. vim.fn.fnameescape(rust_path))

    if scss_path then
        vim.cmd("vsplit " .. vim.fn.fnameescape(scss_path))
        vim.cmd("wincmd h")
    end
end

--- Opens a newly-created page pair after the current UI callback returns.
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
            page_rs = rust_path,
            page_style_path = scss_path and fs.exists(scss_path) and scss_path or nil,
        })

        if scss_path and not fs.exists(scss_path) then
            M.notify_warn("Style file not found: " .. scss_path)
        end
    end)
end

return M
