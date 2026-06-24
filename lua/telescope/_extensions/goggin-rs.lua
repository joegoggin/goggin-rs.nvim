--- Telescope extension exports for goggin-rs.nvim workflows.
---
--- Exposes the plugin's user-facing picker and generator workflows through
--- `require("telescope").load_extension("goggin-rs")`.

local ok_telescope, telescope = pcall(require, "telescope")

if not ok_telescope or type(telescope.register_extension) ~= "function" then
    error("goggin-rs Telescope extension requires nvim-telescope/telescope.nvim.", 0)
end

--- Builds a lazy Telescope extension export for a workflow module action.
---
---@param module_name string Lua module name.
---@param action_name string Function name exported by the module.
---@return fun(...):any callback Lazy callback that forwards arguments to the workflow action.
---
local function workflow_export(module_name, action_name)
    return function(...)
        return require(module_name)[action_name](...)
    end
end

return telescope.register_extension({
    exports = {
        pick_component = workflow_export("goggin-rs.components", "pick"),
        generate_component = workflow_export("goggin-rs.components", "generate"),
        pick_page = workflow_export("goggin-rs.pages", "pick"),
        generate_page = workflow_export("goggin-rs.pages", "generate"),
        add_style = workflow_export("goggin-rs.styles", "pick"),
        delete_style = workflow_export("goggin-rs.styles", "pick_delete"),
        pick_colors = workflow_export("goggin-rs.scss", "pick_colors"),
    },
})
