--- Empty Rust module directory pruning.
---
--- Removes empty generated Rust module directories and updates parent module
--- references when child directories disappear.

local path = require("goggin-rs.infra.path")
local prune = require("goggin-rs.infra.prune")
local touch = require("goggin-rs.infra.touch")
local modules = require("goggin-rs.rust.modules")

local M = {}

--- Prunes empty Rust module directories and removes parent references.
---
---@param start_dir string Directory where pruning starts.
---@param root_dir string Boundary directory that is never deleted.
---@param tracker table|nil Touched-file tracker for deleted paths and updated parents.
---
function M.prune_empty_dirs(start_dir, root_dir, tracker)
    prune.empty_dirs(start_dir, root_dir, {
        marker_name = "mod.rs",
        tracker = tracker,
        on_pruned_parent = function(parent, module_name, active_tracker)
            local mod_path = path.join(parent, "mod.rs")
            if modules.remove_module_reference(mod_path, module_name) then
                touch.mark(active_tracker, mod_path)
            end
        end,
    })
end

return M
