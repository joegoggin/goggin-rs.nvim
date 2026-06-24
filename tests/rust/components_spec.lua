--- Rust component helper tests.
---
--- Verifies Rust component-name parsing and generated component template
--- output used by component creation workflows.

local h = require("tests.helpers")

local path = h.path
local rust = h.rust

local temp_root = h.temp_root
local write_file = h.write_file
local assert_equals = h.assert_equals
local assert_list_equals = h.assert_list_equals
local test = h.test

--- Verifies Rust component parsing and generated component templates.
---
--- # Example Under Test
---
--- A Rust component fixture contains `#[component]`, an additional attribute,
--- and a public component function.
---
--- # Assertions
---
--- - Component parsing skips attributes and returns the component function name.
--- - The generated Rust component template matches the expected source lines.
---
test("rust component helpers parse components and build templates", function()
    local root = path.join(temp_root, "rust-component")
    local rust_path = path.join(root, "src", "components", "account_card.rs")
    write_file(rust_path, {
        "#[component]",
        "#[allow(clippy::needless_pass_by_value)]",
        "pub fn AccountCard() -> impl IntoView {",
        "    view! { <div /> }",
        "}",
    })

    assert_equals(rust.component_name_from_file(rust_path), "AccountCard", "component parser should skip attributes")
    assert_list_equals(rust.build_component_template("AccountCard", "account-card", "account_card"), {
        "use leptos::prelude::*;",
        "",
        "use crate::utils::class_name::ClassNameUtil;",
        "",
        "#[component]",
        "pub fn AccountCard(#[prop(optional, into)] class: Option<String>) -> impl IntoView {",
        "    // Classes",
        '    let class_name = ClassNameUtil::new("account-card", class);',
        "    let account_card = class_name.get_root_class();",
        "",
        "    view! {",
        "        <div class=account_card></div>",
        "    }",
        "}",
    }, "component template should preserve generated Rust source")
end)
