--- SCSS color file discovery, palette parsing, and value normalization.
---
--- Collects `_colors.scss` files from supported web roots and extracts color
--- variables with normalized preview values for later picker workflows.

local fs = require("goggin-rs.infra.fs")
local path = require("goggin-rs.infra.path")
local project = require("goggin-rs.project")

local M = {}

local COLOR_PATH_ATTEMPTS = {
    { "components_dir" },
    { "pages_dir" },
    { "styles_components_dir" },
    { "page_styles_dir" },
    { "app_path" },
}

--- Trims leading and trailing whitespace.
---
---@param value string String to trim.
---@return string trimmed Trimmed string.
---
local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Clamps a number between two bounds.
---
---@param value number Number to clamp.
---@param min number Minimum value.
---@param max number Maximum value.
---@return number clamped Clamped value.
---
local function clamp(value, min, max)
    if value < min then
        return min
    end

    if value > max then
        return max
    end

    return value
end

--- Converts RGB channel values to a lowercase hex color.
---
---@param r number Red channel.
---@param g number Green channel.
---@param b number Blue channel.
---@return string hex Lowercase `#rrggbb` color.
---
local function rgb_to_hex(r, g, b)
    return string.format(
        "#%02x%02x%02x",
        clamp(math.floor(r + 0.5), 0, 255),
        clamp(math.floor(g + 0.5), 0, 255),
        clamp(math.floor(b + 0.5), 0, 255)
    )
end

--- Collects numeric values from a string.
---
---@param value string String to scan.
---@param limit integer|nil Maximum count to collect.
---@return number[] numbers Collected numbers.
---
local function collect_numbers(value, limit)
    local numbers = {}

    for number in value:gmatch("[-+]?%d*%.?%d+") do
        table.insert(numbers, tonumber(number))

        if limit and #numbers >= limit then
            break
        end
    end

    return numbers
end

--- Formats RGB channels as a normalized CSS rgb() value.
---
---@param r number Red channel.
---@param g number Green channel.
---@param b number Blue channel.
---@return string value Normalized rgb() value.
---
local function format_rgb(r, g, b)
    return string.format(
        "rgb(%d, %d, %d)",
        clamp(math.floor(r + 0.5), 0, 255),
        clamp(math.floor(g + 0.5), 0, 255),
        clamp(math.floor(b + 0.5), 0, 255)
    )
end

--- Parses the first three numeric values from an RGB-like triplet.
---
---@param value string Value containing numeric channels.
---@return number|nil r Red channel.
---@return number|nil g Green channel.
---@return number|nil b Blue channel.
---
local function parse_rgb_triplet(value)
    local numbers = collect_numbers(value, 3)
    if #numbers < 3 then
        return nil, nil, nil
    end

    return numbers[1], numbers[2], numbers[3]
end

--- Parses a hex color value.
---
---@param value string SCSS value.
---@return string|nil hex Preview hex color.
---@return string|nil resolved Resolved display value.
---
local function parse_hex_color(value)
    local long, long_alpha = value:match("^%s*(#%x%x%x%x%x%x)(%x*)%s*$")
    if long and (long_alpha == "" or #long_alpha == 2) then
        return long:lower(), long:lower()
    end

    local r, g, b, short_alpha = value:match("^%s*#(%x)(%x)(%x)(%x*)%s*$")
    if r and g and b and (short_alpha == "" or #short_alpha == 1) then
        local hex = "#" .. r .. r .. g .. g .. b .. b
        return hex:lower(), hex:lower()
    end

    return nil, nil
end

--- Parses an rgb() or rgba() color value.
---
---@param value string SCSS value.
---@return string|nil hex Preview hex color.
---@return string|nil resolved Resolved display value.
---
local function parse_rgb_color(value)
    local inner = value:match("^%s*rgba?%s*%((.*)%)%s*$")
    if not inner or inner:match("var%s*%(") then
        return nil, nil
    end

    local r, g, b = parse_rgb_triplet(inner)
    if not r then
        return nil, nil
    end

    return rgb_to_hex(r, g, b), format_rgb(r, g, b)
end

--- Converts HSL channels to RGB channels.
---
---@param h number Hue in degrees.
---@param s number Saturation percentage.
---@param l number Lightness percentage.
---@return number r Red channel.
---@return number g Green channel.
---@return number b Blue channel.
---
local function hsl_to_rgb(h, s, l)
    h = (h % 360) / 360
    s = clamp(s / 100, 0, 1)
    l = clamp(l / 100, 0, 1)

    if s == 0 then
        local value = l * 255
        return value, value, value
    end

    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q

    local function hue_to_rgb(t)
        if t < 0 then
            t = t + 1
        end

        if t > 1 then
            t = t - 1
        end

        if t < 1 / 6 then
            return p + (q - p) * 6 * t
        end

        if t < 1 / 2 then
            return q
        end

        if t < 2 / 3 then
            return p + (q - p) * (2 / 3 - t) * 6
        end

        return p
    end

    return hue_to_rgb(h + 1 / 3) * 255, hue_to_rgb(h) * 255, hue_to_rgb(h - 1 / 3) * 255
end

--- Parses an hsl() or hsla() color value.
---
---@param value string SCSS value.
---@return string|nil hex Preview hex color.
---@return string|nil resolved Resolved display value.
---
local function parse_hsl_color(value)
    local inner = value:match("^%s*hsla?%s*%((.*)%)%s*$")
    if not inner then
        return nil, nil
    end

    local numbers = collect_numbers(inner, 3)
    if #numbers < 3 then
        return nil, nil
    end

    local r, g, b = hsl_to_rgb(numbers[1], numbers[2], numbers[3])
    return rgb_to_hex(r, g, b), format_rgb(r, g, b)
end

--- Removes SCSS variable suffix syntax not needed for color previews.
---
---@param value string SCSS value.
---@return string cleaned Cleaned SCSS value.
---
local function clean_scss_value(value)
    return trim(value:gsub("%s*!default%s*$", ""))
end

--- Parses the default palette selected in a `:root` block.
---
---@param lines string[] SCSS source lines.
---@return string|nil palette Default palette name.
---
function M.parse_default_palette(lines)
    local in_root = false

    for _, line in ipairs(lines) do
        if line:match("^%s*:root%s*{") then
            in_root = true
        end

        if in_root then
            local palette = line:match("@include%s+palette%-css%-variables%(%s*([%w_-]+)%s*%)")
            if palette then
                return palette
            end

            if line:match("^%s*}%s*$") then
                in_root = false
            end
        end
    end

    return nil
end

--- Parses `$palette-values` maps keyed by palette and token.
---
---@param lines string[] SCSS source lines.
---@return table<string, table<string, string>> palettes Palette token values.
---
function M.parse_palette_values(lines)
    local palettes = {}
    local in_palette_values = false
    local current_palette = nil

    for _, line in ipairs(lines) do
        if line:match("^%s*%$palette%-values%s*:") then
            in_palette_values = true
        end

        if in_palette_values then
            if current_palette then
                if line:match("^%s*%),?%s*$") then
                    current_palette = nil
                else
                    local token, triplet = line:match('^%s*([%w_-]+)%s*:%s*"([^"]+)"%s*,?%s*$')
                    if not token then
                        token, triplet = line:match("^%s*([%w_-]+)%s*:%s*([%d%s,%.]+)%s*,?%s*$")
                    end

                    if token and triplet then
                        palettes[current_palette][token] = triplet
                    end
                end
            else
                local palette = line:match("^%s*([%w_-]+)%s*:%s*%(%s*$")
                if palette then
                    current_palette = palette
                    palettes[current_palette] = palettes[current_palette] or {}
                elseif line:match("^%s*%);%s*$") then
                    in_palette_values = false
                end
            end
        end
    end

    return palettes
end

--- Resolves a `--color-*-rgb` CSS variable through the active palette map.
---
---@param value string SCSS value.
---@param palettes table<string, table<string, string>> Palette token values.
---@param default_palette string|nil Default palette name.
---@return string|nil hex Preview hex color.
---@return string|nil resolved Resolved display value.
---
local function resolve_css_color_var(value, palettes, default_palette)
    local token = value:match("var%(%s*%-%-color%-([%w%-]+)%-rgb%s*%)")
    if not token or not default_palette then
        return nil, nil
    end

    local palette = palettes[default_palette]
    if not palette then
        return nil, nil
    end

    local triplet = palette[token]
    if not triplet then
        return nil, nil
    end

    local r, g, b = parse_rgb_triplet(triplet)
    if not r then
        return nil, nil
    end

    return rgb_to_hex(r, g, b), format_rgb(r, g, b)
end

--- Builds a normalized color result.
---
---@param cleaned string Cleaned source value.
---@param hex string Preview hex color.
---@param resolved string Resolved display value.
---@return table color Normalized color result.
---
local function color_result(cleaned, hex, resolved)
    return {
        raw_value = cleaned,
        resolved_value = resolved,
        hex = hex,
    }
end

--- Normalizes a single SCSS color value.
---
---@param value string SCSS color value.
---@param opts table|nil Options with `palettes` and `default_palette`.
---@return table|nil color Normalized color, or nil when the value is not color-like.
---
function M.normalize_color_value(value, opts)
    local options = opts or {}
    local palettes = options.palettes or {}
    local default_palette = options.default_palette
    local cleaned = clean_scss_value(value or "")

    local hex, resolved = resolve_css_color_var(cleaned, palettes, default_palette)
    if hex then
        return color_result(cleaned, hex, resolved)
    end

    hex, resolved = parse_hex_color(cleaned)
    if hex then
        return color_result(cleaned, hex, resolved)
    end

    hex, resolved = parse_rgb_color(cleaned)
    if hex then
        return color_result(cleaned, hex, resolved)
    end

    hex, resolved = parse_hsl_color(cleaned)
    if hex then
        return color_result(cleaned, hex, resolved)
    end

    if cleaned:match("var%(%s*%-%-color%-") or cleaned:match("^%s*rgba?%s*%(") or cleaned:match("^%s*hsla?%s*%(") then
        return {
            raw_value = cleaned,
            resolved_value = nil,
            hex = nil,
        }
    end

    return nil
end

--- Source-compatible wrapper around `normalize_color_value`.
---
---@param value string SCSS color value.
---@param palettes table<string, table<string, string>>|nil Palette token values.
---@param default_palette string|nil Default palette name.
---@return table|nil color Normalized color, or nil when the value is not color-like.
---
function M.analyze_color_value(value, palettes, default_palette)
    return M.normalize_color_value(value, {
        palettes = palettes,
        default_palette = default_palette,
    })
end

--- Resolves project paths for color discovery.
---
---@return table|nil paths Resolved project paths.
---@return string|nil err Resolution error.
---
function M.resolve_color_paths()
    local last_error = nil

    for _, required in ipairs(COLOR_PATH_ATTEMPTS) do
        local paths, err = project.resolve(required)
        if paths then
            return paths, nil
        end

        last_error = err
    end

    return nil, last_error or "Could not locate web project paths."
end

--- Adds a unique value to a list.
---
---@param values string[] Value accumulator.
---@param seen table<string, boolean> Seen set.
---@param value string|nil Value to add.
---
local function add_unique(values, seen, value)
    if value and value ~= "" and not seen[value] then
        seen[value] = true
        table.insert(values, value)
    end
end

--- Returns the web root from a paths table or string input.
---
---@param source table|string Paths table or web root string.
---@return string|nil web_root Resolved web root.
---
local function get_web_root(source)
    if type(source) == "table" then
        return source.web_root
    end

    return source
end

--- Collects directories that may contain `_colors.scss` files.
---
---@param source table|string Paths table or web root string.
---@return string[] roots Search roots.
---
local function collect_color_roots(source)
    local web_root = get_web_root(source)
    local roots = {}
    local seen = {}

    if web_root and web_root ~= "" then
        add_unique(roots, seen, path.join(web_root, "styles"))
        add_unique(roots, seen, path.join(web_root, "assets", "css"))
        add_unique(roots, seen, path.join(web_root, "src"))
    end

    if type(source) == "table" then
        for _, key in ipairs({ "styles_components_dir", "page_styles_dir" }) do
            local style_dir = source[key]
            if style_dir and style_dir ~= "" then
                add_unique(roots, seen, style_dir)

                local style_root = vim.fn.fnamemodify(style_dir, ":h")
                if style_root ~= "." and style_root ~= style_dir then
                    add_unique(roots, seen, style_root)
                end
            end
        end
    end

    return roots
end

--- Adds a color file to a unique list when it exists.
---
---@param files string[] File accumulator.
---@param seen table<string, boolean> Seen set.
---@param file_path string File path to add.
---
local function add_color_file(files, seen, file_path)
    if fs.exists(file_path) and not seen[file_path] then
        seen[file_path] = true
        table.insert(files, file_path)
    end
end

--- Collects `_colors.scss` files from supported project locations.
---
---@param source table|string Paths table or web root string.
---@return string[] files Color file paths.
---
function M.collect_color_files(source)
    local files = {}
    local seen = {}
    local web_root = get_web_root(source)

    if web_root and web_root ~= "" then
        add_color_file(files, seen, path.join(web_root, "_colors.scss"))
    end

    for _, root in ipairs(collect_color_roots(source)) do
        if fs.is_directory(root) then
            for _, file_path in ipairs(vim.fn.glob(path.join(root, "**", "_colors.scss"), true, true)) do
                add_color_file(files, seen, file_path)
            end
        end
    end

    return files
end

--- Builds a source-relative path when a web root is available.
---
---@param web_root string|nil Web root.
---@param file_path string File path.
---@return string relative Source display path.
---
local function relative_source(web_root, file_path)
    if web_root and web_root ~= "" then
        return path.relative(web_root, file_path)
    end

    return file_path
end

--- Collects color variables from one `_colors.scss` file.
---
---@param web_root string|nil Web root for relative source paths.
---@param file_path string Color file path.
---@return table[] colors Color entries.
---
function M.collect_colors_from_file(web_root, file_path)
    local lines = fs.read_lines(file_path)
    local palettes = M.parse_palette_values(lines)
    local default_palette = M.parse_default_palette(lines)
    local colors = {}

    for line_number, line in ipairs(lines) do
        local name, value = line:match("^%s*(%$[%w_-]+)%s*:%s*(.-)%s*;")
        if name and not name:match("%-rgb$") then
            local color = M.normalize_color_value(value, {
                palettes = palettes,
                default_palette = default_palette,
            })

            if color then
                color.name = name
                color.source_path = file_path
                color.source_relative = relative_source(web_root, file_path)
                color.line_number = line_number
                color.display_value = color.resolved_value or color.raw_value

                table.insert(colors, color)
            end
        end
    end

    return colors
end

--- Collects and sorts color variables from all discovered color files.
---
---@param source table|string Paths table or web root string.
---@return table[] colors Sorted color entries.
---@return string[] color_files Discovered color files.
---
function M.collect_colors(source)
    local colors = {}
    local color_files = M.collect_color_files(source)
    local web_root = get_web_root(source)

    for _, file_path in ipairs(color_files) do
        for _, color in ipairs(M.collect_colors_from_file(web_root, file_path)) do
            table.insert(colors, color)
        end
    end

    table.sort(colors, function(a, b)
        if a.name == b.name then
            return a.source_relative < b.source_relative
        end

        return a.name < b.name
    end)

    return colors, color_files
end

return M
