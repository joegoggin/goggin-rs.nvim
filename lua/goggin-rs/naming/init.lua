--- Naming helpers for generated Rust, SCSS, and route artifacts.
---
--- Re-exports case conversion and route segment helpers through the naming
--- package module.

local case = require("goggin-rs.naming.case")
local route = require("goggin-rs.naming.route")

return {
    trim = case.trim,
    split_words = case.split_words,
    to_pascal_case = case.to_pascal_case,
    to_snake_case = case.to_snake_case,
    to_kebab_case = case.to_kebab_case,
    split_path_segments = route.split_path_segments,
    normalize_relative_dir = route.normalize_relative_dir,
    route_segment_to_fs = route.route_segment_to_fs,
    route_segment_to_path = route.route_segment_to_path,
}
