--- SCSS forward and pruning tests.
---
--- Verifies SCSS forward mutation, forward chain creation, and generated
--- directory pruning boundaries for Rust and SCSS helpers.

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

--- Verifies SCSS forward mutations and nested forward chains.
---
--- # Example Under Test
---
--- An SCSS index starts with one forward, then a nested pages chain is created.
---
--- # Assertions
---
--- - New forwards are added once.
--- - Replacements update or add the requested target.
--- - Removed forwards disappear and missing forwards are ignored.
--- - The touched tracker records each changed index once.
--- - Nested indexes forward from root to child to leaf target.
---
test("scss helpers update forwards and forward chains", function()
    local root = path.join(temp_root, "scss-forwards")
    local index_path = path.join(root, "styles", "components", "index.scss")
    local tracker = touch.new()
    write_file(index_path, {
        '@forward "existing";',
    })

    assert_equals(scss.ensure_forward(index_path, "buttons", tracker), true, "forward should be added")
    assert_equals(scss.ensure_forward(index_path, "buttons", tracker), false, "forward should not duplicate")
    assert_equals(scss.replace_forward(index_path, "existing", "base", tracker), true, "forward should be replaced")
    assert_equals(
        scss.replace_forward(index_path, "missing", "layout", tracker),
        true,
        "missing forward should be added"
    )
    assert_equals(scss.remove_forward(index_path, "buttons", tracker), true, "forward should be removed")
    assert_equals(scss.remove_forward(index_path, "buttons", tracker), false, "missing forward should not change file")

    assert_list_equals(fs.read_lines(index_path), {
        '@forward "base";',
        '@forward "layout";',
    }, "forward mutations should produce expected index")

    local spaced_index_path = path.join(root, "styles", "components", "spaced.scss")
    write_file(spaced_index_path, {
        '  @forward   "existing"  ;',
        '@forward   "base"  ;',
    })

    assert_equals(
        scss.replace_forward(spaced_index_path, "existing", "base"),
        true,
        "replace_forward should parse whitespace-tolerant forwards"
    )
    assert_list_equals(fs.read_lines(spaced_index_path), {
        '@forward   "base"  ;',
    }, "replace_forward should not duplicate an existing target with spacing")

    assert_list_equals(tracker:paths(), {
        index_path,
    }, "tracker should record changed index once")

    local chain_root = path.join(root, "styles", "pages")
    local chain_tracker = touch.new()
    scss.ensure_forward_chain(chain_root, { "admin", "settings" }, "profile", chain_tracker)

    assert_list_equals(fs.read_lines(path.join(chain_root, "index.scss")), {
        '@forward "admin";',
    }, "root forward chain index should point to child")
    assert_list_equals(fs.read_lines(path.join(chain_root, "admin", "index.scss")), {
        '@forward "settings";',
    }, "nested forward chain index should point to child")
    assert_list_equals(fs.read_lines(path.join(chain_root, "admin", "settings", "index.scss")), {
        '@forward "profile";',
    }, "leaf forward chain index should point to target")
end)

--- Verifies Rust and SCSS empty-directory pruning.
---
--- # Example Under Test
---
--- Empty generated Rust and SCSS child directories each contain only an empty
--- marker file and have parent references.
---
--- # Assertions
---
--- - Empty child directories are deleted.
--- - Parent Rust module declarations and SCSS forwards are removed.
--- - Trackers record deleted marker files, directories, and updated parents.
---
--- # Why
---
--- Delete workflows should not leave empty generated directories or stale
--- parent references behind.
---
test("rust and scss helpers prune empty directories", function()
    local root = path.join(temp_root, "prune")
    local rust_root = path.join(root, "src", "pages")
    local rust_child = path.join(rust_root, "admin")
    local style_root = path.join(root, "styles", "pages")
    local style_child = path.join(style_root, "admin")

    write_file(path.join(rust_root, "mod.rs"), {
        "pub mod admin;",
        "pub use admin::AdminPage;",
    })
    write_file(path.join(rust_child, "mod.rs"), {})
    write_file(path.join(style_root, "index.scss"), {
        '@forward "admin";',
    })
    write_file(path.join(style_child, "index.scss"), {})

    local rust_tracker = touch.new()
    local style_tracker = touch.new()
    rust.prune_empty_dirs(rust_child, rust_root, rust_tracker)
    scss.prune_empty_dirs(style_child, style_root, style_tracker)

    assert_equals(fs.exists(rust_child), false, "empty rust directory should be removed")
    assert_equals(fs.exists(style_child), false, "empty style directory should be removed")
    assert_list_equals(fs.read_lines(path.join(rust_root, "mod.rs")), {}, "parent mod should remove empty child")
    assert_list_equals(fs.read_lines(path.join(style_root, "index.scss")), {}, "parent index should remove empty child")
    assert_list_equals(rust_tracker:paths(), {
        path.join(rust_child, "mod.rs"),
        rust_child,
        path.join(rust_root, "mod.rs"),
    }, "rust prune should track deleted child and updated parent")
    assert_list_equals(style_tracker:paths(), {
        path.join(style_child, "index.scss"),
        style_child,
        path.join(style_root, "index.scss"),
    }, "style prune should track deleted child and updated parent")
end)

--- Verifies pruning does not delete directories outside the root boundary.
---
--- # Example Under Test
---
--- An empty generated directory outside the configured root is passed to the
--- pruning helper with a different root boundary.
---
--- # Assertions
---
--- - The outside directory remains untouched.
---
test("prune ignores directories outside root boundary", function()
    local root = path.join(temp_root, "prune-boundary")
    local actual_root = path.join(root, "src", "pages")
    local outside = path.join(root, "other", "admin")

    write_file(path.join(outside, "mod.rs"), {})
    mkdir(actual_root)

    rust.prune_empty_dirs(outside, actual_root)

    assert_equals(fs.exists(outside), true, "outside directory should not be pruned")
    assert_equals(fs.exists(path.join(outside, "mod.rs")), true, "outside marker should remain")
end)
