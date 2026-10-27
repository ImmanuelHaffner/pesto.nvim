local M = {}

---@param config pesto.Config
function M.setup(config)
  vim.g.pesto = config
end

---@class pesto.RunOpts
--- Bazel arguments without the executable, e.g. `{ 'build', '//foo:bar' }`.
---@field cmd string[]
--- Run Bazel as if Pesto had been invoked from this directory. Defaults to the
--- package of the current buffer.
---@field cwd string|nil

--- Runs Bazel through the configured runner, like
--- `:Pesto [-C <cwd>] bazel <cmd>`.
---@param opts pesto.RunOpts
---@return integer id Matches `data.id` of the `User PestoBuild*` events for this run
function M.run(opts)
  if type(opts) ~= 'table' or type(opts.cmd) ~= 'table' or #opts.cmd == 0 then
    error('pesto.run: `cmd` must be a non-empty list of Bazel arguments', 2)
  end

  local runner = require('pesto.runner.runner')
  ---@type string|nil
  local cwd = nil
  if opts.cwd ~= nil then
    local err
    cwd, err = runner.resolve_cwd(opts.cwd)
    if cwd == nil then
      error('pesto.run: ' .. err, 2)
    end
  elseif not require('pesto.bazel.repo').is_in_bazel_repo(vim.api.nvim_get_current_buf()) then
    error('pesto.run: the current buffer is not in a Bazel workspace; pass `cwd`', 2)
  end

  ---@type Components
  local components = require('pesto.components')
  local bazel_command = { components.internal_config:get_bazel_executable() }
  vim.list_extend(bazel_command, opts.cmd)

  return components.internal_run_bazel_fn({
    bazel_command = bazel_command,
    context = runner.get_run_bazel_context({ cwd = cwd }),
  })
end

return M
