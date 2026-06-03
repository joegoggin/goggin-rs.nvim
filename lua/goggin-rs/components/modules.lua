--- Component Rust module maintenance.
---
--- Updates component `mod.rs` files and root exports when generated components
--- are added under root or nested component directories.

local fs = require("goggin-rs.infra.fs")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.infra.path")
local rust = require("goggin-rs.rust")
local touch = require("goggin-rs.infra.touch")

local M = {}

--- Ensures Rust module declarations and exports for a generated component.
---
---@param paths table Resolved project paths.
---@param relative_dir string Normalized component subdirectory.
---@param module_name string Component module name.
---@param component_name string Component function name.
---@param tracker table Touched-file tracker.
---
function M.update_rust_modules(paths, relative_dir, module_name, component_name, tracker)
    local rust_segments = relative_dir == "" and {} or naming.split_path_segments(relative_dir)
    local current_rust_dir = paths.components_dir

    for index, segment in ipairs(rust_segments) do
        local parent_mod = path.join(current_rust_dir, "mod.rs")
        touch.mark_when_changed(tracker, parent_mod, rust.ensure_mod_declaration(parent_mod, segment))

        if index == 1 then
            local root_mod = path.join(paths.components_dir, "mod.rs")
            touch.mark_when_changed(tracker, root_mod, rust.ensure_use_declaration(root_mod, segment .. "::*"))
        end

        current_rust_dir = path.join(current_rust_dir, segment)
        fs.ensure_directory(current_rust_dir)
        fs.ensure_file(path.join(current_rust_dir, "mod.rs"))
    end

    local target_mod = path.join(current_rust_dir, "mod.rs")
    touch.mark_when_changed(tracker, target_mod, rust.ensure_mod_declaration(target_mod, module_name))
    touch.mark_when_changed(
        tracker,
        target_mod,
        rust.ensure_use_declaration(target_mod, module_name .. "::" .. component_name)
    )
    touch.mark_when_changed(tracker, target_mod, rust.normalize_mod_layout(target_mod))

    if #rust_segments > 0 then
        local root_mod = path.join(paths.components_dir, "mod.rs")
        touch.mark_when_changed(tracker, root_mod, rust.normalize_mod_layout(root_mod))
    end
end

return M
