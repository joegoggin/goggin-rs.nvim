--- Public API compatibility tests.
---
--- Verifies legacy top-level require paths still load after the package
--- refactor and that the new infra package exposes focused helper modules.

local h = require("tests.helpers")

local assert_equals = h.assert_equals
local test = h.test

test("legacy top-level require paths re-export refactored modules", function()
    assert_equals(require("goggin-rs.component"), require("goggin-rs.components"), "component alias should load")
    assert_equals(require("goggin-rs.page"), require("goggin-rs.pages"), "page alias should load")
    assert_equals(require("goggin-rs.fs"), require("goggin-rs.infra.fs"), "fs alias should load")
    assert_equals(require("goggin-rs.lines"), require("goggin-rs.infra.lines"), "lines alias should load")
    assert_equals(require("goggin-rs.path"), require("goggin-rs.infra.path"), "path alias should load")
    assert_equals(require("goggin-rs.prune"), require("goggin-rs.infra.prune"), "prune alias should load")
    assert_equals(require("goggin-rs.telescope"), require("goggin-rs.infra.telescope"), "telescope alias should load")
    assert_equals(require("goggin-rs.touch"), require("goggin-rs.infra.touch"), "touch alias should load")
    assert_equals(type(require("goggin-rs.infra").fs.exists), "function", "infra package should expose helpers")
    assert_equals(type(require("goggin-rs.scss").pick_colors), "function", "scss package should expose color picker")
end)
