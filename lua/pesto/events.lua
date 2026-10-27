--- `User` autocommands that Pesto's default runner emits.
local M = {}

M.BUILD_SUCCEEDED = 'PestoBuildSucceeded'
M.BUILD_FAILED = 'PestoBuildFailed'

---@class pesto.BuildFinishedEventData
--- Matches the return value of `require('pesto').run()`.
---@field id integer|nil
---@field exit_code integer
--- The Bazel command line, including the executable and injected options.
---@field command string[]
--- Directory Bazel ran in.
---@field cwd string
---@field workspace_dir string
---@field bep_file string|nil
--- True if a newer build replaced this one before it finished. Pesto does not
--- load the quickfix list for such builds.
---@field superseded boolean
--- ID of the quickfix list holding the build's errors (see `:h
--- quickfix-ID`), nil for superseded builds.
---@field qf_id integer|nil

--- Emits `PestoBuildSucceeded` or `PestoBuildFailed`, depending on the exit
--- code.
---@param data pesto.BuildFinishedEventData
function M.emit_build_finished(data)
  local pattern = data.exit_code == 0 and M.BUILD_SUCCEEDED or M.BUILD_FAILED
  -- Scheduled so that an erroring handler cannot abort Pesto's own
  -- post-build processing, and so that handlers never run under textlock.
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', { pattern = pattern, data = data, modeline = false })
  end)
end

return M
