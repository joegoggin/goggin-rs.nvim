--- SCSS color discovery and normalization tests.
---
--- Verifies `_colors.scss` lookup, palette map parsing, default palette
--- resolution, CSS color variable resolution, and supported color syntaxes.

local h = require("tests.helpers")

local path = h.path
local scss = h.scss

local temp_root = h.temp_root
local create_default_layout = h.create_default_layout
local reset = h.reset
local write_file = h.write_file
local assert_equals = h.assert_equals
local assert_list_equals = h.assert_list_equals
local test = h.test

--- Finds a color entry by variable name.
---
---@param colors table[] Color entries.
---@param name string SCSS variable name.
---@return table|nil color Matching color entry.
---
local function find_color(colors, name)
    for _, color in ipairs(colors) do
        if color.name == name then
            return color
        end
    end

    return nil
end

--- Verifies path resolution for direct and nested web-root layouts.
---
--- # Assertions
---
--- - Direct web roots resolve to the current project root.
--- - Nested repository roots resolve to the `web` child.
---
test("scss color path resolution supports direct and nested web roots", function()
    local direct_root = path.join(temp_root, "colors-direct")
    create_default_layout(direct_root)
    reset(direct_root)

    local direct_paths = assert(scss.resolve_color_paths())
    assert_equals(direct_paths.web_root, direct_root, "direct layout should resolve the current root")

    local nested_root = path.join(temp_root, "colors-nested")
    local nested_web_root = path.join(nested_root, "web")
    create_default_layout(nested_web_root)
    reset(nested_root)

    local nested_paths = assert(scss.resolve_color_paths())
    assert_equals(nested_paths.web_root, nested_web_root, "nested layout should resolve the web root")
end)

--- Verifies `_colors.scss` discovery and CSS variable resolution.
---
--- # Assertions
---
--- - Color files are collected from the web root, styles, assets/css, and src.
--- - Palette CSS variables resolve through the palette selected in `:root`.
--- - `$*-rgb` helper variables are excluded from picker entries.
---
test("scss color collection resolves palette CSS variables with the default palette", function()
    local root = path.join(temp_root, "colors-collect")
    create_default_layout(root)

    local paths = {
        web_root = root,
        styles_components_dir = path.join(root, "styles", "components"),
        page_styles_dir = path.join(root, "styles", "pages"),
    }

    local root_colors = path.join(root, "_colors.scss")
    local style_colors = path.join(root, "styles", "theme", "_colors.scss")
    local asset_colors = path.join(root, "assets", "css", "_colors.scss")
    local source_colors = path.join(root, "src", "ui", "_colors.scss")

    write_file(root_colors, {
        "$root-color: #010203;",
    })
    write_file(style_colors, {
        "$palette-values: (",
        "    light: (",
        '        primary: "12, 34, 56",',
        "        accent: 7, 8, 9,",
        "    ),",
        "    dark: (",
        '        primary: "200, 201, 202",',
        "    ),",
        ");",
        "",
        ":root {",
        "    @include palette-css-variables(light);",
        "}",
        "",
        "$palette-primary: var(--color-primary-rgb);",
        "$palette-accent: rgba(var(--color-accent-rgb), 0.5);",
        "$palette-rgb: 12, 34, 56;",
    })
    write_file(asset_colors, {
        "$asset-color: rgb(4, 5, 6);",
    })
    write_file(source_colors, {
        "$source-color: hsl(240, 100%, 50%);",
    })

    local color_files = scss.collect_color_files(paths)
    assert_list_equals(color_files, {
        root_colors,
        style_colors,
        asset_colors,
        source_colors,
    }, "color files should be discovered from every supported root")

    local colors, collected_files = scss.collect_colors(paths)
    assert_list_equals(collected_files, color_files, "collect_colors should return discovered files")
    assert_equals(#colors, 5, "rgb helper variables should not produce color entries")

    local palette_primary = assert(find_color(colors, "$palette-primary"))
    assert_equals(palette_primary.hex, "#0c2238", "default palette should resolve primary hex")
    assert_equals(palette_primary.resolved_value, "rgb(12, 34, 56)", "default palette should resolve primary rgb")
    assert_equals(palette_primary.display_value, "rgb(12, 34, 56)", "display value should prefer resolved rgb")
    assert_equals(
        palette_primary.source_relative,
        "styles/theme/_colors.scss",
        "source path should be relative to the web root"
    )

    local palette_accent = assert(find_color(colors, "$palette-accent"))
    assert_equals(palette_accent.hex, "#070809", "css vars inside rgba should resolve through the palette")
    assert_equals(palette_accent.resolved_value, "rgb(7, 8, 9)", "css vars inside rgba should normalize to rgb")

    assert_equals(colors[1].name, "$asset-color", "colors should sort by variable name")
    assert_equals(colors[#colors].name, "$source-color", "colors should include src color files")
end)

--- Verifies supported color syntax normalization.
---
--- # Assertions
---
--- - Hex, rgb, rgba, hsl, and hsla values produce preview hex values.
--- - Unresolved color-like values are preserved for UI display.
--- - Non-color values are ignored.
---
test("scss color normalization supports hex rgb rgba hsl and hsla values", function()
    local cases = {
        { value = "#ABC !default", hex = "#aabbcc", resolved = "#aabbcc", raw = "#ABC" },
        { value = "#11223344", hex = "#112233", resolved = "#112233" },
        { value = "rgb(10, 20, 30)", hex = "#0a141e", resolved = "rgb(10, 20, 30)" },
        { value = "rgba(10, 20, 30, 0.4)", hex = "#0a141e", resolved = "rgb(10, 20, 30)" },
        { value = "hsl(0, 100%, 50%)", hex = "#ff0000", resolved = "rgb(255, 0, 0)" },
        { value = "hsla(120, 100%, 25%, 0.75)", hex = "#008000", resolved = "rgb(0, 128, 0)" },
    }

    for _, case in ipairs(cases) do
        local color = assert(scss.normalize_color_value(case.value))
        assert_equals(color.hex, case.hex, case.value .. " should normalize to expected hex")
        assert_equals(color.resolved_value, case.resolved, case.value .. " should normalize to expected display value")

        if case.raw then
            assert_equals(color.raw_value, case.raw, case.value .. " should preserve cleaned raw value")
        end
    end

    local unresolved = assert(scss.normalize_color_value("rgba(var(--color-missing-rgb), 0.5)"))
    assert_equals(unresolved.raw_value, "rgba(var(--color-missing-rgb), 0.5)", "unresolved raw value should remain")
    assert_equals(unresolved.hex, nil, "unresolved css variables should not invent a preview hex")
    assert_equals(unresolved.resolved_value, nil, "unresolved css variables should not invent a display value")

    assert_equals(scss.normalize_color_value("#12345"), nil, "invalid 5-digit hex values should be ignored")
    assert_equals(scss.normalize_color_value("#1234567"), nil, "invalid 7-digit hex values should be ignored")
    assert_equals(scss.normalize_color_value("1rem"), nil, "non-color values should be ignored")
end)
