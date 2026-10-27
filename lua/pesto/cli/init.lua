local M = {}

M.COMMAND_NAME = 'Pesto'

--- `:Pesto -C <dir> <subcommand> ...` runs the subcommand as if Pesto had been
--- invoked from `<dir>` (cf. `git -C`, `make -C`).
M.CWD_OPTION = '-C'

---@class PestoCli
---@field run_command function
---@field complete function

---@class pesto.ParsedCommandLine
---@field cwd string|nil The (unresolved) directory given with `-C`
---@field fargs string[] The subcommand name followed by its arguments

--- Splits the global options off the front of the `:Pesto` arguments.
---@param fargs string[]
---@return pesto.ParsedCommandLine|nil parsed
---@return string|nil err
function M.parse_fargs(fargs)
  if fargs[1] ~= M.CWD_OPTION then
    return { fargs = fargs }
  end
  if fargs[2] == nil then
    return nil, string.format("option '%s' requires a directory", M.CWD_OPTION)
  end
  return { cwd = fargs[2], fargs = vim.list_slice(fargs, 3) }
end

---@param arg_lead string
---@param candidates table[string]
local function get_completion_candidates(arg_lead, candidates)
  local arg_lead_len = string.len(arg_lead)
  if arg_lead_len == 0 then
    return candidates
  end
  local matching_candiates = {}
  for _, candiate in ipairs(candidates) do
    if candiate:sub(1, arg_lead_len) == arg_lead then
      table.insert(matching_candiates, candiate)
    end
  end
  return matching_candiates
end

---@class pesto.CommandLineToken
---@field value string
---@field start_pos number 1-indexed
---@field end_pos number 1-indexed, inclusive

---@param line string
---@param init number
---@return pesto.CommandLineToken[]
local function tokenize(line, init)
  ---@type pesto.CommandLineToken[]
  local tokens = {}
  local pos = init
  while true do
    local token_start, token_end = line:find('[^%s]+', pos)
    if token_start == nil then
      break
    end
    table.insert(tokens, {
      value = line:sub(token_start, token_end),
      start_pos = token_start,
      end_pos = token_end,
    })
    pos = token_end + 1
  end
  return tokens
end

---@param subcommands {SUBCOMMAND_NAMES: string[], SUBCOMMANDS_BY_NAME: {[string]: pesto.Subcommand}}
---@return PestoCli
function M.make_cli(subcommands)
  -- See `:h command-completion-custom`
  ---@param arg_lead string
  ---@param cmd_line string
  ---@param cursor_pos number
  local function complete(arg_lead, cmd_line, cursor_pos)
    local command_start, command_end = cmd_line:find(M.COMMAND_NAME)
    if not command_start then
      return {}
    end

    local tokens = tokenize(cmd_line, command_end + 1)
    local one_indexed_cursor_pos = cursor_pos + 1

    --- A missing token is the one about to be typed at the cursor.
    ---@param token pesto.CommandLineToken|nil
    local function is_completing(token)
      return token == nil
        or (
          one_indexed_cursor_pos >= token.start_pos
          and one_indexed_cursor_pos <= token.end_pos + 1
        )
    end

    local subcommand_index = 1
    ---@type string|nil
    local cwd = nil
    if tokens[1] and tokens[1].value == M.CWD_OPTION and not is_completing(tokens[1]) then
      if is_completing(tokens[2]) then
        return vim.fn.getcompletion(arg_lead, 'dir')
      end
      local runner = require('pesto.runner.runner')
      cwd = runner.resolve_cwd(tokens[2].value)
      subcommand_index = 3
    end

    local subcommand_token = tokens[subcommand_index]
    if is_completing(subcommand_token) then
      local candidates = subcommands.SUBCOMMAND_NAMES
      if subcommand_index == 1 then
        candidates = vim.list_extend({ M.CWD_OPTION }, candidates)
      end
      return get_completion_candidates(arg_lead, candidates)
    end

    ---@cast subcommand_token pesto.CommandLineToken
    local subcommand_name = subcommand_token.value
    local logger = require('pesto.logger')
    logger.info('parsed subcommand: ' .. subcommand_name)
    ---@type pesto.Subcommand
    local subcommand = subcommands.SUBCOMMANDS_BY_NAME[subcommand_name]
    if subcommand and subcommand.complete then
      logger.info('parsed completing: ' .. subcommand_name)
      local subcmd_line = cmd_line:sub(subcommand_token.start_pos)
      local subcmd_cursor_pos = cursor_pos - subcommand_token.start_pos + 1
      local buf_nr = vim.api.nvim_get_current_buf()
      return subcommand.complete({
        subcommand_line = subcmd_line,
        cursor_pos = subcmd_cursor_pos,
        arg_lead = arg_lead,
        buf_nr = buf_nr,
        cwd = cwd,
      })
    end
    return {}
  end

  ---@param message string
  local function notify_error(message)
    vim.notify(string.format('[%s] %s', M.COMMAND_NAME, message), vim.log.levels.ERROR)
  end

  ---@param opts table See `:h lua-guide-commands-create`
  local function run_command(opts)
    local parsed, parse_error = M.parse_fargs(opts.fargs)
    if parsed == nil then
      notify_error(parse_error or 'invalid arguments')
      return
    end

    local subcommand_name = parsed.fargs[1]
    if subcommand_name == nil or string.len(subcommand_name) == 0 then
      notify_error('Missing subcommand')
      return
    end

    ---@type pesto.Subcommand|nil
    local subcommand = subcommands.SUBCOMMANDS_BY_NAME[subcommand_name]
    if subcommand == nil then
      notify_error(string.format("Invalid subcommand '%s'", subcommand_name))
      return
    end

    ---@type string|nil
    local cwd = nil
    if parsed.cwd ~= nil then
      if not subcommand.supports_cwd then
        notify_error(
          string.format("Subcommand '%s' does not support '%s'", subcommand_name, M.CWD_OPTION)
        )
        return
      end
      local runner = require('pesto.runner.runner')
      local resolve_error
      cwd, resolve_error = runner.resolve_cwd(parsed.cwd)
      if cwd == nil then
        notify_error(resolve_error or 'invalid directory')
        return
      end
    end

    subcommand.execute({
      fargs = vim.list_slice(parsed.fargs, 2),
      buf_nr = vim.api.nvim_get_current_buf(),
      cwd = cwd,
    })
  end

  return {
    run_command = run_command,
    complete = complete,
  }
end

return M
