--- Missing-style add and delete workflows.
---
--- Re-exports style item collection, mutation, and Telescope picker entrypoints.

local collect = require("goggin-rs.styles.collect")
local create = require("goggin-rs.styles.create")
local ui = require("goggin-rs.styles.ui")

return {
    collect = collect.collect,
    create_missing_style = create.create_missing_style,
    delete_style = create.delete_style,
    pick = ui.pick,
    pick_delete = ui.pick_delete,
}
