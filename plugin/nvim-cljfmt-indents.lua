if vim.g.nvim_cljfmt_loaded then return end;

local has_module, module = pcall(require, "nvim-cljfmt-indents")
if has_module then module.setup() end
