-- Minimal test harness for headless neovim testing.
-- Follows busted conventions (describe/it) without the dependency.
local M = {}

local total = 0
local passed = 0
local failed = 0
local failures = {}
local depth = 0
local prefix = {}

function M.describe(name, fn)
  depth = depth + 1
  table.insert(prefix, name)
  print(string.rep("  ", depth - 1) .. name)
  fn()
  table.remove(prefix)
  depth = depth - 1
end

function M.it(name, fn)
  total = total + 1
  local display = table.concat(prefix, " > ") .. " > " .. name
  local ok, err = pcall(fn)
  local indent = string.rep("  ", depth)
  if ok then
    passed = passed + 1
    print(indent .. "PASS  " .. name)
  else
    failed = failed + 1
    table.insert(failures, { name = display, err = tostring(err) })
    print(indent .. "FAIL  " .. name)
    print(indent .. "      " .. tostring(err))
  end
end

function M.eq(expected, actual, msg)
  if expected ~= actual then
    error(string.format("%s: expected %s, got %s",
      msg or "assertion failed",
      vim.inspect(expected),
      vim.inspect(actual)), 2)
  end
end

function M.neq(not_expected, actual, msg)
  if not_expected == actual then
    error(string.format("%s: expected NOT %s, got %s",
      msg or "assertion failed",
      vim.inspect(not_expected),
      vim.inspect(actual)), 2)
  end
end

function M.is_nil(val, msg)
  if val ~= nil then
    error(string.format("%s: expected nil, got %s",
      msg or "assertion failed",
      vim.inspect(val)), 2)
  end
end

function M.summary()
  print(string.format("\n=== %d passed, %d failed, %d total ===", passed, failed, total))
  if #failures > 0 then
    print("\nFailures:")
    for _, f in ipairs(failures) do
      print(string.format("  %s\n    %s", f.name, f.err))
    end
    vim.cmd("cquit 1")
  end
end

return M
