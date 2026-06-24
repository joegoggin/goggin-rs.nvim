--- Rust source templates for generated components.
---
--- Builds Rust source line arrays for generated component files using the
--- configured component naming inputs.

local M = {}

--- Builds the Rust source template for a generated optional-class component.
---
---@param component_name string PascalCase component function name.
---@param class_name string kebab-case CSS class name.
---@param var_name string snake_case local class variable name.
---@return string[] lines Rust source lines.
---
function M.build_component_template(component_name, class_name, var_name)
    return {
        "use leptos::prelude::*;",
        "",
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        string.format("pub fn %s(#[prop(optional, into)] class: Option<String>) -> impl IntoView {", component_name),
        "    // Classes",
        string.format('    let class_name = ClassNameUtil::new("%s", class);', class_name),
        string.format("    let %s = class_name.get_root_class();", var_name),
        "",
        "    view! {",
        string.format("        <div class=%s></div>", var_name),
        "    }",
        "}",
    }
end

return M
