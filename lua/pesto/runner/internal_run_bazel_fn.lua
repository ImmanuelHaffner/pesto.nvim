---@class pesto.InternalRunBazelFn
---@field private _internal_config pesto.InternalConfig
---@field private _command_history pesto.BazelRunHistory
---@field private _last_id integer
local InternalRunBazelFn = {}
InternalRunBazelFn.__index = InternalRunBazelFn

function InternalRunBazelFn:new(internal_config, command_history)
  local o = setmetatable({}, InternalRunBazelFn)

  o._internal_config = internal_config
  o._command_history = command_history
  o._last_id = 0

  return o
end

---@param opts pesto.RunBazelOpts
---@return integer id Identifies this invocation in the `User PestoBuild*` events
function InternalRunBazelFn:execute(opts)
  self._last_id = self._last_id + 1
  opts.id = self._last_id
  -- Note: downstream runners may modify or inject additional options. It'll be
  -- their job to modify the history.
  self._command_history:push_run_opts(vim.deepcopy(opts))
  self._internal_config:_get_bazel_runner()(opts)
  return opts.id
end

---@param opts pesto.RunBazelOpts
---@return integer id
function InternalRunBazelFn.__call(self, opts)
  return self:execute(opts)
end

return InternalRunBazelFn
