-- Minimal init for headless testing (no user config, no lazyvim)
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.cmd("filetype off")
vim.cmd("syntax off")
