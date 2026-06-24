--- Infrastructure helper package.
---
--- Re-exports focused filesystem, line-list, path, pruning, Telescope, and
--- touched-file helpers through a single package module.

return {
    fs = require("goggin-rs.infra.fs"),
    lines = require("goggin-rs.infra.lines"),
    path = require("goggin-rs.infra.path"),
    prune = require("goggin-rs.infra.prune"),
    telescope = require("goggin-rs.infra.telescope"),
    touch = require("goggin-rs.infra.touch"),
}
