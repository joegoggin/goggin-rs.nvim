--- User command registration for goggin-rs.nvim workflows.
---
--- Creates stable `:GogginRs*` wrappers around the extracted picker and
--- generator entrypoints while keeping callbacks lazy so tests and users can
--- replace modules before commands are invoked.

local workflows = require("goggin-rs.workflows")

local M = {}

---@type table<string, boolean>
local registered = {}

--- Builds a lazy command callback for a workflow module action.
---
---@param module_name string Lua module name.
---@param action_name string Function name exported by the module.
---@return fun() callback Command callback that dispatches to the workflow action.
---
local function command_callback(module_name, action_name)
    return function()
        require(module_name)[action_name]()
    end
end

--- Registers all public plugin workflow commands.
function M.register()
    for _, workflow in ipairs(workflows.all()) do
        vim.api.nvim_create_user_command(workflow.command_name, command_callback(workflow.module, workflow.action), {
            desc = workflow.desc,
            force = true,
        })

        registered[workflow.command_name] = true
    end
end

--- Removes plugin commands registered by this module.
function M.unregister()
    for _, workflow in ipairs(workflows.all()) do
        if registered[workflow.command_name] then
            pcall(vim.api.nvim_del_user_command, workflow.command_name)
            registered[workflow.command_name] = nil
        end
    end
end

--- Returns the public command names managed by this module.
---
---@return string[] names Command names.
---
function M.names()
    local names = {}

    for _, workflow in ipairs(workflows.all()) do
        table.insert(names, workflow.command_name)
    end

    return names
end

return M
