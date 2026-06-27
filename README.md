# elm-workspace

A **reusable workspace around any document** — for the [elm-lang](https://github.com/tunguski/elm-lang)
compiler. Drop it on top of a document type (a notebook, a spreadsheet, a chart spec, a report) and
you get the whole multi-document experience for free:

- **Create / name / open / search / copy / delete** documents.
- **Permissions** — owners and readers, as users *or* groups, plus private / public, edited through
  a sharing dialog. The creator is the sole owner by default.
- **Threaded comments** on a document's elements, with markers showing where conversation lives and
  one toggle to show / hide them all.
- **Import data** from a URL (JSON or CSV / TSV).
- **SQL queries** via a small forward-pipe builder, run through the backend and added to the
  document (shown disabled when there is no database).
- **Export** a document to CSV / JSON (in-browser) or Excel (through a configurable backend).

Live demo (a workspace of plain-text notes): **https://tunguski.github.io/elm-workspace/**

## Two seams, so one component fits every host

The component is generic along two axes, both injected by the host — so the library code is
identical whether it runs on the public site (browser storage) or inside an app with a database.

### 1. The document

The host supplies a [`Config doc docMsg`](src/Workspace.elm): a JSON codec, an `empty` document,
editor hooks (`viewDoc` / `updateDoc`), and a few small maps that let the workspace offer comments
(`elementsOf`), export (`toTable`) and import (`onImport`) for that document type.

```elm
config : Workspace.Config NoteDoc NoteMsg
config =
    { codec = { encode = encodeNote, decoder = noteDecoder }
    , empty = emptyNote
    , kind = "note"
    , activate = identity            -- e.g. a notebook re-runs its cells here
    , viewDoc = viewNote             -- the host's own editor
    , updateDoc = updateNote
    , elementsOf = \_ -> [ ( "note", "The note" ) ]   -- commentable elements
    , toTable = noteTable            -- Nothing ⇒ no export
    , onImport = Just noteImport     -- Nothing ⇒ no import / query
    }
```

### 2. The backend

A [`Backend msg`](src/Workspace/Backend.elm) record of effect builders, generic over the host's
message. Reads take a result-tagger; writes are fire-and-forget (the in-memory model is the source
of truth). Documents cross the boundary as **raw JSON strings**, so the backend never mentions the
`doc` type.

- The site uses [`Workspace.Browser.backend namespace`](src/Workspace/Browser.elm) — `localStorage`,
  with `query = Nothing` and `exportExcel = Nothing` (those actions show disabled).
- An app like **bbx** supplies an HTTP backend talking to its database, with `query` and
  `exportExcel` wired — **and the component does not change**.

## Embedding it

It is an ordinary TEA component:

```elm
type Msg = WsMsg (Workspace.Msg DocMsg)

init _ =
    let ( ws, cmd ) = Workspace.init backend
    in ( { ws = ws }, Cmd.map WsMsg cmd )

update (WsMsg m) model =
    let ( ws, cmd ) = Workspace.update config backend ctx m model.ws
    in ( { ws = ws }, Cmd.map WsMsg cmd )

view model = Html.map WsMsg (Workspace.view config backend ctx model.ws)
```

`ctx : Workspace.Backend.Context` is `{ user, groups }` — a local pseudo-user on the site, the
logged-in user in an app.

## Modules

| Module | Role |
| ------ | ---- |
| `Workspace` | the component (model, update, view) |
| `Workspace.Types` | data types + all record updaters |
| `Workspace.Permissions` | `canRead` / `canWrite` from a context + access |
| `Workspace.Comment` | threaded add / reply / count |
| `Workspace.Backend` | the `Backend` + `Context` seams |
| `Workspace.Browser` | the localStorage backend |
| `Workspace.Serialize` | JSON for metadata, access, comments, the stored envelope |
| `Workspace.Table` | the neutral table + CSV / JSON parse & render |
| `Workspace.Db` | the forward-pipe SQL builder |

## Reuse = vendoring

Like the other elm-lang libraries, reuse is by **vendoring**: copy `src/Workspace/*.elm` into the
consumer's source path. [elm-notebook](https://github.com/tunguski/elm-notebook) and
[elm-svg](https://github.com/tunguski/elm-svg) both do this and supply their own `Config`.

## Develop

With this repo checked out next to a built [`elm-lang`](https://github.com/tunguski/elm-lang) (so
`../../elm.sh` exists):

```sh
ELM=../../elm.sh ./test.sh     # headless test suite (permissions, comments, Db, Table, Serialize)
ELM=../../elm.sh ./build.sh    # compile the demo → build/elm-workspace.html (self-contained)
```

`.github/workflows/pages.yml` runs the same steps in CI and deploys to GitHub Pages, gated on the
tests passing.

Part of the [elm-lang](https://github.com/tunguski/elm-lang) ecosystem.
