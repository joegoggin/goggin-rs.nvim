--- Headless fixture test runner for goggin-rs.nvim.
---
--- Configures package paths, loads every spec module, cleans up shared fixture
--- state, and prints the final passed-test count.

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = repo_root .. "/?.lua;" .. repo_root .. "/?/init.lua;" .. package.path

local h = require("tests.helpers")

require("tests.api_spec")
require("tests.infra_spec")
require("tests.project_spec")
require("tests.naming_spec")
require("tests.rust.components_spec")
require("tests.rust.modules_spec")
require("tests.rust.uses_spec")
require("tests.rust.routes_spec")
require("tests.scss_spec")
require("tests.components.collect_spec")
require("tests.components.create_spec")
require("tests.pages.collect_spec")
require("tests.pages.create_spec")
require("tests.pages.convert_spec")
require("tests.pages.components_spec")

h.finish()
print(string.format("passed %d tests", h.passed))
