local M = {}

local defaults = {
    paths = {
        components_dir = "src/components",
        styles_components_dir = "styles/components",
        pages_dir = "src/pages",
        page_styles_dir = "styles/pages",
        app_path = "src/app.rs",
    },
}

local current = vim.deepcopy(defaults)

local function merge(opts)
    return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.setup(opts)
    current = merge(opts)
    return current
end

function M.get()
    return current
end

function M.defaults()
    return vim.deepcopy(defaults)
end

return M
