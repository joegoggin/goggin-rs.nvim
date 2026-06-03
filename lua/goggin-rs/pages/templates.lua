--- Page naming and source templates.
---
--- Builds generated page component names, CSS class names, and Rust source
--- templates for page creation workflows.

local naming = require("goggin-rs.naming")

local M = {}

--- Builds the generated page component name.
---
---@param input_name string Raw page name input.
---@return string|nil component_name Component name with `Page` suffix.
---
function M.build_page_component_name(input_name)
    local base = naming.to_pascal_case(input_name)
    base = base:gsub("Page$", "")

    if base == "" then
        return nil
    end

    return base .. "Page"
end

--- Builds a page root CSS class from the page component name.
---
---@param component_name string Page component name.
---@return string|nil class_name Page class name.
---
function M.class_name_from_component(component_name)
    local base = component_name:gsub("Page$", "")
    local kebab = naming.to_kebab_case(base)

    if kebab == "" then
        return nil
    end

    return kebab .. "-page"
end

--- Builds the Rust source template for a generated page.
---
---@param component_name string PascalCase page component function name.
---@param class_name string kebab-case CSS class name.
---@return string[] lines Rust source lines.
---
function M.build_page_rust_template(component_name, class_name)
    local var_name = naming.to_snake_case(class_name)

    return {
        "use leptos::prelude::*;",
        "",
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        string.format("pub fn %s() -> impl IntoView {", component_name),
        "    // Classes",
        string.format('    let class_name = ClassNameUtil::new("%s", None);', class_name),
        string.format("    let %s = class_name.get_root_class();", var_name),
        "",
        "    view! {",
        string.format("        <div class=%s></div>", var_name),
        "    }",
        "}",
    }
end

return M
