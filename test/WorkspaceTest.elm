module WorkspaceTest exposing (suite)

{-| Headless tests for the pure core of elm-workspace: permissions, comment threading, the SQL
query builder, the Table CSV/JSON codecs and JSON serialisation round-trips. -}

import Dict
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)
import Workspace.Comment as Comment
import Workspace.Db as Db
import Workspace.Permissions as Permissions
import Workspace.Serialize as Serialize
import Workspace.Table as Table
import Workspace.Types as Types exposing (Principal(..), Visibility(..))


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
        ]
