# Demo

`tree.tape` is a [VHS](https://github.com/charmbracelet/vhs) script — the source for
`tree.gif` shown in the main README. GitHub doesn't render `.tape`; render it to a
`.gif` and commit the `.gif`.

Unlike the other ami demos, this one needs **no LM Studio**: `demos/init.lua`
pre-seeds a short *branched* conversation into a throwaway history dir on startup, so
`:AmiTree` immediately shows a real tree to navigate. The tree UI, branch-switching,
and transcript re-render are genuine; only the seed data is canned.

## Render

```sh
# from this repo's root, with ami core AND ami-chat.nvim checked out as siblings:
vhs demos/tree.tape

git add demos/tree.gif && git commit -m "docs: update demo gif"
```

`demos/init.lua` loads **ami core** (`../ami.nvim` or `../ai-harness`, or `$AMI_CORE`),
**ami-chat.nvim** (`../ami-chat.nvim`), and this extension; it docks the chat panel on
the left so it doesn't overlap the tree's right-hand split. Requires `vhs`
(`brew install vhs`).
