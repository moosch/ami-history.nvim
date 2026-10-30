-- ami-history.session: per-project chat history as a branching tree of nodes,
-- persisted as JSON. Ported from ami's former Go daemon (internal/session).
--
-- Each message is a node linked to its parent; a session has a "head" at the tip of
-- the active branch. Appending adds children under the head, so pointing the head at
-- an earlier node and continuing creates a divergent branch without destroying the
-- old one. Summarization is non-destructive: a boundary node stores a summary and
-- its ancestors are marked collapsed; the originals stay on disk.
local M = {}

local function sanitize(id)
  id = vim.trim(id or "")
  if id == "" then
    id = "default"
  end
  return (id:gsub("[^%w%._-]+", "-"))
end

-- Stable, filesystem-safe id for a project root: basename + short path hash.
local function project_key(root)
  local sum = vim.fn.sha256(root or "")
  local base = (vim.fn.fnamemodify(root or "", ":t")):gsub("[^%w%._-]+", "-")
  if base == "" or base == "-" or base == "." then
    base = "project"
  end
  return base .. "-" .. sum:sub(1, 12)
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local data = fd:read("*a")
  fd:close()
  return data
end

--- Create a store. `base`: a directory to keep sessions out of your repos
--- (sessions live under base/<project-key>/sessions); "" keeps them in each
--- project's own .ami/sessions.
---@param base string
function M.new(base)
  local store = { base = base or "" }

  function store:dir(root)
    if self.base ~= "" then
      return self.base .. "/" .. project_key(root) .. "/sessions"
    end
    return root .. "/.ami/sessions"
  end

  function store:path(root, id)
    return self:dir(root) .. "/" .. sanitize(id) .. ".json"
  end

  -- Nodes root -> node_id, in order.
  local function path_to(sess, node_id)
    local rev = {}
    local id = node_id
    while id and id ~= "" do
      local n = sess.nodes[id]
      if not n then
        break
      end
      rev[#rev + 1] = n
      id = n.parent
    end
    local out = {}
    for i = #rev, 1, -1 do
      out[#out + 1] = rev[i]
    end
    return out
  end
  store.path_nodes = function(_, sess, node_id)
    return path_to(sess, node_id or sess.head)
  end

  local function new_node(sess, parent, role, content)
    sess.next_seq = (sess.next_seq or 0) + 1
    local n = {
      id = "n" .. sess.next_seq,
      parent = parent or "",
      role = role,
      content = content,
      time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    sess.nodes[n.id] = n
    return n
  end

  function store:load(root, id)
    local data = read_file(self:path(root, id))
    if not data then
      return { id = sanitize(id), nodes = {}, head = "", next_seq = 0 }
    end
    local ok, sess = pcall(vim.json.decode, data)
    if not ok or type(sess) ~= "table" then
      return { id = sanitize(id), nodes = {}, head = "", next_seq = 0 }
    end
    sess.id = sess.id or sanitize(id)
    if type(sess.nodes) ~= "table" then
      sess.nodes = {}
    end
    sess.next_seq = sess.next_seq or 0
    sess.head = sess.head or ""
    return sess
  end

  function store:save(root, sess)
    local dir = self:dir(root)
    vim.fn.mkdir(dir, "p")
    local p = self:path(root, sess.id)
    local fd = io.open(p .. ".tmp", "w")
    if not fd then
      return false
    end
    fd:write(vim.json.encode(sess))
    fd:close()
    os.rename(p .. ".tmp", p)
    return true
  end

  --- Append turns ({role, content}) as nodes under the head, advancing it.
  function store:append(root, id, turns)
    local sess = self:load(root, id)
    for _, t in ipairs(turns) do
      local n = new_node(sess, sess.head, t.role, t.content)
      sess.head = n.id
    end
    self:save(root, sess)
    return sess
  end

  --- Point the head at node_id so subsequent appends form a new branch.
  function store:branch(root, id, node_id)
    local sess = self:load(root, id)
    if not sess.nodes[node_id] then
      return nil, ("node %q not found"):format(node_id)
    end
    sess.head = node_id
    self:save(root, sess)
    return sess
  end

  --- Store `summary` on boundary_id and mark it + its ancestors collapsed.
  function store:apply_summary(root, id, boundary_id, summary)
    local sess = self:load(root, id)
    local boundary = sess.nodes[boundary_id]
    if not boundary then
      return nil, ("node %q not found"):format(boundary_id)
    end
    local nid = boundary_id
    while nid and nid ~= "" do
      local n = sess.nodes[nid]
      if not n then
        break
      end
      n.collapsed = true
      n.summary = nil -- only the boundary carries the summary
      nid = n.parent
    end
    boundary.collapsed = true
    boundary.summary = summary
    self:save(root, sess)
    return sess
  end

  return store
end

return M
