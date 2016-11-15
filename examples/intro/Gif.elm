module Gif exposing (Model, init, Msg, update, view, subscriptions, OutMsg(..))

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as Json
import Task


main =
    Html.program
        { init = init "cats"
        , view = view
        , update =
            (\msg model ->
                let
                    ( newModel, cmds, _ ) =
                        update msg model
                in
                    ( newModel, cmds )
            )
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { topic : String
    , gifUrl : String
    }


init : String -> ( Model, Cmd Msg )
init topic =
    ( Model topic "waiting.gif"
    , getRandomGif topic
    )



-- UPDATE


type Msg
    = MorePlease
    | Fetch (Result Http.Error String)


type OutMsg
    = SomethingWentWrong Http.Error


update : Msg -> Model -> ( Model, Cmd Msg, Maybe OutMsg )
update msg model =
    case msg of
        MorePlease ->
            ( model, getRandomGif model.topic, Nothing )

        Fetch (Ok newUrl) ->
            ( Model model.topic newUrl, Cmd.none, Nothing )

        Fetch (Err e) ->
            ( model, Cmd.none, Just <| SomethingWentWrong e )



-- VIEW


view : Model -> Html Msg
view model =
    div []
        [ h2 [] [ text model.topic ]
        , img [ imgStyle model.gifUrl ] []
        , br [] []
        , button [ onClick MorePlease ] [ text "More Please!" ]
        ]


imgStyle : String -> Attribute msg
imgStyle url =
    style
        [ ( "display", "inline-block" )
        , ( "width", "200px" )
        , ( "height", "200px" )
        , ( "background-position", "center center" )
        , ( "background-size", "cover" )
        , ( "background-image", ("url('" ++ url ++ "')") )
        ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- HTTP


getRandomGif : String -> Cmd Msg
getRandomGif topic =
    let
        url =
            "//api.giphy.com/v1/gifs/random?api_key=dc6zaTOxFJmzC&tag=" ++ topic
    in
        Http.send Fetch (Http.get url decodeGifUrl)


decodeGifUrl : Json.Decoder String
decodeGifUrl =
    Json.at [ "data", "image_url" ] Json.string
