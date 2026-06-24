--- User command registration for goggin-rs.nvim workflows.
---
--- Creates stable `:GogginRs*` wrappers around the extracted picker and
--- generator entrypoints while keeping callbacks lazy so tests and users can
--- replace modules before commands are invoked.

local M = {}

---@type table[]
local COMMANDS = {
    {
        name = "GogginRsPickComponent",
        desc = "Pick and open a Rust component",
        module = "goggin-rs.components",
        action = "pick",
    },
    {
        name = "GogginRsGenerateComponent",
        desc = "Generate a Rust component and paired style",
        module = "goggin-rs.components",
        action = "generate",
    },
    {
        name = "GogginRsPickPage",
        desc = "Pick and open a Rust page",
        module = "goggin-rs.pages",
        action = "pick",
    },
    {
        name = "GogginRsGeneratePage",
        desc = "Generate a Rust page or page-local component",
        module = "goggin-rs.pages",
        action = "generate",
    },
    {
        name = "GogginRsAddStyle",
        desc = "Add a missing component or page style",
        module = "goggin-rs.styles",
        action = "pick",
    },
    {
        name = "GogginRsDeleteStyle",
        desc = "Delete an existing component or page style",
        module = "goggin-rs.styles",
        action = "pick_delete",
    },
    {
        name = "GogginRsPickColors",
        desc = "Pick and copy an SCSS color variable",
        module = "goggin-rs.scss",
        action = "pick_colors",
    },
}

---@type table<string, boolean>
local registered = {}

--- Builds a lazy command callback for a workflow module action.
---
---@param module_name string Lua module name.
---@param action_name string Function name exported by the module.
---@return fun()
---
local function command_callback(module_name, action_name)
    return function()
        require(module_name)[action_name]()
    end
end

--- Registers all public plugin workflow commands.
function M.register()
    for _, command in ipairs(COMMANDS) do
        vim.api.nvim_create_user_command(command.name, command_callback(command.module, command.action), {
            desc = command.desc,
            force = true,
        })

        registered[command.name] = true
    end
end

--- Removes plugin commands registered by this module.
function M.unregister()
    for _, command in ipairs(COMMANDS) do
        if registered[command.name] then
            pcall(vim.api.nvim_del_user_command, command.name)
            registered[command.name] = nil
        end
    end
end

--- Returns the public command names managed by this module.
---
---@return string[] names Command names.
---
function M.names()
    local names = {}

    for _, command in ipairs(COMMANDS) do
        table.insert(names, command.name)
    end

    return names
end

return M
