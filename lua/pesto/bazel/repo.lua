local M = {}

-- Note: BUILD.bazel takes precedence over BUILD [1]
-- [1]: https://bazel.build/concepts/build-files
local PACKAGE_MARKERS = {
  'BUILD.bazel',
  'BUILD',
}

-- Finds the corresponding build file for the source file in the given buffer.
--
---@param buf_nr number|nil
local function get_buffer_dir(buf_nr)
  local buffer_dir = nil
  if buf_nr == nil then
    -- Get the current buffer's path
    buffer_dir = vim.fn.expand('%:p:h')
  else
    local buffers = vim.fn.getbufinfo(buf_nr or '%')
    if #buffers < 1 then
      error('invalid buffer number')
    elseif buffers[1].name == '' then
      buffer_dir = vim.fn.getcwd(buffers[1].windows[1])
    else
      buffer_dir = vim.fn.fnamemodify(buffers[1].name, ':p:h')
    end
  end
  return buffer_dir
end

--- An explicit `dir` takes precedence over the buffer, so that callers can
--- resolve the package or workspace of a directory independently of the
--- current buffer.
---@param buf_nr number|nil
---@param dir string|nil
---@return string
local function get_start_dir(buf_nr, dir)
  if dir == nil then
    return get_buffer_dir(buf_nr)
  end
  -- The upward searches below need an absolute path: findfile() cannot climb
  -- above a relative path's first component.
  return vim.fs.normalize(vim.fn.fnamemodify(dir, ':p'))
end

-- Gets the label for the package that contains the file associated with the
-- given buffer, or the package that contains `dir` when it is given.
--
---@param buf_nr number|nil
---@param dir string|nil
---@return string|nil label The package label
function M.get_package_label(buf_nr, dir)
  local build_file_path = M.find_build_file(buf_nr, dir)
  if build_file_path == nil then
    return nil
  end
  local package_dir_path = vim.fn.fnamemodify(build_file_path, ':p:h')
  local root_dir_path = M.find_project_root_dir(buf_nr, dir)
  local package_rel_path = vim.fs.relpath(root_dir_path, package_dir_path)
  if package_rel_path == '.' then
    return '//'
  else
    return '//' .. package_rel_path
  end
end

-- Finds the corresponding build file for the source file in the given buffer,
-- or for `dir` when it is given.
--
---@param buf_nr number|nil
---@param dir string|nil
---@return string|nil
function M.find_build_file(buf_nr, dir)
  local project_root_dir = M.find_project_root_dir(buf_nr, dir)
  local files = vim.fs.find(PACKAGE_MARKERS, {
    type = 'file',
    path = get_start_dir(buf_nr, dir),
    upward = true,
    stop = vim.fs.joinpath(project_root_dir, '..'),
  })
  return files[1]
end

-- Finds the repo's root marker file
--
---@param buf_nr number|nil
---@param dir string|nil
function M.find_project_root_dir(buf_nr, dir)
  local root_marker_file = M.find_project_root_marker_file(buf_nr, dir)
  local root_dir = vim.fn.fnamemodify(root_marker_file, ':p:h')
  return root_dir
end

-- Finds the repo's root marker file
--
---@param buf_nr number|nil
---@param dir string|nil
---@return string|nil
function M.find_project_root_marker_file(buf_nr, dir)
  local start_dir = get_start_dir(buf_nr, dir)
  local root_marker_filenames = { 'MODULE.bazel', 'REPO.bazel', 'WORKSPACE', 'WORKSPACE.bazel' }
  for _, filename in ipairs(root_marker_filenames) do
    local root_marker_file = vim.fn.findfile(filename, start_dir .. ';')
    if root_marker_file and string.len(root_marker_file) > 0 then
      -- findfile() returns a path relative to Neovim's CWD when it can, which
      -- would make the workspace directory depend on the CWD.
      return vim.fn.fnamemodify(root_marker_file, ':p')
    end
  end
  return nil
end

---@param buf_nr number
---@param dir string|nil
---@return boolean
function M.is_in_bazel_repo(buf_nr, dir)
  return M.find_project_root_marker_file(buf_nr, dir) ~= nil
end

return M
