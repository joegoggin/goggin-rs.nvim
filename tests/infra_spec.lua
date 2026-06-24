--- Infrastructure helper tests.
---
--- Verifies path, filesystem, touched-file tracking, and formatting helpers
--- used by source mutation workflows.

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

--- Verifies path helpers preserve join, relative, and normalization behavior.
---
--- # Example Under Test
---
--- A temporary root is joined, relativized, tested for absoluteness, and
--- normalized with and without trailing slashes.
---
--- # Assertions
---
--- - Empty path parts are skipped when joining.
--- - Child paths are returned relative to the root.
--- - Non-child paths are left unchanged.
--- - Unix and Windows absolute paths are detected.
--- - Directory normalization handles nil, blank, trailing slash, and root paths.
---
test("path helpers preserve join normalize and relative behavior", function()
    local root = path.join(temp_root, "path-helpers")
    mkdir(root)

    assert_equals(path.join(root, nil, "", "src", "pages"), root .. "/src/pages", "join should skip empty parts")
    assert_equals(path.relative(root, root), "", "relative should strip matching root")
    assert_equals(
        path.relative(root, path.join(root, "src", "pages")),
        "src/pages",
        "relative should strip root prefix"
    )
    assert_equals(
        path.relative(root, root .. "-other/file.rs"),
        root .. "-other/file.rs",
        "relative should leave non-child paths alone"
    )
    assert_equals(path.basename(path.join(root, "src", "pages", "admin.rs")), "admin.rs", "basename should resolve")
    assert_equals(path.is_absolute(root), true, "absolute unix path should be detected")
    assert_equals(path.is_absolute("C:/web/src"), true, "absolute windows path should be detected")
    assert_equals(path.is_absolute("src/pages"), false, "relative path should not be absolute")
    assert_equals(path.normalize_dir(nil), nil, "nil directory should normalize to nil")
    assert_equals(path.normalize_dir(""), nil, "empty directory should normalize to nil")
    assert_equals(path.normalize_dir(root .. "/"), root, "directory normalization should strip trailing slash")
    assert_equals(path.normalize_dir("/"), "/", "directory normalization should preserve root")
end)

--- Verifies filesystem helpers for missing, existing, and ensured paths.
---
--- # Example Under Test
---
--- A temporary nested directory and files are created through the filesystem
--- helper module.
---
--- # Assertions
---
--- - Missing files report non-existence and read as an empty line list.
--- - Nested directories are created on demand.
--- - Written files exist and read back with the same lines.
--- - Ensured files are created empty when missing.
---
test("filesystem helpers read write and ensure paths", function()
    local root = path.join(temp_root, "fs-helpers")
    local nested = path.join(root, "nested")
    local file_path = path.join(nested, "notes.txt")

    assert_equals(fs.exists(file_path), false, "missing file should not exist")
    assert_list_equals(fs.read_lines(file_path), {}, "missing file should read as empty lines")

    fs.ensure_directory(nested)
    assert_equals(fs.is_directory(nested), true, "ensure_directory should create nested directories")

    fs.write_lines(file_path, { "one", "two" })
    assert_equals(fs.exists(file_path), true, "written file should exist")
    assert_list_equals(fs.read_lines(file_path), { "one", "two" }, "read_lines should return written lines")
    fs.ensure_directory(path.join(root, "alpha", "beta"))
    fs.ensure_directory(path.join(root, "alpha", "gamma"))
    assert_list_equals(
        fs.relative_subdirectories(root),
        { "alpha", "alpha/beta", "alpha/gamma", "nested" },
        "relative_subdirectories should return sorted descendants"
    )

    local empty_file = path.join(root, "empty.txt")
    fs.ensure_file(empty_file)
    assert_equals(fs.exists(empty_file), true, "ensure_file should create missing file")
    assert_list_equals(fs.read_lines(empty_file), {}, "ensure_file should create an empty file")
end)

--- Verifies touched-file tracking and formatting dispatch.
---
--- # Example Under Test
---
--- A touched-file tracker records Rust, SCSS, and text paths while formatting
--- is stubbed to avoid requiring an attached LSP formatter.
---
--- # Assertions
---
--- - First-seen paths are recorded in order.
--- - Duplicate paths are ignored.
--- - Only Rust and SCSS files are formatted.
--- - Formatting options are passed through unchanged.
---
test("touch helpers dedupe paths and dispatch format targets", function()
    local tracker = touch.new()
    local rust_path = path.join(temp_root, "touch", "component.rs")
    local scss_path = path.join(temp_root, "touch", "_component.scss")
    local text_path = path.join(temp_root, "touch", "notes.txt")

    assert_equals(tracker:mark(rust_path), true, "first rust mark should be recorded")
    assert_equals(tracker:mark(scss_path), true, "first scss mark should be recorded")
    assert_equals(tracker:mark(text_path), true, "first text mark should be recorded")
    assert_equals(tracker:mark(rust_path), false, "duplicate mark should be ignored")
    assert_list_equals(tracker:paths(), {
        rust_path,
        scss_path,
        text_path,
    }, "tracker should preserve first-seen order")

    local original_format_file = touch.format_file
    local formatted = {}
    rawset(touch, "format_file", function(file_path, opts)
        table.insert(formatted, file_path .. ":" .. tostring(opts.timeout_ms))
        return true
    end)

    local count = touch.format_touched(tracker, { timeout_ms = 25 })
    rawset(touch, "format_file", original_format_file)

    assert_equals(count, 2, "only rust and scss files should be formatted")
    assert_list_equals(formatted, {
        rust_path .. ":25",
        scss_path .. ":25",
    }, "format dispatch should preserve touched-file order")
end)

--- Verifies file formatting does not write already-modified buffers.
---
--- # Example Under Test
---
--- A file is loaded into a buffer, changed without writing, then passed to
--- `format_file` in a session without an attached formatter.
---
--- # Assertions
---
--- - Formatting returns false.
--- - The unsaved buffer contents are not written to disk.
---
test("touch format_file skips modified loaded buffers", function()
    local file_path = path.join(temp_root, "touch", "loaded.rs")
    write_file(file_path, { "disk" })

    local bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "unsaved" })

    assert_equals(touch.format_file(file_path), false, "modified loaded buffer should not format")
    assert_list_equals(fs.read_lines(file_path), { "disk" }, "format_file should not write unsaved edits")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end)
