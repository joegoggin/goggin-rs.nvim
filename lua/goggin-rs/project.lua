local config = require("goggin-rs.config")
local fs = require("goggin-rs.fs")
local path = require("goggin-rs.path")

local M = {}

local PATH_LABELS = {
    components_dir = "src/components",
    styles_components_dir = "styles/components",
    pages_dir = "src/pages",
    page_styles_dir = "styles/pages",
    app_path = "src/app.rs",
}

local PATH_TYPES = {
    components_dir = "directory",
    styles_components_dir = "directory",
    pages_dir = "directory",
    page_styles_dir = "directory",
    app_path = "file",
}

local function append_ancestors(start_dir, roots, seen)
    local current = path.normalize_dir(start_dir)

    while current and not seen[current] do
        seen[current] = true
        table.insert(roots, current)

        local parent = path.normalize_dir(vim.fn.fnamemodify(current, ":h"))
        if not parent or parent == current then
            break
        end

        current = parent
    end
end

local function collect_search_roots()
    local roots = {}
    local seen = {}

    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file ~= "" then
        append_ancestors(vim.fn.fnamemodify(current_file, ":p:h"), roots, seen)
    end

    append_ancestors(vim.fn.getcwd(), roots, seen)

    local expanded = vim.fn.expand("%:p:h")
    if expanded ~= "" then
        append_ancestors(expanded, roots, seen)
    end

    return roots
end

local function resolve_configured_path(web_root, configured_path)
    if path.is_absolute(configured_path) then
        return configured_path:gsub("/+$", "")
    end

    return path.join(web_root, configured_path):gsub("/+$", "")
end

local function build_paths(web_root)
    local configured_paths = config.get().paths or {}

    return {
        web_root = web_root,
        components_dir = resolve_configured_path(web_root, configured_paths.components_dir),
        styles_components_dir = resolve_configured_path(web_root, configured_paths.styles_components_dir),
        pages_dir = resolve_configured_path(web_root, configured_paths.pages_dir),
        page_styles_dir = resolve_configured_path(web_root, configured_paths.page_styles_dir),
        app_path = resolve_configured_path(web_root, configured_paths.app_path),
    }
end

local function build_layouts(root)
    return {
        build_paths(path.join(root, "web")),
        build_paths(root),
    }
end

local function path_satisfies(paths, key)
    local value = paths[key]
    if not value then
        return false
    end

    if PATH_TYPES[key] == "file" then
        return fs.exists(value)
    end

    return fs.is_directory(value)
end

local function has_required_paths(paths, required)
    for _, key in ipairs(required) do
        if not path_satisfies(paths, key) then
            return false
        end
    end

    return true
end

local function describe_required(required)
    local labels = {}
    local seen = {}

    for _, key in ipairs(required) do
        local label = PATH_LABELS[key] or key
        if not seen[label] then
            seen[label] = true
            table.insert(labels, label)
        end
    end

    table.sort(labels)
    return table.concat(labels, ", ")
end

function M.resolve(required)
    local required_paths = required or {}

    for _, root in ipairs(collect_search_roots()) do
        for _, paths in ipairs(build_layouts(root)) do
            if has_required_paths(paths, required_paths) then
                return paths
            end
        end
    end

    local description = describe_required(required_paths)
    if description == "" then
        description = "required project paths"
    end

    return nil,
        "Could not locate web project paths for "
            .. description
            .. ". Expected either ./web/... from the repo root or ./... from the web root."
end

return M
