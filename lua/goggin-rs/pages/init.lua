--- Page picker and generator workflows.
---
--- Re-exports page collection, creation, conversion, component generation,
--- opening, route parsing, style pairing, and UI entrypoints.

local collect = require("goggin-rs.pages.collect")
local components = require("goggin-rs.pages.components")
local convert = require("goggin-rs.pages.convert")
local create = require("goggin-rs.pages.create")
local entries = require("goggin-rs.pages.entries")
local open = require("goggin-rs.pages.open")
local routes = require("goggin-rs.pages.routes")
local styles = require("goggin-rs.pages.styles")
local ui = require("goggin-rs.pages.ui")

return {
    resolve_scss_path = styles.resolve_scss_path,
    collect = collect.collect,
    collect_entries = entries.collect_entries,
    open_pair = open.open_pair,
    parse_route_segments = routes.parse_route_segments,
    convert_to_module_layout = convert.convert_to_module_layout,
    create_component = components.create_component,
    create = create.create,
    pick = ui.pick,
    generate = ui.generate,
}
