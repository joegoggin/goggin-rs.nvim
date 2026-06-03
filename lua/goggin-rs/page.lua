--- Page picker and generator workflows.
---
--- Collects Leptos page components, resolves paired SCSS partials, and creates
--- new page Rust/SCSS files while maintaining page modules, style indexes, and
--- app routes.

local fs = require("goggin-rs.fs")
local line_utils = require("goggin-rs.lines")
local naming = require("goggin-rs.naming")
local path = require("goggin-rs.path")
local project = require("goggin-rs.project")
local rust = require("goggin-rs.rust")
local scss = require("goggin-rs.scss")
local touch = require("goggin-rs.touch")

local M = {}

--- Shows a warning notification.
---
---@param message string Message to display.
---
local function notify_warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

--- Resolves project paths and warns when required paths are unavailable.
---
---@param required string[] Required project path keys.
---@return table|nil paths Resolved project paths.
---
local function resolve_paths(required)
    local paths, err = project.resolve(required)
    if not paths then
        notify_warn(err)
        return nil
    end

    return paths
end

--- Returns the basename for a filesystem path.
---
---@param file_path string Path to inspect.
---@return string basename Final path component.
---
local function basename(file_path)
    return vim.fn.fnamemodify(file_path, ":t")
end

--- Parses the first Leptos component function name from a Rust file.
---
---@param file_path string Rust file path.
---@return string|nil component_name Parsed component function name.
---
local function component_name_from_file(file_path)
    local awaiting_component_fn = false

    for _, line in ipairs(fs.read_lines(file_path)) do
        if line:match("^%s*#%s*%[%s*component%s*%]") then
            awaiting_component_fn = true
        elseif awaiting_component_fn then
            local component_name = line:match("^%s*pub%s+fn%s+([%w_]+)")
            if component_name then
                return component_name
            end

            local is_attribute = line:match("^%s*#") ~= nil
            local is_blank = line:match("^%s*$") ~= nil
            if not is_attribute and not is_blank then
                awaiting_component_fn = false
            end
        end
    end

    return nil
end

--- Resolves a direct or parent-prefixed partial under a style directory.
---
---@param base_dir string Style directory to inspect.
---@param stem string Rust module stem.
---@return string|nil scss_path Matching SCSS partial path.
---
local function resolve_partial_style(base_dir, stem)
    local kebab_stem = stem:gsub("_", "-")
    local direct_match = path.join(base_dir, "_" .. kebab_stem .. ".scss")
    if fs.exists(direct_match) then
        return direct_match
    end

    local parent = basename(base_dir):gsub("_", "-")
    local prefixed_match = path.join(base_dir, "_" .. parent .. "-" .. kebab_stem .. ".scss")
    if fs.exists(prefixed_match) then
        return prefixed_match
    end

    return nil
end

--- Resolves the paired SCSS partial for a page entry.
---
---@param page table Page entry from `collect`.
---@param paths table Resolved project paths.
---@return string|nil scss_path Matching SCSS path when one exists.
---
function M.resolve_scss_path(page, paths)
    if not page or not paths or not paths.page_styles_dir then
        return nil
    end

    if page.is_module_layout then
        local module_style_dir = path.join(paths.page_styles_dir, page.module_relative_dir)
        local module_style = path.join(module_style_dir, "_page.scss")

        if fs.exists(module_style) then
            return module_style
        end

        return nil
    end

    local style_parent_dir = path.join(paths.page_styles_dir, page.rust_parent_relative)
    local by_stem = resolve_partial_style(style_parent_dir, page.module_name)
    if by_stem then
        return by_stem
    end

    local component_kebab = naming.to_kebab_case(page.page_component_name)
    if component_kebab ~= "" then
        local by_component = path.join(style_parent_dir, "_" .. component_kebab .. ".scss")
        if fs.exists(by_component) then
            return by_component
        end

        local without_page_suffix = component_kebab:gsub("%-page$", "")
        if without_page_suffix ~= component_kebab then
            local by_component_without_page = path.join(style_parent_dir, "_" .. without_page_suffix .. ".scss")
            if fs.exists(by_component_without_page) then
                return by_component_without_page
            end
        end
    end

    return nil
end

--- Checks whether a page-relative Rust path belongs to a page components dir.
---
---@param rust_relative string Path relative to the configured pages root.
---@return boolean is_component_file Whether the path is nested under `components`.
---
local function is_page_component_file(rust_relative)
    return rust_relative:match("^components/") ~= nil or rust_relative:match("/components/") ~= nil
end

--- Builds a page entry for a Rust page component file.
---
---@param page_rs string Rust page path.
---@param component_name string Parsed page component name.
---@param paths table Resolved project paths.
---@return table|nil page Page entry, or nil when the file is not a supported page layout.
---
local function build_page_entry(page_rs, component_name, paths)
    local rust_relative = path.relative(paths.pages_dir, page_rs)
    if is_page_component_file(rust_relative) then
        return nil
    end

    local rust_parent_relative = vim.fn.fnamemodify(rust_relative, ":h")
    if rust_parent_relative == "." then
        rust_parent_relative = ""
    end

    local file_name = basename(page_rs)
    local module_name = vim.fn.fnamemodify(rust_relative, ":t:r")
    local is_module_layout = file_name == "page.rs"
    local module_relative_dir = module_name

    if is_module_layout then
        module_relative_dir = rust_parent_relative
        module_name = basename(module_relative_dir)
    elseif rust_parent_relative ~= "" then
        module_relative_dir = path.join(rust_parent_relative, module_name)
    end

    if module_relative_dir == "" then
        return nil
    end

    local page = {
        page_rs = page_rs,
        rust_path = page_rs,
        rust_relative = rust_relative,
        rust_parent_relative = rust_parent_relative,
        page_dir = path.join(paths.pages_dir, module_relative_dir),
        relative_dir = module_relative_dir,
        module_relative_dir = module_relative_dir,
        module_name = module_name,
        is_module_layout = is_module_layout,
        page_component_name = component_name,
        component_name = component_name,
        display_name = component_name:gsub("Page$", ""),
    }

    page.page_style_path = M.resolve_scss_path(page, paths)
    page.scss_path = page.page_style_path

    return page
end

--- Collects Leptos pages under the configured page root.
---
---@param paths table Resolved project paths.
---@return table[] pages Sorted page entries.
---
function M.collect(paths)
    if not paths or not paths.pages_dir then
        return {}
    end

    local page_files = vim.fn.glob(path.join(paths.pages_dir, "**/*.rs"), true, true)
    local page_by_module = {}
    local pages = {}

    for _, page_rs in ipairs(page_files) do
        if basename(page_rs) ~= "mod.rs" then
            local component_name = component_name_from_file(page_rs)

            if component_name and component_name:sub(-4) == "Page" then
                local page = build_page_entry(page_rs, component_name, paths)
                if page then
                    local existing = page_by_module[page.module_relative_dir]
                    if not existing or (page.is_module_layout and not existing.is_module_layout) then
                        page_by_module[page.module_relative_dir] = page
                    end
                end
            end
        end
    end

    for _, page in pairs(page_by_module) do
        table.insert(pages, page)
    end

    table.sort(pages, function(left, right)
        if left.display_name == right.display_name then
            return left.module_relative_dir < right.module_relative_dir
        end

        return left.display_name < right.display_name
    end)

    return pages
end

--- Opens a Rust page and its paired SCSS partial when present.
---
---@param page table Page entry containing `page_rs` and optional `page_style_path`.
---
function M.open_pair(page)
    local rust_path = page.page_rs or page.rust_path
    local scss_path = page.page_style_path or page.scss_path

    vim.cmd("edit " .. vim.fn.fnameescape(rust_path))

    if scss_path then
        vim.cmd("vsplit " .. vim.fn.fnameescape(scss_path))
        vim.cmd("wincmd h")
    end
end

--- Opens a newly-created page pair after the current UI callback returns.
---
---@param rust_path string Rust file path.
---@param scss_path string|nil SCSS file path.
---
local function open_created_pair(rust_path, scss_path)
    vim.schedule(function()
        if not fs.exists(rust_path) then
            notify_warn("Rust file not found: " .. rust_path)
            return
        end

        M.open_pair({
            page_rs = rust_path,
            page_style_path = scss_path and fs.exists(scss_path) and scss_path or nil,
        })

        if scss_path and not fs.exists(scss_path) then
            notify_warn("Style file not found: " .. scss_path)
        end
    end)
end

--- Parses route and optional nested sub-route input into URL and file segments.
---
---@param route_value string Route input.
---@param subroute_value string|nil Optional nested route input.
---@return table|nil parsed Parsed route information.
---@return string|nil err Validation error.
---
function M.parse_route_segments(route_value, subroute_value)
    local raw_route = naming.trim(route_value)
    local raw_subroute = naming.trim(subroute_value)

    if raw_route == "" then
        return nil, "Route is required."
    end

    if raw_route == "/" and raw_subroute ~= "" then
        return nil, "Root route cannot include sub-route."
    end

    local route_segments = {}
    if raw_route ~= "/" then
        local normalized_route = raw_route:gsub("^/+", ""):gsub("/+$", "")
        for _, segment in ipairs(naming.split_path_segments(normalized_route)) do
            table.insert(route_segments, segment)
        end
    end

    local sub_segments = {}
    if raw_subroute ~= "" then
        local normalized_subroute = raw_subroute:gsub("^/+", ""):gsub("/+$", "")
        for _, segment in ipairs(naming.split_path_segments(normalized_subroute)) do
            table.insert(sub_segments, segment)
        end
    end

    local path_segments = {}
    local fs_segments = {}

    for _, segment in ipairs(route_segments) do
        table.insert(path_segments, naming.route_segment_to_path(segment))
        table.insert(fs_segments, naming.route_segment_to_fs(segment))
    end

    for _, segment in ipairs(sub_segments) do
        table.insert(path_segments, naming.route_segment_to_path(segment))
        table.insert(fs_segments, naming.route_segment_to_fs(segment))
    end

    local route_path = #path_segments == 0 and "/" or "/" .. table.concat(path_segments, "/")

    return {
        route_path = route_path,
        path_segments = path_segments,
        fs_segments = fs_segments,
        route_segments = route_segments,
        sub_segments = sub_segments,
    },
        nil
end

--- Builds the generated page component name.
---
---@param input_name string Raw page name input.
---@return string|nil component_name Component name with `Page` suffix.
---
local function build_page_component_name(input_name)
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
local function class_name_from_component(component_name)
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
local function build_page_rust_template(component_name, class_name)
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

--- Builds the SCSS source template for a generated page.
---
---@param class_name string kebab-case CSS class name.
---@return string[] lines SCSS source lines.
---
local function build_scss_template(class_name)
    return {
        string.format(".%s {", class_name),
        "}",
    }
end

--- Records a changed Rust module file after a mutation helper returns true.
---
---@param tracker table Touched-file tracker.
---@param file_path string File path to mark.
---@param changed boolean Whether the file changed.
---
local function mark_when_changed(tracker, file_path, changed)
    if changed then
        touch.mark(tracker, file_path)
    end
end

--- Checks whether root pages exports already wildcard-export a top segment.
---
---@param pages_root_mod string Root pages `mod.rs` path.
---@param top_segment string|nil Top filesystem route segment.
---@return boolean has_wildcard Whether `pub use segment::*;` exists.
---
local function has_root_wildcard_export(pages_root_mod, top_segment)
    if not top_segment then
        return false
    end

    return line_utils.has(fs.read_lines(pages_root_mod), "pub use " .. top_segment .. "::*;")
end

--- Ensures the generated page component is exported from page modules.
---
---@param paths table Resolved project paths.
---@param fs_segments string[] Filesystem route segments.
---@param component_name string Page component name.
---@param tracker table Touched-file tracker.
---
local function ensure_page_export(paths, fs_segments, component_name, tracker)
    local pages_root_mod = path.join(paths.pages_dir, "mod.rs")
    local top_segment = fs_segments[1]
    local root_wildcard = has_root_wildcard_export(pages_root_mod, top_segment)

    if root_wildcard and #fs_segments > 1 then
        local tail_segments = {}
        for index = 2, #fs_segments do
            table.insert(tail_segments, fs_segments[index])
        end

        local top_mod = path.join(paths.pages_dir, top_segment, "mod.rs")
        local top_use = table.concat(tail_segments, "::") .. "::" .. component_name

        mark_when_changed(tracker, top_mod, rust.ensure_use_declaration(top_mod, top_use))
        mark_when_changed(tracker, top_mod, rust.normalize_mod_layout(top_mod))
        return
    end

    if not root_wildcard then
        local root_use = table.concat(fs_segments, "::") .. "::" .. component_name

        mark_when_changed(tracker, pages_root_mod, rust.ensure_use_declaration(pages_root_mod, root_use))
        mark_when_changed(tracker, pages_root_mod, rust.normalize_mod_layout(pages_root_mod))
    end
end

--- Ensures Rust module declarations for a generated page.
---
---@param paths table Resolved project paths.
---@param parent_segments string[] Parent route filesystem segments.
---@param leaf_segment string Leaf route filesystem segment.
---@param tracker table Touched-file tracker.
---
local function update_page_modules(paths, parent_segments, leaf_segment, tracker)
    local current_pages_dir = paths.pages_dir

    for _, segment in ipairs(parent_segments) do
        local parent_mod = path.join(current_pages_dir, "mod.rs")
        mark_when_changed(tracker, parent_mod, rust.ensure_mod_declaration(parent_mod, segment))
        mark_when_changed(tracker, parent_mod, rust.normalize_mod_layout(parent_mod))

        current_pages_dir = path.join(current_pages_dir, segment)
        fs.ensure_directory(current_pages_dir)
        fs.ensure_file(path.join(current_pages_dir, "mod.rs"))
    end

    local leaf_parent_mod = path.join(current_pages_dir, "mod.rs")
    mark_when_changed(tracker, leaf_parent_mod, rust.ensure_mod_declaration(leaf_parent_mod, leaf_segment))
    mark_when_changed(tracker, leaf_parent_mod, rust.normalize_mod_layout(leaf_parent_mod))
end

--- Ensures the inner `mod.rs` for a generated module-layout page.
---
---@param page_dir string Directory containing the generated `page.rs`.
---@param component_name string Page component name.
---@param tracker table Touched-file tracker.
---
local function update_module_layout_page_mod(page_dir, component_name, tracker)
    local page_mod = path.join(page_dir, "mod.rs")

    mark_when_changed(tracker, page_mod, rust.ensure_mod_declaration(page_mod, "page"))
    mark_when_changed(tracker, page_mod, rust.ensure_use_declaration(page_mod, "page::" .. component_name))
    mark_when_changed(tracker, page_mod, rust.normalize_mod_layout(page_mod))
end

--- Returns parent route segments from a full route segment list.
---
---@param fs_segments string[] Full filesystem route segments.
---@return string[] parent_segments All route segments except the leaf.
---
local function parent_segments_from(fs_segments)
    local parent_segments = {}

    for index = 1, #fs_segments - 1 do
        table.insert(parent_segments, fs_segments[index])
    end

    return parent_segments
end

--- Validates that nested generation is not being created under a flat page.
---
---@param paths table Resolved project paths.
---@param parent_segments string[] Parent route filesystem segments.
---@return string|nil err Error message when a flat page blocks nesting.
---
local function validate_no_flat_parent_page(paths, parent_segments)
    local pages_cursor = paths.pages_dir

    for _, segment in ipairs(parent_segments) do
        local conflicting_flat_page = path.join(pages_cursor, segment .. ".rs")
        if fs.exists(conflicting_flat_page) then
            return "Cannot create nested page under flat page: "
                .. conflicting_flat_page
                .. ". Convert it to a module first."
        end

        pages_cursor = path.join(pages_cursor, segment)
    end

    return nil
end

--- Creates Rust and SCSS files for a new page and inserts its app route.
---
---@param opts table Options containing `route` and `page_name`; accepts `subroute`, `private`, `module_layout`, `paths`, `open`, and `format_opts`.
---@return table|nil result Creation result with paths and touched files.
---@return string|nil err Error message when creation fails.
---
function M.create(opts)
    local options = opts or {}
    local parsed, parse_error = M.parse_route_segments(options.route, options.subroute)
    if parse_error then
        notify_warn(parse_error)
        return nil, parse_error
    end

    local component_name = build_page_component_name(options.page_name)
    if not component_name then
        local err = "Invalid page name."
        notify_warn(err)
        return nil, err
    end

    if #parsed.fs_segments == 0 then
        local err = "Root route generation is not supported by this generator."
        notify_warn(err)
        return nil, err
    end

    local class_name = class_name_from_component(component_name)
    if not class_name then
        local err = "Invalid page class name."
        notify_warn(err)
        return nil, err
    end

    local paths = options.paths or resolve_paths({ "pages_dir", "page_styles_dir", "app_path" })
    if not paths then
        return nil, "Could not resolve page project paths."
    end

    local leaf_segment = parsed.fs_segments[#parsed.fs_segments]
    local parent_segments = parent_segments_from(parsed.fs_segments)
    local flat_parent_error = validate_no_flat_parent_page(paths, parent_segments)
    if flat_parent_error then
        notify_warn(flat_parent_error)
        return nil, flat_parent_error
    end

    local current_pages_dir = paths.pages_dir
    local current_style_dir = paths.page_styles_dir
    for _, segment in ipairs(parent_segments) do
        current_pages_dir = path.join(current_pages_dir, segment)
        current_style_dir = path.join(current_style_dir, segment)
    end

    fs.ensure_directory(current_pages_dir)
    fs.ensure_directory(current_style_dir)

    local module_layout = options.module_layout == true
    local flat_rust_path = path.join(current_pages_dir, leaf_segment .. ".rs")
    local module_page_path = path.join(current_pages_dir, leaf_segment, "page.rs")
    local scss_stem = naming.to_kebab_case(leaf_segment)
    local flat_scss_path = path.join(current_style_dir, "_" .. scss_stem .. ".scss")
    local module_scss_path = path.join(current_style_dir, leaf_segment, "_page.scss")
    local rust_path = module_layout and module_page_path or flat_rust_path
    local scss_path = module_layout and module_scss_path or flat_scss_path

    if fs.exists(flat_rust_path) or fs.exists(module_page_path) then
        local err = "Page already exists: " .. flat_rust_path
        notify_warn(err)
        return nil, err
    end

    if fs.exists(flat_scss_path) or fs.exists(module_scss_path) then
        local err = "Page style already exists: " .. flat_scss_path
        notify_warn(err)
        return nil, err
    end

    if module_layout then
        fs.ensure_directory(path.join(current_pages_dir, leaf_segment))
        fs.ensure_directory(path.join(current_style_dir, leaf_segment))
    end

    fs.write_lines(rust_path, build_page_rust_template(component_name, class_name))
    fs.write_lines(scss_path, build_scss_template(class_name))

    local tracker = touch.new()
    touch.mark(tracker, rust_path)
    touch.mark(tracker, scss_path)

    update_page_modules(paths, parent_segments, leaf_segment, tracker)
    if module_layout then
        update_module_layout_page_mod(path.join(current_pages_dir, leaf_segment), component_name, tracker)
    end

    ensure_page_export(paths, parsed.fs_segments, component_name, tracker)
    if module_layout then
        scss.ensure_forward_chain(paths.page_styles_dir, parent_segments, leaf_segment, tracker)
        scss.ensure_forward(path.join(current_style_dir, leaf_segment, "index.scss"), "page", tracker)
    else
        scss.ensure_forward_chain(paths.page_styles_dir, parent_segments, scss_stem, tracker)
    end

    mark_when_changed(
        tracker,
        paths.app_path,
        rust.insert_route(paths.app_path, parsed.route_path, component_name, { private = options.private == true })
    )

    local formatted = touch.format_touched(tracker, options.format_opts)

    if options.open then
        open_created_pair(rust_path, scss_path)
    end

    return {
        component_name = component_name,
        class_name = class_name,
        module_name = leaf_segment,
        is_module_layout = module_layout,
        relative_dir = table.concat(parsed.fs_segments, "/"),
        route_path = parsed.route_path,
        private = options.private == true,
        rust_path = rust_path,
        scss_path = scss_path,
        touched_paths = tracker:paths(),
        formatted_count = formatted,
    }
end

--- Collects existing page subdirectories for the generation prompt.
---
---@param paths table Resolved project paths.
---@return string[] directories Relative page directories.
---
local function collect_page_subdirectories(paths)
    local directories = vim.fn.glob(path.join(paths.pages_dir, "**/"), true, true)
    local seen = {}
    local results = {}

    for _, directory in ipairs(directories) do
        local cleaned = directory:gsub("/$", "")
        if cleaned ~= paths.pages_dir then
            local relative = path.relative(paths.pages_dir, cleaned)
            local is_components_path = relative == "components"
                or relative:match("^components/")
                or relative:match("/components$")
                or relative:match("/components/")

            if relative ~= "" and relative ~= cleaned and not is_components_path and not seen[relative] then
                seen[relative] = true
                table.insert(results, relative)
            end
        end
    end

    table.sort(results)
    return results
end

--- Prompts for an existing or new page subdirectory.
---
---@param paths table Resolved project paths.
---@param on_select fun(relative_dir: string)
---
local function choose_page_subdirectory(paths, on_select)
    local options = collect_page_subdirectories(paths)
    table.insert(options, "+ Create new sub-directory")

    vim.ui.select(options, { prompt = "Select page sub-directory" }, function(choice)
        if not choice then
            return
        end

        if choice == "+ Create new sub-directory" then
            vim.ui.input({ prompt = "New sub-directory (relative to pages): " }, function(new_dir)
                if not new_dir or naming.trim(new_dir) == "" then
                    return
                end

                local normalized = naming.normalize_relative_dir(new_dir)
                if normalized == "" then
                    notify_warn("Invalid sub-directory.")
                    return
                end

                on_select(normalized)
            end)
        else
            on_select(choice)
        end
    end)
end

--- Prompts for page route metadata and creates a page pair.
---
---@param paths table Resolved project paths.
---
local function prompt_create_page(paths)
    vim.ui.input({ prompt = "Route: " }, function(route_value)
        if not route_value or naming.trim(route_value) == "" then
            return
        end

        vim.ui.select({ "Private", "Public" }, { prompt = "Route visibility" }, function(visibility)
            if not visibility then
                return
            end

            vim.ui.input({ prompt = "Page name (without Page): " }, function(page_name)
                if not page_name or naming.trim(page_name) == "" then
                    return
                end

                vim.ui.select({ "Flat", "Module" }, { prompt = "Page layout" }, function(layout)
                    if not layout then
                        return
                    end

                    local module_layout = layout == "Module"

                    vim.ui.select({ "No", "Yes" }, { prompt = "Nest page in a sub-directory?" }, function(choice)
                        if not choice then
                            return
                        end

                        if choice == "No" then
                            M.create({
                                route = route_value,
                                private = visibility == "Private",
                                page_name = page_name,
                                subroute = "",
                                module_layout = module_layout,
                                paths = paths,
                                open = true,
                            })
                        else
                            choose_page_subdirectory(paths, function(subroute)
                                M.create({
                                    route = route_value,
                                    private = visibility == "Private",
                                    page_name = page_name,
                                    subroute = subroute,
                                    module_layout = module_layout,
                                    paths = paths,
                                    open = true,
                                })
                            end)
                        end
                    end)
                end)
            end)
        end)
    end)
end

--- Opens a Telescope picker for existing pages.
---
function M.pick()
    local paths = resolve_paths({ "pages_dir" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.pages_dir) then
        notify_warn("Pages directory not found: " .. paths.pages_dir)
        return
    end

    local ok_actions, actions = pcall(require, "telescope.actions")
    local ok_action_state, action_state = pcall(require, "telescope.actions.state")
    local ok_finders, finders = pcall(require, "telescope.finders")
    local ok_pickers, pickers = pcall(require, "telescope.pickers")
    local ok_config, telescope_config = pcall(require, "telescope.config")

    if not (ok_actions and ok_action_state and ok_finders and ok_pickers and ok_config) then
        notify_warn("Telescope is required to pick pages.")
        return
    end

    local pages = M.collect(paths)
    if #pages == 0 then
        notify_warn("No page components found in " .. paths.pages_dir)
        return
    end

    pickers
        .new({}, {
            prompt_title = "Open Page",
            finder = finders.new_table({
                results = pages,
                entry_maker = function(page)
                    return {
                        value = page,
                        display = page.display_name .. "  " .. page.rust_relative,
                        ordinal = page.display_name .. " " .. page.page_component_name .. " " .. page.relative_dir,
                    }
                end,
            }),
            sorter = telescope_config.values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)

                    if selection and selection.value then
                        M.open_pair(selection.value)
                    end
                end)

                return true
            end,
        })
        :find()
end

--- Prompts for a page route and creates a new page pair.
---
function M.generate()
    local paths = resolve_paths({ "pages_dir", "page_styles_dir", "app_path" })
    if not paths then
        return
    end

    if not fs.is_directory(paths.pages_dir) then
        notify_warn("Pages directory not found: " .. paths.pages_dir)
        return
    end

    if not fs.is_directory(paths.page_styles_dir) then
        notify_warn("Page styles directory not found: " .. paths.page_styles_dir)
        return
    end

    if not fs.exists(paths.app_path) then
        notify_warn("App file not found: " .. paths.app_path)
        return
    end

    prompt_create_page(paths)
end

return M
