module Main exposing (main)

{-| The elm-workspace demo: a workspace that manages plain-text **notes**, stored in the browser.

The point of the demo is that the document type is *trivial* — a note is just `{ text }` — yet it
gets the whole workspace for free: create / name / open / search / copy / delete, sharing &
permissions, threaded comments, URL import and CSV / JSON export. The same `Workspace` component
drives elm-notebook (a notebook document) and elm-svg (a chart-spec document); only the few hooks
in [`config`](#config) below differ.

-}

import Browser
import Html exposing (Html, a, div, footer, h1, header, p, span, text, textarea)
import Html.Attributes as HA
import Html.Events as HE
import Json.Decode as D
import Json.Encode as E
import Workspace
import Workspace.Backend exposing (Backend, Context)
import Workspace.Browser
import Workspace.Types exposing (Table)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
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
            span [ HA.class "note-marker" ]
                [ Html.i [ HA.class "bi bi-chat-dots" ] [], text (" " ++ String.fromInt (env.commentCount "note")) ]

          else
            text ""
        , textarea
            [ HA.class "note-text"
            , HA.attribute "rows" "16"
            , HA.placeholder "Write your note here…"
            , HA.value doc.text
            , HE.onInput SetText
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
    }



-- WIRING ---------------------------------------------------------------------


ctx : Context
ctx =
    { user = "me", groups = [] }


backend : Backend (Workspace.Msg NoteMsg)
backend =
    Workspace.Browser.backend "elm-workspace-demo"


type alias Model =
    { ws : Workspace.Model NoteDoc }


type Msg
    = WsMsg (Workspace.Msg NoteMsg)


init : () -> ( Model, Cmd Msg )
init _ =
    let
        ( ws, cmd ) =
            Workspace.init backend
    in
    ( { ws = ws }, Cmd.map WsMsg cmd )


update : Msg -> Model -> ( Model, Cmd Msg )
update (WsMsg m) model =
    let
        ( ws, cmd ) =
            Workspace.update config backend ctx m model.ws
    in
    ( { ws = ws }, Cmd.map WsMsg cmd )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.map WsMsg (Workspace.subscriptions model.ws)


view : Model -> Html Msg
view model =
    div [ HA.class "ws-page" ]
        [ header [ HA.class "ws-hero" ]
            [ div [ HA.class "ws-hero-inner" ]
                [ span [ HA.class "ws-eyebrow" ] [ text "elm · reusable workspace" ]
                , h1 [] [ text "elm-workspace" ]
                , p [ HA.class "ws-lead" ]
                    [ text "A reusable workspace around any document — here, plain-text notes stored in your browser. "
                    , text "The same component powers elm-notebook and elm-svg."
                    ]
                ]
            ]
        , Html.map WsMsg (Workspace.view config backend ctx model.ws)
        , footer [ HA.class "ws-foot" ]
            [ a [ HA.href "tests.html" ] [ text "Test report" ]
            , text " · "
            , a [ HA.href "https://github.com/tunguski/elm-workspace" ] [ text "GitHub" ]
            , text " · "
            , a [ HA.href "https://tunguski.github.io/" ] [ text "More projects" ]
            ]
        ]
