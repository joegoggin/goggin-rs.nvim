--- Rust source mutation helpers.
---
--- Re-exports Rust component parsing, module mutation, route mutation, pruning,
--- templates, and public-use helpers through the Rust package module.

local components = require("goggin-rs.rust.components")
local modules = require("goggin-rs.rust.modules")
local prune = require("goggin-rs.rust.prune")
local routes = require("goggin-rs.rust.routes")
local templates = require("goggin-rs.rust.templates")
local uses = require("goggin-rs.rust.uses")

return {
    component_name_from_file = components.component_name_from_file,
    build_component_template = templates.build_component_template,
    normalize_mod_layout = modules.normalize_mod_layout,
    ensure_mod_declaration = modules.ensure_mod_declaration,
    remove_module_reference = modules.remove_module_reference,
    ensure_use_declaration = uses.ensure_use_declaration,
    remove_use_symbol = uses.remove_use_symbol,
    remove_use_symbol_tree = uses.remove_use_symbol_tree,
    insert_route = routes.insert_route,
    remove_route_view = routes.remove_route_view,
    prune_empty_dirs = prune.prune_empty_dirs,
}
