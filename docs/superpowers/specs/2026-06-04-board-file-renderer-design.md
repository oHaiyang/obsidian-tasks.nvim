# Board File Renderer Design

Date: 2026-06-04

## Context

`obsidian-tasks.nvim` currently supports named queries declared in Lua config through `setup({ queries = ..., default_query = ... })`. Those queries are collected by `query_registry.lua` and opened by `:ObsidianTasks [name]`. The plugin also already scans `tasks` fenced code blocks in vault markdown files, can run a block at cursor, and can show lightweight virtual-line previews.

The new direction is to match Obsidian Tasks more closely: task queries should live in vault markdown files as `tasks` code blocks, and the main Neovim board view should render those files in a read-only markdown view where each `tasks` block is replaced by its query results.

## Goals

- Remove Lua-configured named query boards from the primary workflow.
- Keep ad hoc query execution through Lua API and Neovim commands.
- Make `:ObsidianTasks [file]` open a vault markdown board file and render its `tasks` blocks.
- Preserve non-`tasks` markdown as read-only markdown content in the board buffer.
- Prevent direct edits to the board markdown source from the rendered panel.
- Keep task actions from rendered query results, with changes written back to the original task source files.

## Non-Goals

- Do not remove query presets. `presets`, `query_presets`, and `queryPresets` remain settings-level reusable query fragments.
- Do not replace the existing markdown source file with rendered content.
- Do not build a full markdown HTML renderer. The board buffer remains a Neovim markdown buffer that benefits from normal markdown highlighting, conceal, and user-installed renderers.
- Do not remove `:ObsidianTasksRunBlock`, previews, cache commands, completion, task mutation commands, global query/filter, or query file defaults.

## Public API And Commands

`setup()` no longer normalizes or uses `config.queries`, `config.default_query`, or `config.defaultQuery`. These options become unsupported for opening boards. `config.presets`, `config.query_presets`, and `config.queryPresets` continue to work.

`require("obsidian-tasks").run_query(query, opts)` remains the Lua API for an immediate query. `:ObsidianTasksQuery {query...}` remains the command form for immediate query text. These continue to use the existing single-query result buffer path.

`require("obsidian-tasks").open(opts)` and `:ObsidianTasks [file]` become the board-file entry point:

- With a file argument, render that markdown file.
- With no argument and the current buffer is a markdown file under `vault_path`, render the current file.
- With no argument outside a vault markdown file, show `vim.ui.select` listing vault markdown files that contain `tasks` blocks.

`require("obsidian-tasks").open_query(name, opts)` remains temporarily as a migration aid, but it should report a clear error that named Lua-config queries are no longer supported and users should move the query into a vault `tasks` code block.

`:ObsidianTasksRefreshQueries` is removed from the main workflow. Board file discovery can scan vault files on demand. Query-name completion for `:ObsidianTasks` is replaced by file completion.

## Board Render Buffer

A new `lua/obsidian-tasks/board.lua` module owns the rendered-file experience.

The renderer reads a markdown file from disk, scans fenced code blocks, and creates a separate board buffer named like `obsidian-tasks://board/<path-slug>`. The buffer uses `filetype=markdown`, is `readonly`, is `nomodifiable` except while the renderer updates it internally, and uses a non-file buftype so writes do not modify the source markdown.

Rendering rules:

- Normal markdown lines are copied into the board buffer as markdown text.
- Non-`tasks` fenced code blocks are preserved as markdown fenced code blocks.
- `tasks` fenced code blocks are hidden and replaced by a rendered task-results section in the same position.
- Query block metadata such as `# name:` is used as the section heading when present.
- Unnamed query blocks use a compact source label such as `Tasks query at Board.md#L12`.
- Query errors render at that block's position without stopping other blocks from rendering.
- `explain` output renders inside that block's result section when requested.
- Empty result sets render a small empty-state line for that block.

The board buffer stores per-buffer metadata:

- source markdown path
- rendered query sections and their original source ranges
- rendered task line to original task object mapping
- rendered query section line ranges for navigation and refresh

## Data Flow

Opening a board:

1. Resolve the source markdown file from command/API arguments, current buffer, or picker.
2. Read source lines from disk.
3. Use `query_block.lua` to identify `tasks` block ranges and query source text.
4. For each query block, compose the query with global query and query file defaults using the board source file as query-file context.
5. Parse and execute each valid query against cached or freshly scanned vault tasks.
6. Format task results with existing display/query/sort/grouping helpers.
7. Build the read-only markdown board buffer and install keymaps.

Refreshing a board reruns the same flow from disk, preserving the board buffer where possible.

## Module Boundaries

`query_block.lua` remains the source parser. It should expose enough block range data for the board renderer to splice markdown around each `tasks` block.

`board.lua` owns board-file rendering, buffer options, board-specific keymaps, line maps, refresh, file selection, and board-source navigation.

`panel.lua` keeps ad hoc query behavior and delegates `open()` / `:ObsidianTasks [file]` to `board.lua`.

`finder.lua` remains the single-query result path for `run_query`, `run_query_at_cursor`, and direct `find_tasks()` usage.

`display.lua` should expose reusable formatting helpers for query result sections without forcing the old result-buffer header, `obstasks` filetype, or editable buffer behavior.

`query_registry.lua` is removed from the main board-opening path. If retained internally during migration, it should not read `config.queries` or drive `:ObsidianTasks` query-name selection.

## Board Interaction

The rendered board buffer is not an editable markdown source buffer. Users edit the original markdown file separately.

Board keymaps:

- `q` closes the board buffer.
- `<C-r>` and `:ObsidianTasksRefresh` rerender the current board from disk.
- `gq` jumps from a rendered query section to the original `tasks` block in the source markdown file.
- `gd` and `gf` on a rendered task jump to the original task source line.
- `<space>`, status changes, postpone, and edit actions continue to operate on rendered task lines and write back to the original task source files.

After a task mutation succeeds, the board refreshes so the read-only rendered view stays consistent with source files.

## Error Handling

Missing `vault_path` reports a clear error and does not open an empty board.

Unreadable file arguments report the exact path and read error.

File arguments outside `vault_path` report that the board file must be inside the configured vault.

Markdown files with no `tasks` blocks still open as read-only markdown boards and include a small notice near the top that no task queries were found.

One invalid query block renders an error section at that block's location. Other query blocks in the same board still render.

Query placeholders such as `{{query.file.path}}` use the board source file as query-file context.

If a task source line changed, existing source-location safeguards remain in force and tell the user to refresh before mutating or jumping.

## Testing

Add a new headless smoke script for board rendering.

Coverage:

- `:ObsidianTasks {file}` renders markdown around multiple `tasks` blocks.
- No-argument `:ObsidianTasks` renders the current vault markdown file.
- The board buffer is read-only, nonmodifiable, and `filetype=markdown`.
- Non-`tasks` fenced blocks are preserved.
- A bad query block renders an error section while another block in the same file still renders.
- Task toggle from the board buffer writes back to the original task file and refreshes the board.
- Query file defaults and `{{query.file.*}}` placeholders use the board file path.
- `:ObsidianTasksQuery` continues to execute immediate queries.

Regression scripts should include relevant existing coverage for query file defaults, preview, task mutation, cache refresh, and explain. Older smoke expectations that depend on `setup({ queries = ..., default_query = ... })` should be updated or replaced.

## Migration Notes

Before:

```lua
require("obsidian-tasks").setup({
  vault_path = "/vault",
  default_query = "today",
  queries = {
    today = "not done\ndue today",
  },
})
```

After:

```lua
require("obsidian-tasks").setup({
  vault_path = "/vault",
})
```

`/vault/Tasks Board.md`:

````markdown
# Tasks Board

```tasks
# name: Today
not done
due today
```
````

Open the board with:

```vim
:ObsidianTasks Tasks\ Board.md
```
