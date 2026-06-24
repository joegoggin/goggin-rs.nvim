--- Component picker and generator workflows.
---
--- Re-exports component collection, creation, opening, style pairing, and UI
--- entrypoints through the component package module.

local collect = require("goggin-rs.components.collect")
local create = require("goggin-rs.components.create")
local open = require("goggin-rs.components.open")
local styles = require("goggin-rs.components.styles")
local ui = require("goggin-rs.components.ui")

return {
    resolve_scss_path = styles.resolve_scss_path,
    collect = collect.collect,
    open_pair = open.open_pair,
    create = create.create,
    pick = ui.pick,
    generate = ui.generate,
}
