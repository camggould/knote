# knote

[![CI](https://github.com/camggould/knote/actions/workflows/ci.yml/badge.svg)](https://github.com/camggould/knote/actions/workflows/ci.yml)

A native macOS quick-notes launcher. Hit a global hotkey, and a Spotlight-style
panel appears anywhere. Type `/n …` to capture a note, or type a natural-language
query to find past ones — results are ranked by meaning, keyboard-navigable, and
deletable with a confirm. Everything is **local and private**: SQLite datastore,
an in-memory vector index, and an on-device encoder. No network, no accounts.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full design.

## Status

Menu-bar app, end-to-end. Working toward **v0.2.0-beta**.

Core:
- ✅ Menu-bar accessory app (no Dock icon), runs in the background, ~48 MB idle.
- ✅ Global hotkey **⌥Space** (Carbon — no Accessibility permission needed),
  rebindable in **Settings…** (menu-bar icon → Settings, or ⌘,).
- ✅ Floating panel over any Space / fullscreen app; click-away / Esc to dismiss.
- ✅ `/n` capture → SQLite (GRDB) with an FTS5 mirror.
- ✅ Hybrid ranking: semantic (vectors) + lexical (BM25) fused with RRF + recency.
- ✅ Arrow-to-select, backspace-to-delete with inline confirm.

v0.2.0-beta features:
- ✅ **Tags** — `#tag` in a note is parsed, shown as chips, and searchable (`#work`).
- ✅ **Spaces** — `/s` create, `/ns <space>` capture-into, `/ss <space>` scoped
  search, with **Tab** autocomplete.
- ✅ **Linked notes** — `⌘L` links a note to an answer (question ↔ answer);
  linked notes show an indicator.
- ✅ **MCP server** — `knote-mcp` exposes read-only search to LLM clients (below).
- ✅ **Auto-update** — Check for Updates pulls the newest GitHub Release.

Encoder:
- ✅ On-device encoder via Apple **NLEmbedding**, loaded lazily to keep idle light.
- 🚧 **Core ML BGE** (better retrieval): app-side code auto-activates when the
  model file exists; producing it needs a one-time conversion under Python
  3.11/3.12 (see below). Until then, NLEmbedding is used.

## Install

Download the latest **`knote-<version>-macos-arm64.dmg`** from the
[**Releases**](https://github.com/camggould/knote/releases) page, open it, and
drag **Knote.app** onto the **Applications** folder shown in the window. (Apple
Silicon; ad-hoc signed — on first launch, right-click the app → **Open** to
approve.) Then skip to step 3. (A `.zip` is also attached — it's what the in-app
updater uses.)

To build it yourself instead (requires **Xcode 16+** on macOS 14+):

**1. Build the app bundle**

```bash
git clone https://github.com/camggould/knote && cd knote
./scripts/make_app.sh            # → build/Knote.app
```

**2. Install it to /Applications**

Install to a stable location *before* enabling Launch at Login — the login item
points at wherever the app lives, so running it from the repo's `build/` folder
would break the next time you rebuild or clean.

```bash
cp -R build/Knote.app /Applications/
open /Applications/Knote.app
```

A **note icon appears in the menu bar** (no Dock icon — it runs in the
background). There's no window until you summon it.

**3. First use**

- Press **⌥Space** from any app to open the panel.
- Type to search; type `/n <text>` then `↩` to capture a note.
- Rebind the shortcut anytime: menu-bar icon → **Settings…** (⌘,) → click the
  field → press your combination (must include ⌘, ⌥, or ⌃).

**4. Launch at login**

Menu-bar icon → **Launch at Login**. knote now starts with every login. Confirm
under **System Settings → General → Login Items** if you like.

> **Note on signing.** `make_app.sh` ad-hoc-signs the app, which is fine for
> personal use. If macOS Gatekeeper blocks first launch, right-click the app →
> **Open** once to approve it. A Developer ID signature (for notarized releases)
> is future work.

### Updating

After pulling new changes, rebuild and reinstall:

```bash
./scripts/make_app.sh
pkill -f "Knote.app/Contents/MacOS/knote"   # quit the running copy
cp -R build/Knote.app /Applications/
open /Applications/Knote.app
```

## Using knote

Press **⌥Space** anywhere to summon the panel. Start typing. Click away or press
**Esc** to dismiss it. Everything below is keyboard-driven.

### Capture a note

Type `/n` then your note, and press **↩** to save:

```
/n call the dentist tomorrow #health
```

Any `#hashtags` in the body become **tags** automatically (see below).

### Find notes

Just type — no prefix. knote ranks by **meaning + keywords** (semantic + BM25),
so a query like `teeth appointment` surfaces that dentist note even without exact
word matches. Recent notes break ties.

- **↓ / ↑** move the selection through the results.
- **↩** opens the selected note — which **copies its text to the clipboard** (handy
  for pasting a snippet elsewhere) and closes the panel.
- Empty query shows your most recent notes.

### Tags — `#tag`

Tags come from `#hashtags` in a note's body and show as chips on each result.
Search by tag by typing it:

- `#work` — only notes tagged `work`.
- `#work budget` — tagged `work` **and** matching “budget”.

### Spaces — organize & scope

Spaces are optional buckets for notes.

| Type | Does |
|------|------|
| `/s Reading` | Create a space called **Reading** |
| `/ns Reading <note>` | Capture a note **into** Reading |
| `/ss Reading <query>` | Search **only within** Reading |

While typing a space name after `/ns ` or `/ss `, press **⇥ Tab** to autocomplete
it from your existing spaces.

### Link notes — question ↔ answer

Select a result (**↓**), then press **⌘L** to link it to another note. Type to
find the target, press **↩**, and it's linked as the **answer** to the note you
started from. Notes with links show a 🔗 indicator. (Great for pairing a question
note with the note that resolves it.)

### Delete a note

Arrow (**↓**) into the results to select a note, then press **⌫** — knote asks to
confirm (**↩** to delete, **Esc** to cancel). While you're still typing a query,
**⌫** just edits your text; it only deletes once a note is selected. **⌘⌫** deletes
the selected note from anywhere.

### Keyboard reference

| Key | Action |
|-----|--------|
| `⌥Space` | Show / hide the panel (from anywhere; rebindable in Settings) |
| type | Search by meaning + keywords |
| `/n <text>` | Compose a note (`↩` saves) |
| `/s <name>` | Create a space |
| `/ns <space> <text>` | Capture into a space |
| `/ss <space> <query>` | Search within a space |
| `#tag` | Filter to a tag |
| `⇥` | Autocomplete a space name |
| `↓` / `↑` | Move selection through results |
| `↩` | Open selected result (copies to clipboard) |
| `⌘L` | Link the selected note to another (as its answer) |
| `⌫` | With a result selected: delete (asks to confirm) |
| `⌘⌫` | Delete selected result from anywhere |
| `⌘C` / `⌘V` / `⌘X` / `⌘A` | Standard editing in the field |
| `Esc` | Cancel confirm → exit selection → clear → hide |

Menu-bar icon → **Settings…** (⌘,) to rebind the shortcut, **Launch at Login**,
and **Check for Updates…**.

## Give an LLM access to your notes (MCP)

`knote-mcp` is a local [MCP](https://modelcontextprotocol.io) stdio server that
exposes **read-only** tools — `search_notes`, `get_note`, `list_spaces`,
`list_tags` — over the same local database. An MCP client (Claude Desktop,
Claude Code, etc.) spawns it on demand; nothing listens on a network.

It's bundled at `Contents/Resources/knote-mcp`. Point your client at it:

```json
{
  "mcpServers": {
    "knote": {
      "command": "/Applications/Knote.app/Contents/Resources/knote-mcp"
    }
  }
}
```

(During development the binary is at `.build/debug/knote-mcp`. Set `KNOTE_DB` to
point at a different database.) Sanity-check it with `./scripts/test-mcp.sh`.

## Develop

```bash
swift run knote                  # run from the terminal (no bundle)
swift test                       # KnoteCore unit tests
```

CI (`.github/workflows/ci.yml`) builds and tests every push to `main` and every
PR on a macOS runner.

## Releasing

Push a `vMAJOR.MINOR.PATCH` tag and CI builds the app, zips it, and publishes a
GitHub Release with the artifact + SHA-256 (`.github/workflows/release.yml`):

```bash
git tag v0.1.0
git push origin v0.1.0
```

The tag version is stamped into the app bundle (`CFBundleShortVersionString`).

## Upgrade to Core ML BGE embeddings (optional, better search)

Use **Python 3.11 or 3.12** (not 3.13 — see the note in `scripts/convert_model.py`;
the trace-friendly `transformers`/`tokenizers` pin has no 3.13 wheels):

```bash
/opt/homebrew/bin/python3.12 -m venv .venv && source .venv/bin/activate
pip install torch "transformers==4.40.2" coremltools
python scripts/convert_model.py     # writes the model to Application Support
```

Restart knote; it detects the model and switches automatically, re-embedding
existing notes in the background. Heavy deps (torch/coremltools) are only needed
for this one-time conversion, not to run the app.

## Where data lives

`~/Library/Application Support/knote/`
  - `knote.sqlite` — notes + embeddings + FTS index
  - `model/` — Core ML model + `vocab.txt` (only if you ran the conversion)

Nothing leaves your machine.

## Project layout

```
Sources/
  knote/           App shell: hotkey, panel, keyboard state machine, menu bar
  KnoteCore/       Note model, GRDB store + FTS, indexer, search + RRF ranking
  KnoteEmbeddings/ Encoder protocol; NLEmbedding + Core ML BGE + WordPiece
  KnoteVector/     VectorIndex protocol; brute-force in-memory cosine (Accelerate)
Icon/
  knote-source.png Source artwork
  AppIcon.icns     Generated app icon (bundled by make_app.sh)
scripts/
  make_app.sh      Assemble the .app bundle
  make_dmg.sh      Build the drag-to-Applications .dmg
  make_icon.py     Regenerate AppIcon.icns from Icon/knote-source.png
  snapshots.sh     Render UI states to PNGs (offscreen)
  test-mcp.sh      Smoke-test the MCP helper
  convert_model.py BGE → Core ML conversion
```

To change the app icon, replace `Icon/knote-source.png` (a square PNG), run
`python3 scripts/make_icon.py`, then rebuild with `./scripts/make_app.sh`.
