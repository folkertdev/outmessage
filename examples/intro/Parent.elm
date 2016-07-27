module Parent exposing (..)

import Html exposing (..)
import Html.App as App
import Html.Attributes exposing (..)
import Gif exposing (OutMsg(..))
import OutMessage


main =
    App.program
        { init = init "funny cats" "funny dogs"
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { left : Gif.Model
    , right : Gif.Model
    }


init : String -> String -> ( Model, Cmd Msg )
init leftTopic rightTopic =
    let
        ( left, leftFx ) =
            Gif.init leftTopic

        ( right, rightFx ) =
            Gif.init rightTopic
    in
        ( Model left right
        , Cmd.batch
            [ Cmd.map Left leftFx
            , Cmd.map Right rightFx
            ]
        )



-- UPDATE


type Msg
    = Left Gif.Msg
    | Right Gif.Msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Left leftMsg ->
            Gif.update leftMsg model.left
                -- add the updated child to the parent
                |>
                    OutMessage.mapComponent (\newChild -> Model newChild model.right)
                -- map the child's commands to parent commands
                |>
                    OutMessage.mapCmd Left
                -- give a default command (for Nothing) and a way
                -- to convert OutMsg to (Model, Cmd Msg)
                |>
                    OutMessage.evaluateMaybe interpretOutMsg Cmd.none

        Right rightMsg ->
            Gif.update rightMsg model.right
                |> OutMessage.mapComponent (\newChild -> Model model.left newChild)
                |> OutMessage.mapCmd Right
                |> OutMessage.evaluateMaybe interpretOutMsg Cmd.none


interpretOutMsg : Gif.OutMsg -> Model -> ( Model, Cmd Msg )
interpretOutMsg outmsg model =
    case outmsg of
        SomethingWentWrong err ->
            let
                _ =
                    Debug.log "A child component had an http error" (toString err)
            in
                ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ style [ ( "display", "flex" ) ]
        ]
        [ App.map Left (Gif.view model.left)
        , App.map Right (Gif.view model.right)
        ]



-- SUBS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Sub.map Left (Gif.subscriptions model.left)
        , Sub.map Right (Gif.subscriptions model.right)
        ]
