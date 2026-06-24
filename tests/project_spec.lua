--- Project discovery tests.
---
--- Verifies supported Rust/Leptos project layouts, configured path overrides,
--- discovery precedence, and user-facing missing-path diagnostics.

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

--- Verifies project resolution for a repo-root web layout.
---
--- # Example Under Test
---
--- A temporary directory contains the default source, style, page, and app
--- paths directly at the root.
---
--- # Assertions
---
--- - Resolution returns no error.
--- - The resolved web root is the temporary root.
--- - Component and app paths point to the expected locations.
---
test("resolves repo-root layout", function()
    local root = path.join(temp_root, "repo-root")
    create_default_layout(root)
    reset(root)

    local paths, err = project.resolve({
        "components_dir",
        "styles_components_dir",
        "pages_dir",
        "page_styles_dir",
        "app_path",
    })

    assert_equals(err, nil, "repo-root layout should not return an error")
    local resolved_paths = assert(paths)
    assert_equals(resolved_paths.web_root, root, "repo-root web root should be the current root")
    assert_equals(resolved_paths.components_dir, path.join(root, "src", "components"), "components path should resolve")
    assert_equals(resolved_paths.app_path, path.join(root, "src", "app.rs"), "app path should resolve")
end)

--- Verifies project resolution for a nested `web` layout.
---
--- # Example Under Test
---
--- A temporary repository contains the default web layout inside a `web`
--- directory.
---
--- # Assertions
---
--- - Resolution returns no error.
--- - The resolved web root is the nested `web` directory.
--- - Required component paths resolve under the nested web root.
---
test("resolves nested web layout", function()
    local root = path.join(temp_root, "nested-web")
    local web_root = path.join(root, "web")
    create_default_layout(web_root)
    reset(root)

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(err, nil, "nested web layout should not return an error")
    local resolved_paths = assert(paths)
    assert_equals(resolved_paths.web_root, web_root, "nested web root should resolve")
    assert_equals(
        resolved_paths.components_dir,
        path.join(web_root, "src", "components"),
        "nested components path should resolve"
    )
end)

--- Verifies nested web layout precedence.
---
--- # Example Under Test
---
--- A temporary repository contains both root-level and nested `web` layouts.
---
--- # Assertions
---
--- - The nested `web` layout is selected before the repo-root layout.
---
--- # Why
---
--- Repositories may contain support files at the root while the application
--- lives in `web`.
---
test("prefers nested web layout over repo-root layout", function()
    local root = path.join(temp_root, "layout-precedence")
    local web_root = path.join(root, "web")
    create_default_layout(root)
    create_default_layout(web_root)
    reset(root)

    local paths = assert(project.resolve({ "components_dir", "app_path" }))

    assert_equals(paths.web_root, web_root, "nested web layout should be checked first")
end)

--- Verifies configured path overrides are merged with defaults.
---
--- # Example Under Test
---
--- Plugin setup overrides the component and app paths while leaving other
--- paths unspecified.
---
--- # Assertions
---
--- - Resolution returns no error.
--- - Overridden paths resolve to configured locations.
--- - Unspecified paths still use default values.
---
test("merges configured path overrides", function()
    local root = path.join(temp_root, "overrides")
    reset(root)

    mkdir(path.join(root, "ui", "components"))
    write_file(path.join(root, "app", "main.rs"), { "fn main() {}" })

    plugin.setup({
        paths = {
            components_dir = "ui/components",
            app_path = "app/main.rs",
        },
    })

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(err, nil, "configured layout should not return an error")
    local resolved_paths = assert(paths)
    assert_equals(
        resolved_paths.components_dir,
        path.join(root, "ui", "components"),
        "components override should resolve"
    )
    assert_equals(resolved_paths.app_path, path.join(root, "app", "main.rs"), "app override should resolve")
    assert_equals(resolved_paths.pages_dir, path.join(root, "src", "pages"), "defaults should remain merged")
end)

--- Verifies project resolution diagnostics for missing required paths.
---
--- # Example Under Test
---
--- A temporary root has no required component or app paths.
---
--- # Assertions
---
--- - Resolution returns nil paths.
--- - The warning names the missing required labels.
--- - The warning describes both supported layout shapes.
---
--- # Why
---
--- User-facing project discovery warnings should point at actionable missing
--- paths.
---
test("returns clear warning for missing required paths", function()
    local root = path.join(temp_root, "missing-required")
    mkdir(root)
    reset(root)

    local paths, err = project.resolve({ "components_dir", "app_path" })

    assert_equals(paths, nil, "missing required paths should not resolve")
    assert_match(
        err,
        "Could not locate web project paths for src/app.rs, src/components.",
        "warning should name missing labels"
    )
    assert_match(
        err,
        "Expected either ./web/... from the repo root or ./... from the web root.",
        "warning should describe supported layouts"
    )
end)
