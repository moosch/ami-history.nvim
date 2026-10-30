# ami-history.nvim

Conversation history for [ami](https://github.com/moosch/ami.nvim) — a branching
tree with persistence, branch/switch/summarize, and `:AmiTree`.

It provides ami's `history` capability: it supplies the prior-turn messages the chat
controller includes in each request (so chat is multi-turn), and records completed
turns by listening to the chat lifecycle events. History is a tree — point the head
at any earlier node and keep talking to create a divergent branch without losing the
old one; summarize a long prefix to shrink future context non-destructively.

Because it's just a provider, you can swap it for a fancier memory later (semantic
search, summarizing memory, …) by registering a different `history` provider — no
change to ami-chat.

## Requirements

- [ami.nvim](https://github.com/moosch/ami.nvim) — the runtime.
- [ami-chat.nvim](https://github.com/moosch/ami-chat.nvim) — the chat controller
  whose events this records and whose requests it feeds. **Required**: without chat
  there's nothing to remember.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim), install it alongside ami and
ami-chat, and register all three:

```lua
{
  "moosch/ami.nvim",
  dependencies = {
    "moosch/ami-chat.nvim",
    "moosch/ami-history.nvim",
  },
  config = function()
    require("ami").setup({
      extensions = { require("ami-chat"), require("ami-history") },
      -- optional: history = { session_dir = nil },  -- nil = stdpath("data")/ami
    })
  end,
}
```

Without this extension, ami-chat still works but keeps only an in-memory history for
the current session (no persistence, no branching).

## Commands

| Command | What it does |
| --- | --- |
| `:AmiTree` | Open the tree — `<CR>` switch branch, `s` summarize up to a node, `r` refresh, `q` close |

In the tree, `*` marks the head, `|` a node on the active path, `~` a collapsed
(summarized) node; `A`/`U` is assistant/user.

## Configuration

Config lives under `history` in ami's `setup()`:

| Key | Default | Meaning |
| --- | --- | --- |
| `session_dir` | `nil` | where sessions are stored. `nil` = `stdpath("data")/ami/<project>/sessions/` (out of your repos); `""` = each project's own `./.ami/sessions/` (add `.ami/` to your global gitignore) |

## How it works

- Records by listening to `chat_turn_post` (which carries the full user + assistant
  text and the project root).
- Supplies prior turns via `messages(session)` — the active root→head path, with any
  summarized prefix collapsed into a single system message.
- Sessions are keyed per project (basename + a short path hash) so same-named
  projects in different locations don't collide.

> **Per-instance:** history is local to each Neovim instance (there's no shared
> daemon any more). Two instances editing the same project write to the same files;
> last write wins. A future provider could add locking or live reload.

## License

[MIT](LICENSE)
