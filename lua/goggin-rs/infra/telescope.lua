--- Optional Telescope dependency loader.
---
--- Loads the Telescope modules used by picker workflows and returns them in a
--- single table so callers can keep workflow-specific warning messages local.

local M = {}

--- Loads Telescope picker dependencies.
---
---@return table|nil telescope Loaded Telescope dependencies.
---
function M.load()
    local ok_actions, actions = pcall(require, "telescope.actions")
    local ok_action_state, action_state = pcall(require, "telescope.actions.state")
    local ok_finders, finders = pcall(require, "telescope.finders")
    local ok_pickers, pickers = pcall(require, "telescope.pickers")
    local ok_config, telescope_config = pcall(require, "telescope.config")

    if not (ok_actions and ok_action_state and ok_finders and ok_pickers and ok_config) then
        return nil
    end

    return {
        actions = actions,
        action_state = action_state,
        finders = finders,
        pickers = pickers,
        config = telescope_config,
    }
end

return M
