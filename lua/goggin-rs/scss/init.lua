--- SCSS mutation helpers.
---
--- Re-exports SCSS partial templates, partial lookup, forward mutation, and
--- empty-directory pruning through the SCSS package module.

local forwards = require("goggin-rs.scss.forwards")
local partials = require("goggin-rs.scss.partials")
local prune = require("goggin-rs.scss.prune")

return {
    build_class_template = partials.build_class_template,
    resolve_partial_style = partials.resolve_partial_style,
    ensure_forward = forwards.ensure_forward,
    replace_forward = forwards.replace_forward,
    remove_forward = forwards.remove_forward,
    ensure_forward_chain = forwards.ensure_forward_chain,
    prune_empty_dirs = prune.prune_empty_dirs,
}
