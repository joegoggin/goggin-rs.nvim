--- Empty SCSS directory pruning.
---
--- Removes empty generated SCSS directories and drops stale parent forwards
--- when style directories disappear.

local path = require("goggin-rs.infra.path")
local prune = require("goggin-rs.infra.prune")
local forwards = require("goggin-rs.scss.forwards")

local M = {}

--- Prunes empty SCSS directories and removes parent forwards.
---
---@param start_dir string Directory where pruning starts.
---@param root_dir string Boundary directory that is never deleted.
---@param tracker table|nil Touched-file tracker for deleted paths and updated parents.
---
function M.prune_empty_dirs(start_dir, root_dir, tracker)
    prune.empty_dirs(start_dir, root_dir, {
        marker_name = "index.scss",
        tracker = tracker,
        on_pruned_parent = function(parent, child_name, active_tracker)
            forwards.remove_forward(path.join(parent, "index.scss"), child_name, active_tracker)
        end,
    })
end

return M
