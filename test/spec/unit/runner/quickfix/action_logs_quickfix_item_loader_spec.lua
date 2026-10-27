describe('pesto.ActionLogsQuickfixItemLoader:get_quickfix_items', function()
  local busted_fixtures = require('busted.fixtures')
  local ActionLogsQuickfixItemLoader =
    require('pesto.runner.quickfix.action_logs_quickfix_item_loader')
  local BuildEventJsonLoader = require('pesto.bazel.build_event_json_loader')

  ---@param fixture string
  local function load_build_events(fixture)
    return BuildEventJsonLoader:new():load(busted_fixtures.path(fixture))
  end

  --- A file loader that records fetches so the test decides when, and how,
  --- each one completes.
  local function make_file_loader(complete_synchronously)
    local loader = { fetches = {} }
    function loader:fetch_file(opts)
      table.insert(self.fetches, opts)
      if complete_synchronously then
        opts.on_load({ opts.uri })
      end
    end
    return loader
  end

  local parser = {
    parse = function(_, lines)
      return vim.tbl_map(function(line)
        return { text = line }
      end, lines)
    end,
  }
  local errorformat_resolver = {
    get_errorformat = function()
      return '%m'
    end,
  }

  it('calls on_done once all asynchronous fetches have settled', function()
    local file_loader = make_file_loader(false)
    local loader = ActionLogsQuickfixItemLoader:new(parser, file_loader, errorformat_resolver)

    local items = {}
    local done_calls = 0
    loader:get_quickfix_items(
      load_build_events(
        'action_logs_quickfix_item_loader_spec_fixtures/two-failed-actions-bep.json'
      ),
      function(qf_items)
        vim.list_extend(items, qf_items)
      end,
      function() end,
      function()
        done_calls = done_calls + 1
      end
    )

    assert.are.equal(2, #file_loader.fetches)
    assert.are.equal(0, done_calls)

    file_loader.fetches[1].on_load({ 'error in a' })
    assert.are.equal(0, done_calls)

    file_loader.fetches[2].on_error('download failed')
    assert.are.equal(1, done_calls)
    assert.are.same({ { text = 'error in a' } }, items)

    -- A late duplicate callback must not report completion twice.
    file_loader.fetches[2].on_error('download failed')
    assert.are.equal(1, done_calls)
  end)

  it('calls on_done once when fetches complete synchronously', function()
    local file_loader = make_file_loader(true)
    local loader = ActionLogsQuickfixItemLoader:new(parser, file_loader, errorformat_resolver)

    local done_calls = 0
    loader:get_quickfix_items(
      load_build_events(
        'action_logs_quickfix_item_loader_spec_fixtures/two-failed-actions-bep.json'
      ),
      function() end,
      function() end,
      function()
        done_calls = done_calls + 1
      end
    )

    assert.are.equal(1, done_calls)
  end)

  it('calls on_done when no action failed', function()
    local file_loader = make_file_loader(false)
    local loader = ActionLogsQuickfixItemLoader:new(parser, file_loader, errorformat_resolver)

    local done_calls = 0
    loader:get_quickfix_items(
      load_build_events('../../bazel/build_event_tree_spec_fixtures/clean-compile.json'),
      function() end,
      function() end,
      function()
        done_calls = done_calls + 1
      end
    )

    assert.are.equal(0, #file_loader.fetches)
    assert.are.equal(1, done_calls)
  end)
end)
