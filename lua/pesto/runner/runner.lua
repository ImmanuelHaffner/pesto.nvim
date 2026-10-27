local M = {}

---@class pesto.RunBazelContext
---@field workspace_dir string
---@field package_dir string|nil
---@field package_label string|nil
---@field buf_nr number
--- Directory to run Bazel in when it was given explicitly (e.g., by
--- `:Pesto -C <dir>` or `require('pesto').run()`). In that case the other
--- fields are resolved from this directory rather than from the current buffer.
---@field cwd string|nil

---@class pesto.RunBazelOpts
---@field bazel_command string[]
---@field context pesto.RunBazelContext
--- Identifies the invocation in the `User PestoBuild*` events. Assigned by
--- Pesto before the runner is called.
---@field id integer|nil

---@alias pesto.RunBazelFn fun(opts: pesto.RunBazelOpts)

---@class pesto.GetRunBazelContextOpts
---@field cwd string|nil Resolve the context from this directory instead of the current buffer

---@param opts pesto.GetRunBazelContextOpts|nil
---@return pesto.RunBazelContext
function M.get_run_bazel_context(opts)
  local cwd = opts and opts.cwd

  local bazel_repo = require('pesto.bazel.repo')
  local build_file = bazel_repo.find_build_file(nil, cwd)
  local build_dir = vim.fs.dirname(build_file)

  local buf_nr = vim.api.nvim_get_current_buf()
  local package_label = bazel_repo.get_package_label(nil, cwd)

  local workspace_marker_file = bazel_repo.find_project_root_marker_file(nil, cwd)
  local workspace_dir = vim.fs.dirname(workspace_marker_file)

  return {
    workspace_dir = workspace_dir,
    package_dir = build_dir,
    package_label = package_label,
    buf_nr = buf_nr,
    cwd = cwd,
  }
end

--- The directory Bazel should run in for the given context.
---@param context pesto.RunBazelContext
---@return string
function M.get_working_dir(context)
  return context.cwd or context.package_dir or context.workspace_dir
end

--- Normalizes a user-supplied directory (expanding `~`, `%`, and relative
--- paths) and checks that it lies in a Bazel workspace.
---@param dir string
---@return string|nil cwd The absolute directory, or nil on error
---@return string|nil err
function M.resolve_cwd(dir)
  local expanded = vim.fn.expand(dir)
  if expanded == '' then
    expanded = dir
  end
  local cwd = vim.fs.normalize(vim.fn.fnamemodify(expanded, ':p'))
  if cwd ~= '/' then
    cwd = cwd:gsub('/$', '')
  end
  if vim.fn.isdirectory(cwd) == 0 then
    return nil, string.format('not a directory: %s', dir)
  end
  local bazel_repo = require('pesto.bazel.repo')
  if bazel_repo.find_project_root_marker_file(nil, cwd) == nil then
    return nil, string.format('not in a Bazel workspace: %s', cwd)
  end
  return cwd
end

return M
