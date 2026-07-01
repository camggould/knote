# knote

[![CI](https://github.com/camggould/knote/actions/workflows/ci.yml/badge.svg)](https://github.com/camggould/knote/actions/workflows/ci.yml)

A native macOS quick-notes launcher. Hit a global hotkey, and a Spotlight-style
panel appears anywhere. Type `/n …` to capture a note, or type a natural-language
query to find past ones — results are ranked by meaning, keyboard-navigable, and
deletable with a confirm. Everything is **local and private**: SQLite datastore,
an in-memory vector index, and an on-device encoder. No network, no accounts.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full design.

## Status

Working v1 skeleton, end-to-end:

- ✅ Menu-bar accessory app (no Dock icon), runs in the background, ~48 MB idle.
- ✅ Global hotkey **⌥Space** (Carbon — no Accessibility permission needed),
  rebindable in **Settings…** (menu-bar icon → Settings, or ⌘,).
- ✅ Floating panel over any Space / fullscreen app; click-away / Esc to dismiss.
- ✅ `/n` capture → SQLite (GRDB) with an FTS5 mirror.
- ✅ Hybrid ranking: semantic (vectors) + lexical (BM25) fused with RRF + recency.
- ✅ Arrow-to-select, backspace-to-delete with inline confirm (§8 state machine).
- ✅ On-device encoder via Apple **NLEmbedding**, loaded lazily to keep idle light.
- 🚧 **Core ML BGE** encoder (better retrieval): app-side code is in place and
  auto-activates when the model file exists. Producing it needs a one-time
  conversion under Python 3.11/3.12 (see below) — not 3.13. Until then,
  NLEmbedding is used.
- 🚧 Open-a-result currently copies the note to the clipboard; in-place edit is
  next.

## Install

Grab the latest `knote-<version>-macos-arm64.zip` from the
[**Releases**](https://github.com/camggould/knote/releases) page, unzip, and
drag `Knote.app` into `/Applications`. (Apple Silicon; ad-hoc signed — on first
launch, right-click → **Open** to approve.) Then skip to step 3.

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

## Keyboard

| Key            | Action                                                        |
|----------------|---------------------------------------------------------------|
| `⌥Space`       | Show / hide the panel (from anywhere)                         |
| type           | Search notes by meaning + keywords                            |
| `/n <text>`    | Compose a note; `↩` saves                                     |
| `↓` / `↑`      | Move selection into / through results                        |
| `↩`            | Open selected result (copies to clipboard)                   |
| `⌫`            | With a result selected: delete (asks to confirm)             |
| `⌘⌫`           | Delete selected result from anywhere                         |
| `Esc`          | Cancel confirm → exit selection → clear → hide               |

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
  make_icon.py     Regenerate AppIcon.icns from Icon/knote-source.png
  convert_model.py BGE → Core ML conversion
```

To change the app icon, replace `Icon/knote-source.png` (a square PNG), run
`python3 scripts/make_icon.py`, then rebuild with `./scripts/make_app.sh`.
