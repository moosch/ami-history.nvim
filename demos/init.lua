-- Minimal Neovim config for recording the ami-history (:AmiTree) demo with VHS.
--   nvim -u demos/init.lua <file>
--
-- To keep the demo deterministic and fast, it uses a throwaway history dir and
-- pre-seeds a short *branched* conversation on startup — so :AmiTree immediately
-- shows a real tree to navigate (no live model calls needed). The tree UI,
-- branch-switching, and transcript re-render are all genuine.
--
-- Needs ami core + ami-chat checked out next to this repo (../ami.nvim or
-- ../ai-harness; ../ami-chat.nvim), or set $AMI_CORE.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local parent = vim.fn.fnamemodify(root, ":h")
local function add(p)
  if p and vim.fn.isdirectory(p) == 1 then
    vim.opt.runtimepath:append(p)
    return true
  end
end

vim.opt.runtimepath:append(root) -- this extension (ami-history)
if not add(os.getenv("AMI_CORE")) then
  local _ = add(parent .. "/ami.nvim") or add(parent .. "/ai-harness")
end
add(parent .. "/ami-chat.nvim") -- the chat controller this records/feeds

vim.o.termguicolors = true
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.laststatus = 0
vim.o.swapfile = false

-- Fresh throwaway history dir each render.
local hist_dir = vim.fn.stdpath("cache") .. "/ami-tree-demo"
vim.fn.delete(hist_dir, "rf")

local endpoint = os.getenv("AMI_ENDPOINT") or "http://localhost:1234/v1"
require("ami").setup({
  model = { endpoint = endpoint, model = os.getenv("AMI_CHAT_MODEL") or "qwen3-coder" },
  history = { session_dir = hist_dir },
  -- Dock the chat panel on the LEFT so it doesn't overlap the tree's right split.
  chat = { ui = { position = "left", width = 0.42 } },
  extensions = { require("ami-chat"), require("ami-history") },
})

-- Pre-seed a branched conversation once the buffer is open.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local proj = require("ami.context").project_root(0)
    local store = require("ami-history.session").new(hist_dir)
    store:append(proj, "default", {
      { role = "user", content = "How should Get handle errors?" },
      { role = "assistant", content = "Return typed errors: a sentinel ErrNotFound, and wrap the rest with %w for context." },
    })
    store:append(proj, "default", {
      { role = "user", content = "And retries on transient DB failures?" },
      { role = "assistant", content = "Only for idempotent reads, with capped exponential backoff." },
    })
    -- Branch back to the first answer and take a different direction.
    store:branch(proj, "default", "n2")
    store:append(proj, "default", {
      { role = "user", content = "Actually — let's write the test first." },
      { role = "assistant", content = "Table-driven test for Get: found, not-found (ErrNotFound), and a db error." },
    })
    -- Let ami-history learn this session's project root (normally from chat events).
    require("ami.events").emit("chat_session", { session = "default", root = proj })
  end,
})
