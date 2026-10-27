describe('bazel_repo.get_package_label', function()
  local busted_fixtures = require('busted.fixtures')
  local bazel_repo_dir = busted_fixtures.path('repo_spec_example_repo_fixture')

  teardown(function()
    -- Clean up buffers opened during the test. Each test should clean up their
    -- own buffers, so we should only be closing buffers opened during this test.
    vim.iter(vim.api.nvim_list_bufs()):each(function(buf_id)
      if vim.api.nvim_buf_is_loaded(buf_id) then
        vim.api.nvim_buf_delete(buf_id, {})
      end
    end)
  end)

  it('correctly calculates package labels', function()
    ---@type {repo_file: string, expected_label: string}[]
    local test_cases = {
      {
        repo_file = 'BUILD',
        expected_label = '//',
      },
      {
        repo_file = 'a1/a2/a3/a3.sh',
        expected_label = '//a1/a2',
      },
      {
        repo_file = 'c1/c2/c2.sh',
        expected_label = '//c1/c2',
      },
    }

    for _, test_case in ipairs(test_cases) do
      local file_path = vim.fs.joinpath(bazel_repo_dir, test_case.repo_file)
      vim.cmd.edit(file_path)
      local bazel_repo = require('pesto.bazel.repo')
      local label = bazel_repo.get_package_label()
      assert.are.equal(test_case.expected_label, label)
    end
  end)

  it('resolves the package of an explicit directory', function()
    local bazel_repo = require('pesto.bazel.repo')
    local a3_dir = vim.fs.joinpath(bazel_repo_dir, 'a1/a2/a3')
    local c2_dir = vim.fs.joinpath(bazel_repo_dir, 'c1/c2')
    assert.are.equal('//a1/a2', bazel_repo.get_package_label(nil, a3_dir))
    assert.are.equal('//c1/c2', bazel_repo.get_package_label(nil, c2_dir))
    -- The fixture path may be relative; the marker file is always absolute.
    assert.are.equal(
      vim.fs.normalize(vim.fn.fnamemodify(vim.fs.joinpath(bazel_repo_dir, 'MODULE.bazel'), ':p')),
      vim.fs.normalize(bazel_repo.find_project_root_marker_file(nil, a3_dir))
    )
  end)
end)
