---@class pesto.RemoteCacheInfo
---@field uri string
---@field remote_headers string[]

--- Parses quickfix items from failed action logs.
---
--- When a build fails, Bazel includes the "action completed" events for the
--- failed actions. The action completed events include a URI to stederr logs
--- for the action. This item loader fetches the logs--which may be stored
--- remotely--and parses the quickfix items.
---@class pesto.ActionLogsQuickfixItemLoader
---@field private _quickfix_item_parser pesto.QuickfixItemParser
---@field private _build_event_file_loader pesto.BuildEventFileLoader
---@field private _mnemonic_errorformat_resolver pesto.MnemonicErrorformatResolver
local ActionLogsQuickfixItemLoader = {}
ActionLogsQuickfixItemLoader.__index = ActionLogsQuickfixItemLoader

---@param quickfix_item_parser pesto.QuickfixItemParser
---@param build_event_file_loader pesto.BuildEventFileLoader
---@param mnemonic_errorformat_resolver pesto.MnemonicErrorformatResolver
---@return pesto.ActionLogsQuickfixItemLoader
function ActionLogsQuickfixItemLoader:new(
  quickfix_item_parser,
  build_event_file_loader,
  mnemonic_errorformat_resolver
)
  local o = setmetatable({}, ActionLogsQuickfixItemLoader)

  o._quickfix_item_parser = quickfix_item_parser
  o._build_event_file_loader = build_event_file_loader
  o._mnemonic_errorformat_resolver = mnemonic_errorformat_resolver

  return o
end

---@param build_events pesto.BuildEventTree
---@param on_items_loaded fun(qf_items: table[]) Called when a batch quickfix items have been parsed
---@param on_error fun(err: any) Called when an error occurs
---@param on_done fun()|nil Called once, after the logs of every failed action were loaded or failed to load
function ActionLogsQuickfixItemLoader:get_quickfix_items(
  build_events,
  on_items_loaded,
  on_error,
  on_done
)
  local logger = require('pesto.logger')

  -- Fetches may complete synchronously (local files) or asynchronously
  -- (remote caches), so count them and report completion only once all have
  -- been started and none is pending.
  local pending_fetches = 0
  local all_fetches_started = false
  local called_on_done = false
  local function maybe_call_on_done()
    if all_fetches_started and pending_fetches == 0 and not called_on_done then
      called_on_done = true
      if on_done then
        on_done()
      end
    end
  end

  local BuildEventTreeQueries = require('pesto.bazel.build_event_tree_queries')
  local build_event_tree_queries = BuildEventTreeQueries:new(build_events)

  local workspace_root = build_event_tree_queries:get_workspace_directory()
  if workspace_root == nil then
    logger.debug('Failed to extract workspace root')
    workspace_root = ''
  end

  ---@type pesto.bep.BuildEvent[]
  local failed_actions = build_event_tree_queries:find_failed_action_completed_events()
  logger.debug(string.format('Found %d failed action(s)', #failed_actions))

  vim.iter(failed_actions):each(function(action_completed_event)
    ---@type string|nil
    local stderr_uri = vim.tbl_get(action_completed_event, 'action', 'stderr', 'uri')
    if stderr_uri == nil then
      logger.trace(
        string.format(
          'Failed to extract stderr_uri. action_id_key=%s',
          action_completed_event.id_key
        )
      )
      return
    end

    local mnemonic = vim.tbl_get(action_completed_event, 'action', 'type')
    if mnemonic == nil then
      logger.trace(
        string.format('Failed to extract mnemonic. action_id_key=%s', action_completed_event.id_key)
      )
      return
    end

    local errorformat = self._mnemonic_errorformat_resolver:get_errorformat(mnemonic)
    if errorformat == nil then
      logger.trace(
        string.format(
          'Failed to resolve errorformat for failed action. action_id_key=%s, stderr_uri=%s, mnemonic=%s',
          action_completed_event.id_key,
          stderr_uri,
          mnemonic
        )
      )
      return
    end

    ---@type pesto.RemoteCacheInfo|nil
    local remote_cache_info

    local BuildEventFileLoader = require('pesto.bazel.build_event_file_loader')
    if BuildEventFileLoader.is_byte_stream_uri(stderr_uri) and remote_cache_info == nil then
      remote_cache_info = self:_get_remote_cache_info(build_events)
    end

    pending_fetches = pending_fetches + 1
    local settled = false
    local function settle()
      if not settled then
        settled = true
        pending_fetches = pending_fetches - 1
        maybe_call_on_done()
      end
    end

    local ok, err = pcall(self._build_event_file_loader.fetch_file, self._build_event_file_loader, {
      uri = stderr_uri,
      on_load = function(stderr_lines)
        logger.debug(string.format('Fetched stderr logs. uri=%s', stderr_uri))
        local parse_ok, parse_err = pcall(function()
          local items = self._quickfix_item_parser:parse(stderr_lines, errorformat, workspace_root)
          on_items_loaded(items)
        end)
        settle()
        if not parse_ok then
          error(parse_err)
        end
      end,
      on_error = function(fetch_err)
        logger.error(
          string.format('Error loading action stderr file %s: %s', stderr_uri, tostring(fetch_err))
        )
        on_error(fetch_err)
        settle()
      end,
      remote_cache_uri = vim.tbl_get(remote_cache_info or {}, 'uri'),
      remote_headers = vim.tbl_get(remote_cache_info or {}, 'remote_headers'),
    })
    if not ok then
      logger.error(string.format('Failed to fetch %s: %s', stderr_uri, tostring(err)))
      settle()
    end
  end)

  all_fetches_started = true
  maybe_call_on_done()
end

---@param build_events pesto.BuildEventTree
---@return pesto.RemoteCacheInfo|nil
function ActionLogsQuickfixItemLoader:_get_remote_cache_info(build_events)
  local BuildEventsTreeQueries = require('pesto.bazel.build_event_tree_queries')
  local build_event_tree_queries = BuildEventsTreeQueries:new(build_events)

  local remote_cache_option = build_event_tree_queries:find_command_line_option(
    'canonical',
    'remote_cache'
  )[1] or build_event_tree_queries:find_command_line_option('canonical', 'remote_executor')[1]

  if not remote_cache_option or not remote_cache_option.option_value then
    return nil
  end

  local remote_headers =
    build_event_tree_queries:find_command_line_option('canonical', 'remote_header')

  return {
    uri = remote_cache_option.option_value,
    remote_headers = vim
      .iter(remote_headers)
      :map(function(h)
        return h.option_value
      end)
      :totable(),
  }
end

return ActionLogsQuickfixItemLoader
