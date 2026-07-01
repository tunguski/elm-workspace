module Main exposing (main)

{-| The elm-workspace demo site.

Like elm-notebook and elm-svg, this is a [`Workspace.Site`](Workspace-Site): a landing page plus the
live workspace under a navbar, with hash routing. The managed document is a *trivial* plain-text
**note** (`{ text }`) — the point of the demo is that even so it gets the whole workspace for free:
create / name / open / search / copy / delete, sharing & permissions, threaded comments, URL import
and CSV / JSON export. The same `Workspace` component drives elm-notebook, elm-svg and elm-spreadsheet;
only the few hooks in [`config`](#config) differ.

The landing presents a **disabled** (non-interactive) preview of the workspace alongside the Elm
needed to embed it, and a link to the live workspace.

-}

import Html exposing (Html, div, p, pre, section, text)
import Html.Attributes as HA
import Html.Events
import Json.Decode as D
import Json.Encode as E
import Workspace
import Workspace.Backend exposing (Backend, Context)
import Workspace.Browser
import Workspace.I18n
import Workspace.Site
import Workspace.Types as Types exposing (Table)


main : Program () (Workspace.Site.Model NoteDoc Preview) (Workspace.Site.Msg NoteMsg PreviewMsg)
main =
    Workspace.Site.program
        { title = "elm-workspace"
        , namespace = "elm-workspace-demo"
        , logo = "logo.svg"
        , eyebrow = "elm · reusable workspace"
        , lead =
            [ text "A reusable workspace around any document — create, name, share, comment on, import "
            , text "into and export many documents, over a storage backend you choose. It powers "
            , text "elm-notebook, elm-svg and elm-spreadsheet. Open the "
            , Workspace.Site.workspaceLink [ text "live workspace" ]
            , text " (here managing plain-text notes), or see how to embed it below."
            ]
        , repoUrl = "https://github.com/tunguski/elm-workspace"
        , workspace = config
        , context = ctx
        , landing =
            { init = preview
            , update = \_ m -> ( m, Cmd.none )
            , subscriptions = \_ -> Sub.none
            , view = landingView
            , copyToWorkspace = \_ _ -> Nothing
            }
        }



-- THE DOCUMENT ---------------------------------------------------------------


{-| A note is just some text. -}
type alias NoteDoc =
    { text : String }


type NoteMsg
    = SetText String


emptyNote : NoteDoc
emptyNote =
    { text = "" }


encodeNote : NoteDoc -> E.Value
encodeNote doc =
    E.object [ ( "text", E.string doc.text ) ]


noteDecoder : D.Decoder NoteDoc
noteDecoder =
    D.map NoteDoc (D.field "text" D.string)


updateNote : NoteMsg -> NoteDoc -> NoteDoc
updateNote (SetText s) doc =
    { doc | text = s }


viewNote : Workspace.EditorEnv -> NoteDoc -> Html NoteMsg
viewNote env doc =
    div [ HA.class "note" ]
        [ if env.commentsVisible && env.commentCount "note" > 0 then
            Html.span [ HA.class "note-marker" ]
                [ Html.i [ HA.class "bi bi-chat-dots" ] [], text (" " ++ String.fromInt (env.commentCount "note")) ]

          else
            text ""
        , Html.textarea
            [ HA.class "note-text"
            , HA.attribute "rows" "16"
            , HA.placeholder "Write your note here…"
            , HA.value doc.text
            , Html.Events.onInput SetText
            ]
            []
        ]


{-| One commentable element: the note itself. -}
noteElements : NoteDoc -> List ( String, String )
noteElements _ =
    [ ( "note", "The note" ) ]


{-| Export a note as a one-column table (one line per row). -}
noteTable : NoteDoc -> Maybe Table
noteTable doc =
    if String.trim doc.text == "" then
        Nothing

    else
        Just
            { headers = [ "line" ]
            , rows = String.lines doc.text |> List.map (\l -> [ l ])
            }


{-| Apply imported tabular data to the note (one row per line). -}
noteImport : Table -> NoteDoc -> NoteDoc
noteImport table _ =
    { text =
        (table.headers :: table.rows)
            |> List.map (String.join " | ")
            |> String.join "\n"
    }


config : Workspace.Config NoteDoc NoteMsg
config =
    { codec = { encode = encodeNote, decoder = noteDecoder }
    , empty = emptyNote
    , kind = "note"
    , activate = identity
    , viewDoc = viewNote
    , updateDoc = updateNote
    , elementsOf = noteElements
    , toTable = noteTable
    , onImport = Just noteImport
    , t = Workspace.I18n.en
    , templates = []
    , references = \_ -> []
    , provide = \_ _ -> Err "a note has no referenceable data"
    , absorb = \_ doc -> doc
    , docSql = \_ -> Nothing
    }



-- WIRING ---------------------------------------------------------------------


ctx : Context
ctx =
    { user = "me", groups = [] }



-- LANDING: a disabled workspace preview + an embedding snippet --------------------


{-| The landing's state is a seeded, non-interactive workspace model used purely for the preview. -}
type alias Preview =
    Workspace.Model NoteDoc


type PreviewMsg
    = Ignore


previewBackend : Backend (Workspace.Msg NoteMsg)
previewBackend =
    Workspace.Browser.backend "elm-workspace-preview"


{-| A workspace model seeded with a few sample documents, so the disabled preview has content. -}
preview : Preview
preview =
    let
        ( model, _ ) =
            Workspace.init previewBackend
    in
    { model
        | metas =
            [ Types.newMeta "demo-1" "Quarterly review" "note" "me"
            , Types.newMeta "demo-2" "Trip budget" "note" "me"
            , Types.newMeta "demo-3" "Reading list" "note" "me"
            ]
    }


landingView : Preview -> Html PreviewMsg
landingView model =
    div [ HA.class "wsite-app" ]
        [ section [ HA.class "wsite-section" ]
            [ Html.h2 [] [ text "The workspace, embedded" ]
            , p []
                [ text "Below is the actual workspace component (disabled here) — the same UI you get "
                , text "live. It manages your documents with search, sharing, comments, import and export."
                ]
            , div [ HA.class "wsite-preview" ]
                [ Html.span [ HA.class "wsite-preview-tag" ] [ text "preview" ]
                , div [ HA.class "wsite-preview-frame" ]
                    [ Html.map (always Ignore) (Workspace.view config previewBackend ctx model) ]
                ]
            ]
        , section [ HA.class "wsite-section" ]
            [ Html.h2 [] [ text "Use it in your Elm app" ]
            , p []
                [ text "Supply a document "
                , Html.code [] [ text "Config" ]
                , text " (a JSON codec plus editor hooks) and a "
                , Html.code [] [ text "Backend" ]
                , text ", then hand the whole site to "
                , Html.code [] [ text "Workspace.Site.program" ]
                , text "."
                ]
            , pre [ HA.class "wsite-code" ] [ text embedSnippet ]
            ]
        ]


embedSnippet : String
embedSnippet =
    """import Workspace
import Workspace.Site

-- 1. Describe your document: how to (de)serialise it and how to edit it.
config : Workspace.Config Note NoteMsg
config =
    { codec = { encode = encodeNote, decoder = noteDecoder }
    , empty = { text = "" }
    , kind = "note"
    , activate = identity
    , viewDoc = viewNote          -- EditorEnv -> Note -> Html NoteMsg
    , updateDoc = updateNote      -- NoteMsg -> Note -> Note
    , elementsOf = \\_ -> [ ( "note", "The note" ) ]
    , toTable = noteTable         -- export to CSV / JSON
    , onImport = Just noteImport  -- import a URL / database table
    }

-- 2. Hand it to the site template: landing + workspace + routing, for free.
main =
    Workspace.Site.program
        { title = "my-notes"
        , namespace = "my-notes"
        , logo = "logo.svg"
        , eyebrow = "notes"
        , lead = [ Html.text "Take notes. Open the ", Workspace.Site.workspaceLink [ Html.text "Workspace" ], Html.text "." ]
        , repoUrl = "https://github.com/me/my-notes"
        , workspace = config
        , context = { user = "me", groups = [] }
        , landing = landing
        }
"""
