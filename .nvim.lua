-- Project-local Neovim config (sourced via 'exrc').
-- Supplies Vortex-specific indexing to svlangserver; the plugin itself is
-- configured globally in the LazyVim config.
--
-- Include dirs and defines mirror the verilator invocation in
-- sim/rtlsim/Makefile (RTL_INCLUDE / VL_FLAGS), with VM_ENABLE set for the
-- MMU work on this branch.

local root = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))

-- No format-on-save in this repo: reformatting upstream Vortex files creates
-- large diffs. Format explicitly with <leader>cf (verible, .verible-format.flags).
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "verilog", "systemverilog" },
  callback = function()
    vim.b.autoformat = false
  end,
})

local include_dirs = {
  "hw/rtl",
  "hw/dpi",
  "hw/rtl/libs",
  "hw/rtl/interfaces",
  "hw/rtl/core",
  "hw/rtl/mem",
  "hw/rtl/cache",
  "hw/rtl/fpu",
  -- VM_ENABLE (mmu) includes
  "hw/rtl/mmu",
  "hw/rtl/mmu/bsc_mmu/includes",
  "hw/rtl/mmu/bsc_mmu/rtl",
  "hw/rtl/mmu/bsc_mmu/rtl/tlb",
  "hw/rtl/mmu/bsc_mmu/rtl/tlb/storage",
  "hw/rtl/mmu/bsc_mmu/rtl/tlb/banked_tlb",
  "hw/rtl/mmu/bsc_mmu/rtl/tlb/multiport_tlb",
  "hw/rtl/mmu/bsc_mmu/rtl/ptw",
  "hw/rtl/mmu/bsc_mmu/rtl/common",
  "hw/rtl/mmu/bsc_mmu/rtl/vortex_adapter",
}

local defines = {
  "XLEN_32",
  "SIMULATION",
  "SV_DPI",
  "VM_ENABLE",
}

local lint_cmd = { "verilator", "-sv", "--lint-only", "-Wall" }
-- suppressions used by the project build (sim/rtlsim/Makefile) plus ones
-- that fire spuriously when linting a single file out of context
for _, w in ipairs({ "DECLFILENAME", "REDEFMACRO", "UNUSED", "PINCONNECTEMPTY" }) do
  table.insert(lint_cmd, "-Wno-" .. w)
end
for _, d in ipairs(defines) do
  table.insert(lint_cmd, "-D" .. d)
end
-- -I resolves `include; -y + libext auto-resolves module/package references
-- by filename (e.g. mmu_pkg -> mmu_pkg.sv) so single-file lint works
for _, dir in ipairs(include_dirs) do
  table.insert(lint_cmd, "-I" .. root .. "/" .. dir)
  table.insert(lint_cmd, "-y" .. root .. "/" .. dir)
end
table.insert(lint_cmd, "+libext+.sv+.vh")

vim.lsp.config("svlangserver", {
  -- pin the workspace root: bsc_mmu has its own .git, which would otherwise
  -- become the root for files inside it, breaking all the relative globs above
  root_dir = root,
  settings = {
    systemverilog = {
      includeIndexing = {
        "hw/rtl/**/*.{sv,vh}",
        "hw/dpi/**/*.{sv,vh}",
      },
      excludeIndexing = {
        "hw/syn/**",
        "build/**",
        "third_party/**",
      },
      defines = defines,
      launchConfiguration = table.concat(lint_cmd, " "),
    },
  },
})
