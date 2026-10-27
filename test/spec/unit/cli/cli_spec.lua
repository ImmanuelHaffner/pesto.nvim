describe('pesto.cli.parse_fargs', function()
  local cli = require('pesto.cli')

  it('passes arguments without global options through', function()
    assert.are.same(
      { fargs = { 'bazel', 'build', '//...' } },
      cli.parse_fargs({ 'bazel', 'build', '//...' })
    )
  end)

  it('splits off -C <dir>', function()
    assert.are.same(
      { cwd = 'foo/bar', fargs = { 'bazel', 'build', ':baz' } },
      cli.parse_fargs({ '-C', 'foo/bar', 'bazel', 'build', ':baz' })
    )
  end)

  it('leaves -C after the subcommand to the subcommand', function()
    assert.are.same({ fargs = { 'bazel', '-C', 'x' } }, cli.parse_fargs({ 'bazel', '-C', 'x' }))
  end)

  it('rejects -C without a directory', function()
    local parsed, err = cli.parse_fargs({ '-C' })
    assert.is_nil(parsed)
    assert.is_truthy(err:find('requires a directory'))
  end)
end)
