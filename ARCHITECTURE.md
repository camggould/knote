# knote — Architecture

A native macOS quick-notes launcher. A global hotkey summons a Spotlight-style
floating panel. Type `/n …` to capture a note, or type a natural-language query
to find past notes. Results are ranked, keyboard-navigable, and deletable
(with confirmation). Everything runs **locally**: SQLite datastore, a local
vector index, and an on-device text encoder. No network, no accounts.

---

## 1. Design goals & non-goals

**Goals**
- Feels like Spotlight/Raycast: appears instantly (<100 ms), over any Space or
  fullscreen app, no dock icon.
- Fully local & private. No data leaves the machine. Minimal OS permissions.
- Capture in one keystroke; find by meaning, not just keywords.
- Keyboard-only: type, arrow to select, delete with confirm, all without a mouse.

**Non-goals (v1)**
- Sync / multi-device, rich text / attachments, tags, sharing, encryption at
  rest. All deferred to *Future work* (§10). The design keeps seams for them.

---

## 2. High-level shape

```
┌──────────────────────────────────────────────────────────────┐
│  KnoteApp  (menu-bar accessory, LSUIElement)                   │
│  ├─ GlobalHotkey ─────────┐                                    │
│  │                        ▼                                    │
│  ├─ PanelController  →  NSPanel (borderless, floating)         │
│  │                        └─ NSHostingView → KnoteUI (SwiftUI) │
│  │                                              │              │
│  └─ AppState (ObservableObject) ◄───────────────┘             │
│         │                                                      │
│         ▼                                                      │
│   KnoteCore                                                    │
│   ├─ CommandParser   ("/n …" vs query)                         │
│   ├─ NoteStore       (GRDB / SQLite: notes + FTS5)             │
│   ├─ Indexer         (embed on write, keep index in sync)      │
│   └─ SearchService   (candidate gen + Ranker)                  │
│         │                    │                                 │
│         ▼                    ▼                                 │
│   KnoteEmbeddings       KnoteVector                            │
│   Encoder protocol      VectorIndex protocol                  │
│   └─ CoreMLEncoder      └─ InMemoryVectorIndex                 │
│      (BGE + tokenizer)                                         │
└──────────────────────────────────────────────────────────────┘
```

Module boundaries (each a folder/SPM target so they stay decoupled and testable):

| Module            | Responsibility                                             | Key deps        |
|-------------------|------------------------------------------------------------|-----------------|
| `KnoteApp`        | Entry point, menu bar, hotkey, panel lifecycle             | AppKit          |
| `KnoteUI`         | SwiftUI views + keyboard state machine                     | SwiftUI         |
| `KnoteCore`       | Domain model, store, indexer, search, ranking              | GRDB            |
| `KnoteEmbeddings` | `Encoder` protocol + implementations                       | CoreML, swift-transformers |
| `KnoteVector`     | `VectorIndex` protocol + implementations                   | Accelerate      |

The `Encoder` and `VectorIndex` protocols are the two seams that let us upgrade
the ML stack (§7, §6) without touching the app.

---

## 3. App lifecycle, hotkey & panel

**Accessory app.** `LSUIElement = true` → no dock icon, lives in the menu bar
(`NSStatusItem`) like a launcher. Menu bar item offers Preferences / Quit and
shows the current hotkey.

**Global hotkey.** Use Carbon `RegisterEventHotKey` (via a thin Swift wrapper).
Rationale: it is the one global-hotkey mechanism that works **without** the
Accessibility permission (`CGEvent` taps and `NSEvent.addGlobalMonitor` both
require it). Fewer permission prompts = more Spotlight-like. Default binding:
`⌥Space` (configurable in Preferences).

**The panel.** A borderless `NSPanel`:
- `styleMask = [.borderless, .nonactivatingPanel]`, but `canBecomeKey = true`
  so the text field can receive input.
- `level = .floating` (or `.modalPanel`); `collectionBehavior` includes
  `.canJoinAllSpaces` + `.fullScreenAuxiliary` so it appears over any Space and
  over fullscreen apps.
- Centered on the screen with the active mouse/focus; fixed width (~640pt),
  height grows with results.
- Content is a single `NSHostingView` wrapping the SwiftUI root.
- **Dismiss** on `Esc` (see §8 state machine) or on `resignKey` (click-away).
- Toggle behavior: hotkey shows+focuses if hidden, hides if visible.

Target: show/focus in <100 ms → keep the panel allocated and just
order-front/order-out rather than recreating it.

---

## 4. Data model & store

SQLite via **GRDB.swift** (mature, safe, migrations, FTS5 support). DB lives at
`~/Library/Application Support/knote/knote.sqlite`.

```sql
-- Core note record
CREATE TABLE note (
  id          TEXT PRIMARY KEY,     -- UUID string
  body        TEXT NOT NULL,        -- full note text (source of truth)
  title       TEXT NOT NULL,        -- derived: first non-empty line, trimmed
  created_at  REAL NOT NULL,        -- unix epoch seconds
  updated_at  REAL NOT NULL
);

-- Embeddings kept separate so model/dim changes are a clean re-index,
-- not a schema migration of `note`.
CREATE TABLE embedding (
  note_id  TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
  model    TEXT NOT NULL,           -- encoder id + version, e.g. "bge-small-en.v1"
  dim      INTEGER NOT NULL,
  vector   BLOB NOT NULL,           -- packed little-endian float32[dim]
  PRIMARY KEY (note_id, model)
);

-- Lexical search (BM25). Contentless external-content FTS mirrored from `note`.
CREATE VIRTUAL TABLE note_fts USING fts5(
  title, body, content='note', content_rowid='rowid'
);
-- triggers keep note_fts in sync with note on insert/update/delete
```

`Note` (Swift value type) is the domain model. `NoteStore` wraps a GRDB
`DatabaseQueue` and exposes: `create`, `update`, `delete`, `fetch(id)`,
`allForIndexLoad()`, plus the FTS query used by search. All writes go through
the store; the store emits change events the `Indexer` observes.

---

## 5. Indexing pipeline

On **create/update**:
1. `NoteStore` persists the note (and FTS row via triggers).
2. `Indexer` (background queue) asks `Encoder` for the note's vector,
   writes it to `embedding`, and upserts it into the in-memory `VectorIndex`.

On **delete**: `note` row removed → `ON DELETE CASCADE` drops the embedding and
triggers drop the FTS row; `Indexer` removes the vector from the index.

On **launch**: load all `(note_id, vector)` for the active model into the
`InMemoryVectorIndex` (a few MB; §6). If a note has no embedding for the active
model (e.g. after a model upgrade), it is queued for background (re)embedding.

Embedding is async and never blocks the UI. A note is searchable lexically
(FTS) the instant it is saved, and semantically as soon as its vector lands
(typically <10 ms later).

---

## 6. Vector index

**v1: brute-force in-memory cosine similarity.** For a personal note corpus
this is the right call, not a compromise:
- 100k notes × 384-dim float32 ≈ 150 MB resident; a full scan with
  `Accelerate`/`vDSP` (or `simd`) is a few milliseconds. Real corpora are
  usually far smaller.
- Zero external dependencies, zero index-build/rebuild, trivially correct
  (exact nearest neighbors, no recall loss), survives restarts by reloading
  from `embedding`.

Vectors are L2-normalized on store, so cosine similarity is a dot product.

```
protocol VectorIndex {
  func upsert(id: NoteID, vector: [Float])
  func remove(id: NoteID)
  func search(_ query: [Float], k: Int) -> [(id: NoteID, score: Float)]  // score ∈ [-1,1]
}
```

**Upgrade path (behind the same protocol):** when a corpus outgrows brute force,
swap in `sqlite-vec` (keeps vectors in the same SQLite file, does KNN in SQL) or
an HNSW index. No caller changes.

---

## 7. Encoder (local text embedding)

**v1: `CoreMLEncoder` running `bge-small-en-v1.5` (384-dim) on-device.** A real
sentence-transformer gives noticeably better "find by meaning" retrieval than
Apple's built-in embedding, which is worth the setup cost.

```
protocol Encoder {
  var id: String { get }          // e.g. "bge-small-en.v1" — stamped into `embedding.model`
  var dimension: Int { get }      // 384
  func embed(_ text: String, kind: EmbedKind) -> [Float]?   // .query | .document
}
```

**Model.** `BAAI/bge-small-en-v1.5` — 33M params, 384-dim, strong on
short-query→passage retrieval, permissive license. Converted to Core ML
(fp16, ~65 MB) with `coremltools`. Runs on the Neural Engine / GPU.

**Tokenizer.** BERT WordPiece via
[`swift-transformers`](https://github.com/huggingface/swift-transformers)
(`Tokenizers` module), loading the model's `tokenizer.json` — no hand-rolled
tokenization.

**Pooling.** BGE uses the CLS-token embedding, then L2-normalize. The Core ML
model outputs the pooled+normalized vector directly so the Swift side just reads
384 floats.

**Asymmetric query/document (the `kind:` parameter).** BGE recommends prefixing
*queries* (not stored notes) with an instruction:
`"Represent this sentence for searching relevant passages: "`. `.query`
prepends it; `.document` embeds the note text as-is. This matters because our
queries are short and notes are longer.

**Long notes.** BGE's context window is 512 tokens. Longer bodies are chunked
(~256 tokens, small overlap), each chunk embedded, then **mean-pooled +
re-normalized** into one note vector. (Per-chunk vectors are a later refinement
for long-note recall — the schema already allows multiple rows per note.)

**Packaging.** The `.mlpackage` + `tokenizer.json` ship inside the app bundle
(kept out of git via Git LFS or a fetch-on-build script; a checked-in checksum
pins the version). Because the encoder `id` is stamped per embedding (§4), a
future encoder swap just triggers a background re-index and old/new vectors
coexist during the transition.

---

## 8. UI & keyboard model

One screen: a **query field** on top, a **results list** below. The field also
doubles as the note composer in `/n` mode.

**Command parsing** (`CommandParser`, runs on every keystroke):
- Input starting with `/n` (then space/newline) → **compose mode**. The text
  after `/n ` is the note body. `⏎` (or `⌘⏎` for multi-line) saves and clears.
- Anything else → **search mode**. Debounced ~120 ms, runs `SearchService`.
- `/`-prefix is an extensible command namespace (future: `/todo`, etc.).

**Keyboard state machine** (reconciles "backspace edits text" with "backspace
deletes a note"):

```
        type text
   ┌──────────────────────────► EDITING (caret in field)
   │                              │  ↓ arrow ─────────► NAVIGATING
   │  ↑ past top / any char       │
   NAVIGATING (a result selected) ◄┘
     ├─ ↑/↓          move selection
     ├─ ⏎            open / expand selected note
     ├─ ⌫            → CONFIRM-DELETE on selected row
     └─ Esc          back to EDITING
   CONFIRM-DELETE (inline on the row: "Delete? ⏎ confirm · Esc cancel")
     ├─ ⏎            delete note (store + index), return to NAVIGATING
     └─ Esc / type   cancel
```

This satisfies "arrow keys to select, backspace to delete, with a prompt":
once you arrow into the results you're navigating, so `⌫` means delete-selected
(guarded by an inline confirm) rather than editing text. `⌘⌫` is also accepted
as an always-available delete-selected shortcut for muscle memory.

**Esc precedence:** cancel confirm → exit navigating → clear field → hide panel.

State lives in an `AppState: ObservableObject`; SwiftUI views are thin.

---

## 9. Ranking

Search blends **semantic** and **lexical** signals, then applies a mild
**recency** prior — no hand-tuned weight soup.

1. **Semantic candidates:** embed the query (`.query` kind, §7),
   `VectorIndex.search(k=50)`.
2. **Lexical candidates:** `note_fts MATCH` → BM25, top 50.
3. **Fuse** the two ranked lists with **Reciprocal Rank Fusion**:
   `score(d) = Σ 1 / (k + rank_i(d))`, `k = 60`. RRF needs no score
   normalization and gracefully handles a note appearing in only one list.
4. **Recency prior:** multiply by a gentle exponential decay on `updated_at`
   (half-life ~30 days, configurable) so ties and near-ties favor recent notes
   without burying strong older matches.
5. Return top N (default ~8, the visible list height).

Empty query → show most-recent notes (a "recents" home state). Compose mode →
no ranking (the list area can show a live preview / char count instead).

Weights, half-life, and `k` live in one `RankingConfig` for easy tuning and
later user preferences.

---

## 10. Privacy, permissions, distribution

- **Local-only.** No networking code in the app at all. The Core ML model runs
  fully on-device; the DB stays under `~/Library/Application Support/knote/`.
- **Permissions:** with the Carbon hotkey and an on-device Core ML model, v1
  needs **no** Accessibility or other sensitive permission — a deliberate choice.
- **Distribution:** open-source. Xcode project checked in; project files managed
  with **XcodeGen** (a `project.yml`) so the repo has clean, reviewable diffs
  instead of a giant `.pbxproj`. Build a signed/notarized `.app` for releases.

**Future work (seams already in place):** encryption at rest (SQLCipher /
`embedding` stays local), iCloud or file-based sync, a larger/upgraded encoder,
chunk-level (per-chunk) retrieval, tags & pinning, paste-selected-text capture,
additional `/` commands.

---

## 11. Proposed build sequence

1. **Skeleton app:** menu-bar accessory + Carbon hotkey + floating `NSPanel`
   that opens, focuses a SwiftUI text field, and dismisses. (Proves the hardest
   platform bits first.)
2. **Store:** GRDB schema + migrations + `NoteStore` (create/fetch/delete) +
   FTS triggers. `/n` capture writing real rows.
3. **Search:** `Encoder` (Core ML BGE + swift-transformers tokenizer) +
   `InMemoryVectorIndex` + `Indexer` + `SearchService` with RRF ranking. Live
   results as you type. (Convert/bundle the model + tokenizer as a sub-step.)
4. **Keyboard/delete UX:** the §8 state machine, selection, inline
   confirm-delete.
5. **Polish:** recents home state, preferences (hotkey, ranking), packaging
   (XcodeGen, notarization).

Each step is independently runnable and testable (`KnoteCore` unit tests need
no UI).
```
