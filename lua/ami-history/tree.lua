-- ami-history.tree: the :AmiTree viewer. Renders the branching history as an
-- indented tree in a right-hand split and lets you switch branches or summarize a
-- prefix — operating on the local session store (no daemon). Switching/summarizing
-- re-render the chat transcript (via the "chat" capability) to match the active path.
local M = {
  buf = nil,
  win = nil,
  data = nil,
  node_by_id = {},
  line_to_id = {},
}

local A, store, get_current = nil, nil, nil

local SUMMARIZER = "You summarize a pair-programming conversation concisely, preserving decisions made, constraints, and open questions. Output a tight prose summary, no preamble."

--- @param api table ami extension API
--- @param st table the session store
--- @param current fun():string,string returns (root, session) for the active chat
function M.init(api, st, current)
  A, store, get_current = api, st, current
end

local function load_active()
  local root, session = get_current()
  if not root then
    return nil
  end
  local sess = store:load(root, session)
  local path_nodes = store:path_nodes(sess)
  local path_ids = {}
  for _, n in ipairs(path_nodes) do
    path_ids[#path_ids + 1] = n.id
  end
  local nodes = {}
  for _, n in pairs(sess.nodes) do
    nodes[#nodes + 1] = n
  end
  return { head = sess.head, nodes = nodes, path = path_ids, path_nodes = path_nodes }, root, session
end

local function render_transcript(path_nodes)
  local chat = A.resolve("chat")
  if chat and chat.render_nodes then
    chat.render_nodes(path_nodes)
  end
end

local function build_lines(data)
  local by_parent, by_id = {}, {}
  for _, n in ipairs(data.nodes or {}) do
    by_id[n.id] = n
    local p = n.parent or ""
    by_parent[p] = by_parent[p] or {}
    table.insert(by_parent[p], n)
  end
  for _, kids in pairs(by_parent) do
    table.sort(kids, function(a, b)
      return (tonumber((a.id:gsub("%D", ""))) or 0) < (tonumber((b.id:gsub("%D", ""))) or 0)
    end)
  end
  local path_set = {}
  for _, id in ipairs(data.path or {}) do
    path_set[id] = true
  end

  local lines, map = {}, {}
  local function walk(parent, depth)
    for _, n in ipairs(by_parent[parent] or {}) do
      local head = (n.id == data.head) and "*" or (path_set[n.id] and "|" or " ")
      local col = n.collapsed and "~" or " "
      local role = (n.role == "assistant") and "A" or "U"
      local text = (n.content or ""):gsub("%s+", " ")
      if #text > 48 then
        text = text:sub(1, 48) .. "…"
      end
      lines[#lines + 1] = string.format("%s%s %s%s %s: %s", head, col, string.rep("  ", depth), n.id, role, text)
      map[#lines] = n.id
      walk(n.id, depth + 1)
    end
  end
  walk("", 0)
  if #lines == 0 then
    lines = { "(empty session — ask something first)" }
  end
  return lines, map, by_id
end

local function ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return
  end
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden = "hide"
  vim.bo[M.buf].filetype = "ami-tree"
  vim.api.nvim_buf_set_name(M.buf, "ami://tree")
  local opts = { buffer = M.buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", M.switch, opts)
  vim.keymap.set("n", "s", M.summarize, opts)
  vim.keymap.set("n", "r", function() M.open() end, opts)
  vim.keymap.set("n", "q", M.close, opts)
end

-- Which side to dock the tree on. Default: the opposite side from the chat panel,
-- so a floating chat (which draws on top of splits) never overlaps the tree.
-- Override with history.tree_side = "left"|"right".
local function tree_side()
  local side = A and A.config and A.config.tree_side
  if side == "left" or side == "right" then
    return side
  end
  local pos = ((require("ami.config").options.chat or {}).ui or {}).position or "right"
  return (pos == "left") and "right" or "left"
end

local function show_win()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  vim.cmd(tree_side() == "left" and "topleft vsplit" or "botright vsplit")
  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)
  vim.api.nvim_win_set_width(M.win, math.max(48, math.floor(vim.o.columns * 0.35)))
  vim.wo[M.win].number = false
  vim.wo[M.win].relativenumber = false
  vim.wo[M.win].winbar = "tree  <CR> switch · s summarize · r refresh · q close"
  vim.api.nvim_set_current_win(cur)
end

local function render()
  ensure_buf()
  local lines, map, by_id = build_lines(M.data)
  M.line_to_id, M.node_by_id = map, by_id
  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.bo[M.buf].modifiable = false
end

--- Open/refresh the tree viewer.
function M.open(sync_transcript)
  local data = load_active()
  if not data then
    vim.notify("ami: no conversation yet in this project/session", vim.log.levels.INFO)
    return
  end
  M.data = data
  render()
  show_win()
  if sync_transcript then
    render_transcript(data.path_nodes)
  end
end

function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
end

local function node_under_cursor()
  if not (M.win and vim.api.nvim_win_is_valid(M.win)) then
    return nil
  end
  return M.line_to_id[vim.api.nvim_win_get_cursor(M.win)[1]]
end

--- Switch the active branch to the node under the cursor.
function M.switch()
  local id = node_under_cursor()
  if not id then
    return
  end
  local root, session = get_current()
  if not root then
    return
  end
  local sess, err = store:branch(root, session, id)
  if not sess then
    vim.notify("ami: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  render_transcript(store:path_nodes(sess))
  M.open(false)
  vim.notify("ami: switched to branch at " .. id, vim.log.levels.INFO)
end

--- Summarize the path up to the node under the cursor (shrinks future context).
function M.summarize()
  local id = node_under_cursor()
  if not id then
    return
  end
  local root, session = get_current()
  if not root then
    return
  end
  local sess = store:load(root, session)
  local nodes = store:path_nodes(sess, id)
  local convo = {}
  for _, n in ipairs(nodes) do
    local content = (n.collapsed and n.summary and n.summary ~= "") and n.summary or n.content
    convo[#convo + 1] = ("%s: %s"):format(n.role, content)
  end

  local eff = A.models.effective("chat")
  vim.notify("ami: summarizing up to " .. id .. "…", vim.log.levels.INFO)
  local summary = {}
  A.client.stream_chat(eff.endpoint, {
    model = eff.model,
    messages = {
      { role = "system", content = SUMMARIZER },
      { role = "user", content = "Summarize the conversation so far:\n\n" .. table.concat(convo, "\n\n") },
    },
  }, {
    on_token = function(c) summary[#summary + 1] = c end,
    on_done = function()
      local text = vim.trim(table.concat(summary))
      local ok, err = store:apply_summary(root, session, id, text)
      if not ok then
        vim.notify("ami: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      M.open(true)
      vim.notify("ami: summarized up to " .. id, vim.log.levels.INFO)
    end,
    on_error = function(e) vim.notify("ami: summarize failed — " .. tostring(e), vim.log.levels.ERROR) end,
  })
end

return M
