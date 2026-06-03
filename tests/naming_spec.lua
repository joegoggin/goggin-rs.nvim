--- Naming helper tests.
---
--- Verifies user-input normalization for generated Rust names, style names,
--- relative directories, and route path segments.

local h = require("tests.helpers")

local component = h.component
local page = h.page
local plugin = h.plugin
local fs = h.fs
local naming = h.naming
local path = h.path
local project = h.project
local rust = h.rust
local scss = h.scss
local touch = h.touch

local temp_root = h.temp_root
local mkdir = h.mkdir
local write_file = h.write_file
local create_default_layout = h.create_default_layout
local reset = h.reset
local assert_equals = h.assert_equals
local assert_match = h.assert_match
local assert_list_equals = h.assert_list_equals
local test = h.test
local with_stubbed_format = h.with_stubbed_format

--- Verifies general naming conversions.
---
--- # Example Under Test
---
--- Mixed acronym, PascalCase, snake_case, kebab-case, spaced, blank, and
--- relative directory inputs are normalized.
---
--- # Assertions
---
--- - Outer whitespace is trimmed.
--- - Mixed input splits into lowercase words.
--- - Pascal, snake, and kebab conversions match expected casing.
--- - Path splitting ignores empty and dot segments.
--- - Relative directory normalization snake-cases each segment.
---
test("naming helpers convert words and relative paths", function()
    assert_equals(naming.trim("  Account Settings  "), "Account Settings", "trim should remove outer whitespace")
    assert_list_equals(
        naming.split_words("HTTPServer_page-name"),
        { "http", "server", "page", "name" },
        "split_words should normalize representative input"
    )
    assert_equals(
        naming.to_pascal_case("account-settings page"),
        "AccountSettingsPage",
        "pascal case should convert spaced kebab input"
    )
    assert_equals(
        naming.to_snake_case("AccountSettingsPage"),
        "account_settings_page",
        "snake case should split pascal input"
    )
    assert_equals(
        naming.to_kebab_case("account_settings Page"),
        "account-settings-page",
        "kebab case should convert mixed input"
    )
    assert_equals(naming.to_pascal_case("   "), "", "blank pascal input should be empty")
    assert_list_equals(
        naming.split_path_segments("/admin/./User Settings//"),
        { "admin", "User Settings" },
        "path segments should ignore empty and dot segments"
    )
    assert_equals(
        naming.normalize_relative_dir("/Admin Tools/./UserSettings//"),
        "admin_tools/user_settings",
        "relative directory normalization should snake-case segments"
    )
end)

--- Verifies route segment normalization.
---
--- # Example Under Test
---
--- Static, dynamic, wildcard, and blank route segments are converted for file
--- paths and URL paths.
---
--- # Assertions
---
--- - Static route segments use snake_case for files and kebab-case for URLs.
--- - Dynamic route markers are stripped for files and preserved for URLs.
--- - Wildcards become `all` for file paths.
--- - Blank file segments fall back to `index`.
---
test("naming helpers preserve route-safe segment behavior", function()
    assert_equals(
        naming.route_segment_to_fs("BlogPost"),
        "blog_post",
        "route fs segment should snake-case static names"
    )
    assert_equals(naming.route_segment_to_fs(":postId"), "post_id", "route fs segment should strip dynamic marker")
    assert_equals(naming.route_segment_to_fs("*"), "all", "route fs segment should convert wildcard")
    assert_equals(naming.route_segment_to_fs("   "), "index", "empty route fs segment should fall back to index")
    assert_equals(
        naming.route_segment_to_path("BlogPost"),
        "blog-post",
        "route path segment should kebab-case static names"
    )
    assert_equals(
        naming.route_segment_to_path(":postId"),
        ":postId",
        "route path segment should preserve dynamic marker"
    )
end)
