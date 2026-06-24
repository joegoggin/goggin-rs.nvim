--- SCSS mutation helpers.
---
--- Re-exports SCSS partial templates, partial lookup, color discovery, forward
--- mutation, and empty-directory pruning through the SCSS package module.

local forwards = require("goggin-rs.scss.forwards")
local colors = require("goggin-rs.scss.colors")
local partials = require("goggin-rs.scss.partials")
local prune = require("goggin-rs.scss.prune")

return {
    analyze_color_value = colors.analyze_color_value,
    build_class_template = partials.build_class_template,
    collect_color_files = colors.collect_color_files,
    collect_colors = colors.collect_colors,
    collect_colors_from_file = colors.collect_colors_from_file,
    resolve_partial_style = partials.resolve_partial_style,
    ensure_forward = forwards.ensure_forward,
    normalize_color_value = colors.normalize_color_value,
    parse_default_palette = colors.parse_default_palette,
    parse_palette_values = colors.parse_palette_values,
    replace_forward = forwards.replace_forward,
    remove_forward = forwards.remove_forward,
    resolve_color_paths = colors.resolve_color_paths,
    ensure_forward_chain = forwards.ensure_forward_chain,
    prune_empty_dirs = prune.prune_empty_dirs,
}
