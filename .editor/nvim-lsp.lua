-- Routeplane — Neovim LSP wiring for the four stack language servers.
-- Usage (Neovim 0.11+, no plugins required): from the workspace root run
--     :luafile .editor/nvim-lsp.lua
-- or source it from your init.lua. Binaries resolve from PATH
-- (~/.cargo/bin, ~/bin, ~/.npm-global/bin).

local lsp = vim.lsp

-- rust-analyzer: point at the Cargo workspace in routeplane/, lint with clippy.
lsp.config["rust_analyzer"] = {
  cmd = { "rust-analyzer" },
  filetypes = { "rust" },
  root_markers = { "Cargo.toml", "Cargo.lock" },
  settings = {
    ["rust-analyzer"] = {
      check = { command = "clippy", allTargets = true },
      cargo = { buildScripts = { enable = true } },
      procMacro = { enable = true },
    },
  },
}

-- terraform-ls
lsp.config["terraformls"] = {
  cmd = { "terraform-ls", "serve" },
  filetypes = { "terraform", "terraform-vars", "hcl" },
  root_markers = { ".terraform", "*.tf", ".git" },
}

-- yaml-language-server: GitHub Actions + general YAML via SchemaStore.
lsp.config["yamlls"] = {
  cmd = { "yaml-language-server", "--stdio" },
  filetypes = { "yaml" },
  root_markers = { ".git" },
  settings = {
    yaml = {
      schemaStore = { enable = true },
      schemas = {
        ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
        ["https://json.schemastore.org/github-action.json"] = "/**/action.{yml,yaml}",
      },
    },
  },
}

-- taplo (TOML)
lsp.config["taplo"] = {
  cmd = { "taplo", "lsp", "stdio" },
  filetypes = { "toml" },
  root_markers = { "*.toml", ".git" },
}

lsp.enable({ "rust_analyzer", "terraformls", "yamlls", "taplo" })
