# ami-history — the branching conversation tree (:AmiTree)  [EXAMPLE]
#
# Demonstrates ami-history.nvim (https://github.com/moosch/ami-history.nvim) with ami
# core + ami-chat.nvim, loaded by demos/init.lua. The init pre-seeds a short branched
# conversation so the tree is immediately navigable (no live model calls needed).
#
# Record with:  vhs demos/tree.tape   (needs `vhs`; ami core + ami-chat.nvim checked
# out next to this repo, or set $AMI_CORE). No LM Studio required for this one.

Output demos/tree.gif

Require nvim
Set Shell "bash"
Set FontSize 18
Set Width 1280
Set Height 760
Set Padding 20
Set Framerate 24
Set TypingSpeed 55ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden): write a source file and open it (init pre-seeds history) ---
# \042 is printf's octal for a double quote; %% prints a literal %.
Hide
Type "printf 'package store\n\nimport (\n\t\042context\042\n\t\042database/sql\042\n\t\042errors\042\n\t\042fmt\042\n)\n\nvar ErrNotFound = errors.New(\042store: user not found\042)\n\n// Get loads one user by id, returning ErrNotFound when the row is absent.\nfunc Get(ctx context.Context, db *sql.DB, id string) (*User, error) {\n\trow := db.QueryRowContext(ctx, \042SELECT id, name, email FROM users WHERE id = $1\042, id)\n\tvar u User\n\tif err := row.Scan(&u.ID, &u.Name, &u.Email); err != nil {\n\t\treturn nil, fmt.Errorf(\042store.Get(%%q): %%w\042, id, err)\n\t}\n\treturn &u, nil\n}\n' > /tmp/ami_tree_demo.go"
Enter
Type "nvim -u demos/init.lua /tmp/ami_tree_demo.go"
Enter
Sleep 2s
Show
Sleep 1500ms

# --- open the tree: a pre-seeded conversation that forks at n2 ---
Type ":AmiTree"
Enter
Sleep 3s

# --- focus the tree (docked left, opposite the chat), jump to n4, switch to it ---
Type ":wincmd h"
Enter
Sleep 1s
Type "4G"
Sleep 1500ms
Enter
Sleep 1500ms

# --- the transcript re-materializes for the switched branch; head (*) moves ---
Sleep 3s
