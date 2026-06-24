--- Public workflow metadata shared by commands and Telescope exports.

local M = {}

---@type table[]
local WORKFLOWS = {
    {
        command_name = "GogginRsPickComponent",
        telescope_name = "pick_component",
        desc = "Pick and open a Rust component",
        module = "goggin-rs.components",
        action = "pick",
    },
    {
        command_name = "GogginRsGenerateComponent",
        telescope_name = "generate_component",
        desc = "Generate a Rust component and paired style",
        module = "goggin-rs.components",
        action = "generate",
    },
    {
        command_name = "GogginRsPickPage",
        telescope_name = "pick_page",
        desc = "Pick and open a Rust page",
        module = "goggin-rs.pages",
        action = "pick",
    },
    {
        command_name = "GogginRsGeneratePage",
        telescope_name = "generate_page",
        desc = "Generate a Rust page or page-local component",
        module = "goggin-rs.pages",
        action = "generate",
    },
    {
        command_name = "GogginRsAddStyle",
        telescope_name = "add_style",
        desc = "Add a missing component or page style",
        module = "goggin-rs.styles",
        action = "pick",
    },
    {
        command_name = "GogginRsDeleteStyle",
        telescope_name = "delete_style",
        desc = "Delete an existing component or page style",
        module = "goggin-rs.styles",
        action = "pick_delete",
    },
    {
        command_name = "GogginRsPickColors",
        telescope_name = "pick_colors",
        desc = "Pick and copy an SCSS color variable",
        module = "goggin-rs.scss",
        action = "pick_colors",
    },
}

--- Returns the public workflows in display and registration order.
---
---@return table[] workflows Workflow metadata entries.
---
function M.all()
    return WORKFLOWS
end

return M
