--- Page style resolution helpers.
---
--- Resolves flat page, module-layout page, and page-local component SCSS
--- partial paths from generated Rust page paths.

local fs = require("goggin-rs.infra.fs")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.infra.path")
local scss = require("goggin-rs.scss")

local M = {}

--- Resolves the paired SCSS partial for a page entry.
---
---@param page table Page entry from `collect`.
---@param paths table Resolved project paths.
---@return string|nil scss_path Matching SCSS path when one exists.
---
function M.resolve_scss_path(page, paths)
    if not page or not paths or not paths.page_styles_dir then
        return nil
    end

    if page.is_module_layout then
        local module_style_dir = path.join(paths.page_styles_dir, page.module_relative_dir)
        local module_style = path.join(module_style_dir, "_page.scss")

        if fs.exists(module_style) then
            return module_style
        end

        return nil
    end

    local style_parent_dir = path.join(paths.page_styles_dir, page.rust_parent_relative)
    local by_stem = scss.resolve_partial_style(style_parent_dir, page.module_name)
    if by_stem then
        return by_stem
    end

    local component_kebab = naming.to_kebab_case(page.page_component_name)
    if component_kebab ~= "" then
        local by_component = path.join(style_parent_dir, "_" .. component_kebab .. ".scss")
        if fs.exists(by_component) then
            return by_component
        end

        local without_page_suffix = component_kebab:gsub("%-page$", "")
        if without_page_suffix ~= component_kebab then
            local by_component_without_page = path.join(style_parent_dir, "_" .. without_page_suffix .. ".scss")
            if fs.exists(by_component_without_page) then
                return by_component_without_page
            end
        end
    end

    return nil
end

--- Resolves the paired SCSS partial for a page-local component.
---
---@param page table Page entry from `collect`.
---@param rust_path string Page-local component Rust path.
---@param paths table Resolved project paths.
---@return string|nil scss_path Matching SCSS path when one exists.
---
function M.resolve_page_component_scss_path(page, rust_path, paths)
    local components_dir = path.join(page.page_dir, "components")
    local relative_from_components = path.relative(components_dir, rust_path)
    if relative_from_components == rust_path then
        return nil
    end

    local style_dir_relative = vim.fn.fnamemodify(relative_from_components, ":h")
    if style_dir_relative == "." then
        style_dir_relative = ""
    end

    local file_stem = vim.fn.fnamemodify(relative_from_components, ":t:r")
    local style_base_dir = path.join(paths.page_styles_dir, page.relative_dir, "components", style_dir_relative)

    return scss.resolve_partial_style(style_base_dir, file_stem)
end

--- Returns the SCSS forward target represented by a partial path.
---
---@param style_path string SCSS partial path.
---@return string target Forward target without a leading underscore.
---
function M.style_forward_target_from_path(style_path)
    local stem = vim.fn.fnamemodify(style_path, ":t:r")
    return stem:gsub("^_", "")
end

return M
