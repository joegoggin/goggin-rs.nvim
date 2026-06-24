--- Style creation and deletion workflows.
---
--- Creates missing SCSS partials with Rust class setup insertion and deletes
--- existing style partials with SCSS forward cleanup.

local fs = require("goggin-rs.infra.fs")
local path = require("goggin-rs.infra.path")
local rust = require("goggin-rs.rust")
local scss = require("goggin-rs.scss")
local touch = require("goggin-rs.infra.touch")

local M = {}

--- Shows a warning notification unless disabled.
---
---@param message string Message to display.
---@param opts table|nil Workflow options.
---
local function notify_warn(message, opts)
    if not opts or opts.notify ~= false then
        vim.notify(message, vim.log.levels.WARN)
    end
end

--- Shows an info notification unless disabled.
---
---@param message string Message to display.
---@param opts table|nil Workflow options.
---
local function notify_info(message, opts)
    if not opts or opts.notify ~= false then
        vim.notify(message)
    end
end

--- Opens a Rust/style pair after the current callback completes.
---
---@param rust_path string Rust file path.
---@param scss_path string|nil SCSS file path.
---
local function open_created_pair(rust_path, scss_path)
    vim.schedule(function()
        if not fs.exists(rust_path) then
            notify_warn("Rust file not found: " .. rust_path)
            return
        end

        vim.cmd("edit " .. vim.fn.fnameescape(rust_path))

        if scss_path and fs.exists(scss_path) then
            vim.cmd("vsplit " .. vim.fn.fnameescape(scss_path))
            vim.cmd("wincmd h")
        elseif scss_path then
            notify_warn("Style file not found: " .. scss_path)
        end
    end)
end

--- Validates the minimum fields needed for a style item mutation.
---
---@param item table|nil Style item to validate.
---@return string|nil err Validation error.
---
local function validate_item(item)
    if not item then
        return "Style item is required."
    end

    if not item.rust_path or item.rust_path == "" then
        return "Style item is missing a Rust path."
    end

    if not item.scss_path or item.scss_path == "" then
        return "Style item is missing an SCSS path."
    end

    if not item.style_root or item.style_root == "" then
        return "Style item is missing a style root."
    end

    if not item.style_target or item.style_target == "" then
        return "Style item is missing a style target."
    end

    return nil
end

--- Creates a missing SCSS style and updates related Rust/SCSS setup.
---
---@param item table Style item from `collect`.
---@param opts table|nil Options; accepts `open`, `format_opts`, and `notify`.
---@return table|nil result Mutation result.
---@return string|nil err Error message when creation fails.
---
function M.create_missing_style(item, opts)
    local options = opts or {}
    local validation_error = validate_item(item)
    if validation_error then
        notify_warn(validation_error, options)
        return nil, validation_error
    end

    if fs.exists(item.scss_path) then
        local err = "Style file already exists: " .. item.scss_path
        notify_warn(err, options)
        if options.open then
            open_created_pair(item.rust_path, item.scss_path)
        end
        return nil, err
    end

    local class_name = item.class_name
    if not class_name or class_name == "" then
        local err = "Could not derive class name for " .. tostring(item.component_name)
        notify_warn(err, options)
        return nil, err
    end

    local tracker = touch.new()
    local style_dir = vim.fn.fnamemodify(item.scss_path, ":h")

    fs.ensure_directory(style_dir)
    fs.write_lines(item.scss_path, scss.build_class_template(class_name))
    touch.mark(tracker, item.scss_path)

    scss.ensure_forward_chain(item.style_root, item.style_segments or {}, item.style_target, tracker)

    local rust_changed, rust_error = rust.ensure_class_setup(item.rust_path, class_name)
    if rust_changed then
        touch.mark(tracker, item.rust_path)
    end

    if rust_error then
        notify_warn(rust_error .. "\n" .. item.rust_path, options)
    end

    local formatted = touch.format_touched(tracker, options.format_opts)

    if options.open then
        open_created_pair(item.rust_path, item.scss_path)
    end

    return {
        item = item,
        rust_path = item.rust_path,
        scss_path = item.scss_path,
        class_name = class_name,
        rust_class_setup_error = rust_error,
        touched_paths = tracker:paths(),
        formatted_count = formatted,
    }
end

--- Deletes an existing SCSS style and cleans related forwards/directories.
---
---@param item table Style item from `collect`.
---@param opts table|nil Options; accepts `format_opts` and `notify`.
---@return table|nil result Mutation result.
---@return string|nil err Error message when deletion fails.
---
function M.delete_style(item, opts)
    local options = opts or {}
    local validation_error = validate_item(item)
    if validation_error then
        notify_warn(validation_error, options)
        return nil, validation_error
    end

    if not fs.exists(item.scss_path) then
        local err = "Style file not found: " .. item.scss_path
        notify_warn(err, options)
        return nil, err
    end

    local tracker = touch.new()
    local removed, remove_error = fs.delete_path(item.scss_path, false)
    if not removed then
        notify_warn(remove_error, options)
        return nil, remove_error
    end

    touch.mark(tracker, item.scss_path)

    local style_dir = vim.fn.fnamemodify(item.scss_path, ":h")
    scss.remove_forward(path.join(style_dir, "index.scss"), item.style_target, tracker)
    scss.prune_empty_dirs(style_dir, item.style_root, tracker)

    local formatted = touch.format_touched(tracker, options.format_opts)
    notify_info("Successfully deleted style for " .. tostring(item.component_name), options)

    return {
        item = item,
        rust_path = item.rust_path,
        scss_path = item.scss_path,
        touched_paths = tracker:paths(),
        formatted_count = formatted,
    }
end

return M
