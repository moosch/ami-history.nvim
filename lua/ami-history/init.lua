-- ami-history: conversation history for ami, as a standalone extension.
--
-- Provides the "history" capability: it supplies the prior-turn messages the chat
-- controller includes in each request, and records completed turns by listening to
-- the chat lifecycle events. History is a branching tree (see ami-history.session)
-- persisted to disk, with branch/switch/summarize via :AmiTree.
--
--   require("ami").setup({ extensions = { require("ami-chat"), require("ami-history") } })
--
-- Swap it for a fancier memory later by registering a different "history" provider.
local session = require("ami-history.session")
local tree = require("ami-history.tree")

local store = nil
local roots = {} -- session id -> project root (learned from chat events)

local function remember(session_id, root)
  if session_id and root and root ~= "" then
    roots[session_id] = root
  end
end

-- Active path -> LLM messages, collapsing a summarized prefix into one system
-- message (ported from the former daemon's pathMessages).
local function path_messages(st, sess)
  local msgs = {}
  for _, n in ipairs(st:path_nodes(sess)) do
    if n.collapsed then
      if n.summary and n.summary ~= "" then
        msgs[#msgs + 1] = { role = "system", content = "Summary of earlier conversation:\n" .. n.summary }
      end
    else
      msgs[#msgs + 1] = { role = n.role, content = n.content }
    end
  end
  return msgs
end

return {
  name = "history",

  config = {
    -- Where sessions are stored. nil = stdpath("data")/ami (out of your repos);
    -- "" = each project's own ./.ami/sessions.
    session_dir = nil,
    -- Which side :AmiTree docks on: "left" | "right". nil = auto (opposite the chat
    -- panel, so a floating chat never overlaps the tree).
    tree_side = nil,
    -- In-tree keys (each a string, a list of strings, or false to disable).
    -- `open` optionally maps :AmiTree globally (normal mode); nil = don't.
    keymaps = {
      switch = "<CR>",     -- switch the active branch to the node under the cursor
      summarize = "s",     -- summarize the path up to the node
      refresh = "r",       -- reload the tree
      close = "q",         -- close the tree window
      open = nil,          -- e.g. "<leader>at" to map :AmiTree globally
    },
  },

  commands = {
    AmiTree = {
      desc = "Open the conversation tree (branch/switch/summarize)",
      fn = function() tree.open(false) end,
    },
  },

  setup = function(api)
    local base = api.config.session_dir
    if base == nil then
      base = vim.fs.joinpath(vim.fn.stdpath("data"), "ami")
    end
    store = session.new(base)

    -- (root, session) for the tree viewer: the chat controller's current session,
    -- and the root we learned for it from chat events.
    local function current()
      local s = api.chat.session()
      return roots[s], s
    end
    tree.init(api, store, current)

    -- Record completed turns; learn each session's project root.
    api.on("chat_session", function(e) remember(e.session, e.root) end)
    api.on("chat_turn_post", function(e)
      remember(e.session, e.root)
      if e.ok and e.root then
        store:append(e.root, e.session, {
          { role = "user", content = e.user or "" },
          { role = "assistant", content = e.assistant or "" },
        })
      end
    end)

    -- Contribute chat slash-commands. /compact (alias /compress) summarizes the
    -- conversation so far into one summary, so future turns carry the summary
    -- instead of every prior message — shrinking the context the model receives.
    -- Reduction takes effect on the next turn (the transcript scrollback is left
    -- as-is as a human-readable log). Available only while ami-history is loaded.
    local function compact(ctx)
      -- /compact            fold the whole conversation into a summary
      -- /compact keep=2     keep the last 2 turns verbatim, summarize the rest
      local keep = tonumber((ctx.args or ""):match("keep%s*=?%s*(%d+)")) or 0
      local note = keep > 0 and (" (keeping the last " .. keep .. " turn(s) verbatim)") or ""
      ctx.append("\n\n_Compacting the conversation…" .. note .. "_\n")
      tree.summarize_path({ keep = keep }, function(ok, msg)
        if ok then
          ctx.append("\n_✓ " .. msg .. " — future turns will use it instead of the full history._\n")
        else
          ctx.append("\n_Compact: " .. msg .. "_\n")
        end
      end)
    end
    api.on("chat.commands", function()
      return {
        compact = {
          desc = "Summarize earlier turns to shrink future context (/compact [keep=N])",
          fn = compact,
        },
        compress = { desc = "Alias for /compact", fn = compact },
      }
    end)

    -- Supply prior-turn context for the next request.
    api.provide("history", {
      messages = function(session_id)
        local root = roots[session_id]
        if not root then
          return {}
        end
        return path_messages(store, store:load(root, session_id))
      end,
    })

    -- Optional global mapping for opening the tree.
    local open = (api.config.keymaps or {}).open
    if open then
      vim.keymap.set("n", open, function() tree.open(false) end, { desc = "ami: open the conversation tree" })
    end

    api.health(function(report)
      if base == "" then
        report.info("sessions: per-project ./.ami/sessions")
      else
        report.info("session dir: " .. base)
        vim.fn.mkdir(base, "p")
        if vim.fn.isdirectory(base) == 1 and vim.fn.filewritable(base) == 2 then
          report.ok("session dir writable")
        else
          report.warn("session dir not writable: " .. base)
        end
      end
    end)
  end,
}
