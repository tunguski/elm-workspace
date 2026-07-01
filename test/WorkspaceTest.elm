module WorkspaceTest exposing (suite)

{-| Headless tests for the pure core of elm-workspace: permissions, comment threading, the SQL
query builder, the Table CSV/JSON codecs and JSON serialisation round-trips. -}

import Dict exposing (Dict)
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)
import Workspace.Comment as Comment
import Workspace.Db as Db
import Workspace.Permissions as Permissions
import Workspace.Refs as Refs
import Workspace.Serialize as Serialize
import Workspace.Table as Table
import Workspace.Types as Types exposing (DocRef, Id, Principal(..), Selector(..), Stored, Visibility(..))


me : { user : String, groups : List String }
me =
    { user = "ada", groups = [ "eng" ] }


stranger : { user : String, groups : List String }
stranger =
    { user = "zed", groups = [] }


suite : Test
suite =
    describe "elm-workspace"
        [ permissions
        , comments
        , db
        , tables
        , serialize
        , refs
        ]



-- PERMISSIONS ----------------------------------------------------------------


permissions : Test
permissions =
    let
        owned =
            Types.defaultAccess "ada"

        shared =
            owned |> Types.addReader (User "bob")

        groupOwned =
            { owners = [ Group "eng" ], readers = [], visibility = Private }

        publicDoc =
            { owners = [ User "bob" ], readers = [], visibility = Public }
    in
    describe "Permissions"
        [ test "creator is owner: can read and write" <|
            \_ ->
                Expect.equal ( True, True ) ( Permissions.canRead me owned, Permissions.canWrite me owned )
        , test "stranger cannot read a private doc" <|
            \_ ->
                Expect.equal False (Permissions.canRead stranger owned)
        , test "reader can read but not write" <|
            \_ ->
                Expect.equal ( True, False )
                    ( Permissions.canRead { user = "bob", groups = [] } shared
                    , Permissions.canWrite { user = "bob", groups = [] } shared
                    )
        , test "group membership grants ownership" <|
            \_ ->
                Expect.equal True (Permissions.canWrite me groupOwned)
        , test "public doc is readable by any logged-in user" <|
            \_ ->
                Expect.equal True (Permissions.canRead stranger publicDoc)
        , test "public doc is not readable by an anonymous (empty) user" <|
            \_ ->
                Expect.equal False (Permissions.canRead { user = "", groups = [] } publicDoc)
        , test "adding the same owner twice is idempotent" <|
            \_ ->
                (Types.defaultAccess "ada"
                    |> Types.addOwner (User "bob")
                    |> Types.addOwner (User "bob")
                ).owners
                    |> List.length
                    |> Expect.equal 2
        , test "removing an owner drops it" <|
            \_ ->
                (Types.defaultAccess "ada"
                    |> Types.addOwner (User "bob")
                    |> Types.removeOwner (User "bob")
                ).owners
                    |> Expect.equal [ User "ada" ]
        ]



-- COMMENTS -------------------------------------------------------------------


comments : Test
comments =
    let
        c1 =
            Comment.add "cell-1" "ada" "first!" Dict.empty

        c2 =
            Comment.add "cell-1" "bob" "second" c1

        withReply =
            Comment.reply "cell-1" 1 "carol" "replying to first" c2
    in
    describe "Comment"
        [ test "add puts a comment on an element" <|
            \_ -> Expect.equal 1 (Comment.countFor "cell-1" c1)
        , test "ids increase" <|
            \_ -> Expect.equal 3 (Comment.nextId c2)
        , test "total counts across elements" <|
            \_ -> Expect.equal 2 (Comment.total c2)
        , test "reply threads under its parent and is counted" <|
            \_ -> Expect.equal 3 (Comment.total withReply)
        , test "countFor includes nested replies" <|
            \_ -> Expect.equal 3 (Comment.countFor "cell-1" withReply)
        , test "deleteThread removes an element's comments" <|
            \_ -> Expect.equal 0 (Comment.total (Comment.deleteThread "cell-1" withReply))
        ]



-- DB -------------------------------------------------------------------------


db : Test
db =
    describe "Db query builder"
        [ test "select / where / order / limit" <|
            \_ ->
                Db.from "users"
                    |> Db.where_ (Db.gt "age" "18")
                    |> Db.select [ "name", "age" ]
                    |> Db.orderBy "age"
                    |> Db.limit 20
                    |> Db.toSql
                    |> Expect.equal "SELECT name, age FROM users WHERE age > 18 ORDER BY age ASC LIMIT 20"
        , test "select * by default" <|
            \_ ->
                Db.from "t" |> Db.toSql |> Expect.equal "SELECT * FROM t"
        , test "string values are quoted, numbers bare" <|
            \_ ->
                Db.from "t" |> Db.where_ (Db.eq "city" "Oslo") |> Db.toSql |> Expect.equal "SELECT * FROM t WHERE city = 'Oslo'"
        , test "LIKE quotes its pattern" <|
            \_ ->
                Db.from "t" |> Db.where_ (Db.like "name" "A%") |> Db.toSql |> Expect.equal "SELECT * FROM t WHERE name LIKE 'A%'"
        , test "embedded quotes are doubled" <|
            \_ ->
                Db.from "t" |> Db.where_ (Db.eq "x" "O'Hara") |> Db.toSql |> Expect.equal "SELECT * FROM t WHERE x = 'O''Hara'"
        , test "and_ / or_ nest with parentheses" <|
            \_ ->
                Db.from "t"
                    |> Db.where_ (Db.and_ (Db.gt "a" "1") (Db.lt "b" "2"))
                    |> Db.toSql
                    |> Expect.equal "SELECT * FROM t WHERE (a > 1 AND b < 2)"
        , test "multiple where_ are AND-ed; desc + offset" <|
            \_ ->
                Db.from "t"
                    |> Db.where_ (Db.gte "a" "1")
                    |> Db.where_ (Db.neq "b" "x")
                    |> Db.descBy "a"
                    |> Db.limit 5
                    |> Db.offset 10
                    |> Db.toSql
                    |> Expect.equal "SELECT * FROM t WHERE a >= 1 AND b <> 'x' ORDER BY a DESC LIMIT 5 OFFSET 10"
        ]



-- TABLES ---------------------------------------------------------------------


tables : Test
tables =
    describe "Table"
        [ test "fromCsv reads headers and rows" <|
            \_ ->
                Table.fromCsv "name, age\nAda, 36\nBob, 41"
                    |> Expect.equal { headers = [ "name", "age" ], rows = [ [ "Ada", "36" ], [ "Bob", "41" ] ] }
        , test "fromCsv auto-detects tabs" <|
            \_ ->
                Table.fromCsv "a\tb\n1\t2"
                    |> Expect.equal { headers = [ "a", "b" ], rows = [ [ "1", "2" ] ] }
        , test "fromCsv honours quoted fields with commas" <|
            \_ ->
                (Table.fromCsv "name,note\nAda,\"hi, there\"").rows
                    |> Expect.equal [ [ "Ada", "hi, there" ] ]
        , test "fromJson reads an array of objects" <|
            \_ ->
                Table.fromJson "[{\"name\":\"Ada\",\"age\":36},{\"name\":\"Bob\",\"age\":41}]"
                    |> Expect.equal (Ok { headers = [ "name", "age" ], rows = [ [ "Ada", "36" ], [ "Bob", "41" ] ] })
        , test "toCsv quotes fields that need it" <|
            \_ ->
                Table.toCsv { headers = [ "a", "b" ], rows = [ [ "x", "y,z" ] ] }
                    |> Expect.equal "a,b\nx,\"y,z\""
        , test "column picks one column by name" <|
            \_ ->
                Table.column "age" { headers = [ "name", "age" ], rows = [ [ "Ada", "36" ], [ "Bob", "41" ] ] }
                    |> Expect.equal [ "36", "41" ]
        ]



-- SERIALIZE ------------------------------------------------------------------


serialize : Test
serialize =
    let
        access =
            Types.defaultAccess "ada"
                |> Types.addReader (User "bob")
                |> Types.addOwner (Group "eng")
                |> Types.setVisibility Public

        meta =
            { id = "d1", name = "My doc", kind = "note", access = access }

        cs =
            Comment.reply "note" 1 "bob" "re" (Comment.add "note" "ada" "hi" Dict.empty)

        stored =
            { meta = meta, doc = "the body", comments = cs }

        roundTripMeta =
            E.encode 0 (Serialize.encodeMeta meta)
                |> D.decodeString Serialize.metaDecoder

        roundTripStored =
            E.encode 0 (Serialize.encodeStored E.string stored)
                |> D.decodeString (Serialize.storedDecoder D.string)

        roundTripIndex =
            E.encode 0 (Serialize.encodeIndex [ meta ])
                |> D.decodeString Serialize.indexDecoder
    in
    describe "Serialize"
        [ test "meta round-trips through JSON" <|
            \_ -> Expect.equal (Ok meta) roundTripMeta
        , test "stored document round-trips (with a host doc codec)" <|
            \_ -> Expect.equal (Ok stored) roundTripStored
        , test "the index round-trips" <|
            \_ -> Expect.equal (Ok [ meta ]) roundTripIndex
        , test "references round-trip (all three selector shapes)" <|
            \_ ->
                let
                    rs =
                        [ { binding = "all", docId = "a", selector = WholeDoc }
                        , { binding = "orders", docId = "b", selector = Step "s7" }
                        , { binding = "grid", docId = "c", selector = RangeSel "A1:C10" }
                        ]
                in
                E.encode 0 (Serialize.encodeRefs rs)
                    |> D.decodeString Serialize.refsDecoder
                    |> Expect.equal (Ok rs)
        ]



-- REFS -----------------------------------------------------------------------


{-| A trivial document for exercising the reference engine: some outgoing references, a literal
value, and a record of the bindings that were absorbed into it (so a test can see resolution ran). -}
type alias RDoc =
    { refs : List DocRef
    , value : String
    , seen : List String
    }


rdoc : Id -> List DocRef -> String -> ( Id, Stored RDoc )
rdoc id rs v =
    ( id
    , { meta = Types.newMeta id "" "r" "me"
      , doc = { refs = rs, value = v, seen = [] }
      , comments = Dict.empty
      }
    )


{-| A resolver whose `provide` returns the document's value as a 1×1 table, whose `absorb` records
which bindings arrived (and folds their single cell into `seen`), and whose `activate` is a no-op. -}
rResolver : Refs.Resolver RDoc
rResolver =
    { references = .refs
    , provide =
        \selector doc ->
            case selector of
                WholeDoc ->
                    Ok { headers = [ "v" ], rows = [ [ doc.value ] ] }

                _ ->
                    Err "only WholeDoc is supported"
    , absorb =
        \tables doc ->
            { doc
                | seen =
                    Dict.toList tables
                        |> List.map (\( b, t ) -> b ++ "=" ++ (List.concat t.rows |> String.join "/"))
            }
    , activate = identity
    }


ref : String -> Id -> DocRef
ref binding docId =
    { binding = binding, docId = docId, selector = WholeDoc }


refs : Test
refs =
    let
        -- A → B → C, plus A → C directly. Acyclic.
        cache =
            Dict.fromList
                [ rdoc "A" [ ref "fromB" "B", ref "fromC" "C" ] "a"
                , rdoc "B" [ ref "fromC" "C" ] "b"
                , rdoc "C" [] "c"
                ]

        edges id =
            Dict.get id cache
                |> Maybe.map (\s -> List.map .docId s.doc.refs)
                |> Maybe.withDefault []
    in
    describe "Refs"
        [ test "topoOrder puts dependencies before dependents" <|
            \_ ->
                case Refs.topoOrder edges [ "A" ] of
                    Ok order ->
                        -- C before B before A
                        Expect.equal True (indexOf "C" order < indexOf "B" order && indexOf "B" order < indexOf "A" order)

                    Err _ ->
                        Expect.fail "expected an acyclic order"
        , test "cycleFrom finds no cycle in an acyclic graph" <|
            \_ -> Expect.equal Nothing (Refs.cycleFrom edges "A")
        , test "a self-reference is a cycle" <|
            \_ ->
                let
                    selfEdges id =
                        if id == "X" then
                            [ "X" ]

                        else
                            []
                in
                Expect.notEqual Nothing (Refs.cycleFrom selfEdges "X")
        , test "topoOrder reports a cycle as Err" <|
            \_ ->
                let
                    cyc id =
                        case id of
                            "P" ->
                                [ "Q" ]

                            "Q" ->
                                [ "P" ]

                            _ ->
                                []
                in
                case Refs.topoOrder cyc [ "P" ] of
                    Err _ ->
                        Expect.pass

                    Ok _ ->
                        Expect.fail "expected a cycle error"
        , test "resolve threads a dependency's value into the dependent's bindings" <|
            \_ ->
                case Refs.resolve rResolver "A" cache of
                    Ok res ->
                        Dict.get "A" res.docs
                            |> Maybe.map (\s -> List.sort s.doc.seen)
                            |> Expect.equal (Just [ "fromB=b", "fromC=c" ])

                    Err _ ->
                        Expect.fail "expected resolution to succeed"
        , test "resolve of a cyclic closure fails with Cycle" <|
            \_ ->
                let
                    cyclic =
                        Dict.fromList
                            [ rdoc "P" [ ref "q" "Q" ] "p"
                            , rdoc "Q" [ ref "p" "P" ] "q"
                            ]
                in
                case Refs.resolve rResolver "P" cyclic of
                    Err (Refs.Cycle _) ->
                        Expect.pass

                    Ok _ ->
                        Expect.fail "expected a cycle error"
        , test "a reference to a missing document is a warning, not a failure" <|
            \_ ->
                let
                    dangling =
                        Dict.fromList [ rdoc "A" [ ref "gone" "ZZZ" ] "a" ]
                in
                case Refs.resolve rResolver "A" dangling of
                    Ok res ->
                        Expect.equal 1 (List.length res.warnings)

                    Err _ ->
                        Expect.fail "a dangling reference should not block resolution"
        ]


indexOf : a -> List a -> Int
indexOf x xs =
    let
        go i list =
            case list of
                [] ->
                    -1

                y :: rest ->
                    if y == x then
                        i

                    else
                        go (i + 1) rest
    in
    go 0 xs
