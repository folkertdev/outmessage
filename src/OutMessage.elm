module OutMessage
    exposing
        ( evaluate
        , evaluateMaybe
        , evaluateResult
        , evaluateList
        , mapComponent
        , mapChildCmd
        , mapOutMsg
        , toNested
        , fromNested
        , run
        , wrap
        )

{-|

**Note: **  This library is opinionated. The usage of an OutMsg is a technique to extend The Elm Architecture (TEA) to support
child-parent communication. The [README]() covers the design.

#Evaluators
@docs evaluate, evaluateMaybe, evaluateList, evaluateResult

#Mapping
@docs mapComponent, mapChildCmd, mapOutMsg

#Helpers
@docs toNested, fromNested

#Extend
@docs wrap, run

Some internal functions that can be used to write your own custom `OutMsg` handler.

-}

import State exposing (state, State, andThen)
import Debug


swap ( x, y ) =
    ( y, x )


applyWithDefault : b -> (a -> b) -> Maybe a -> b
applyWithDefault default f =
    Maybe.withDefault default << Maybe.map f


{-| Embed a function into [State](http://package.elm-lang.org/packages/folkertdev/elm-state/1.0.0/)

-}
wrap : (outmsg -> model -> ( model, Cmd msg )) -> outmsg -> State model (Cmd msg)
wrap f msg =
    State.advance (f msg >> swap)


{-| Evaluate a `State model (Cmd msg)` given a model and effects to prepend.

This is the workhorse.

    wrap (interpretOutMsg) myOutMsg
        |> run Cmd.none myModel
-}
run : Cmd msg -> model -> State model (Cmd msg) -> ( model, Cmd msg )
run cmd model =
    State.map (\outCmd -> Cmd.batch [ cmd, outCmd ])
        >> State.run model
        >> swap


{-| Turn an `OutMsg` value into commands and model changes.

The arguments are:
* An update function, that given the updated child component,
    produces a new model
* `interpretOutMsg`, a function that turns OutMsg values into
    model changes and effects. There are helpers for when the `outmsg` is
    wrapped.
* The return value of a child component update function

Example usage:
    -- in update : Msg -> Model -> (Model, Cmd Msg)
    ChildComponentMessageWrapper childMsg ->
        let
            updateModel : Model -> ChildComponent -> Model
            updateModel oldModel newChildComponent =
                { oldModel | child = newChildComponent }
        in

            ChildComponentModule.update childMsg model.child
                |> mapChildCmd ChildComponentMessageWrapper
                |> evaluate (updateModel model) interpretOutMessage

-}
evaluate :
    (childComponent -> model)
    -> (outMsg -> model -> ( model, Cmd msg ))
    -> ( childComponent, Cmd msg, outMsg )
    -> ( model, Cmd msg )
evaluate updateModel interpretOutMsg ( childComponent, cmd, outMsg ) =
    wrap interpretOutMsg outMsg
        |> run cmd (updateModel childComponent)


{-| Turn a `Maybe OutMsg` into effects.

In the case of `Just outMsg`, the `OutMsg` will be fed to `interpretOutMsg`, in the case of
Nothing, the default `Cmd Msg` is used. The updated child component is always added to the model.
-}
evaluateMaybe :
    (childComponent -> model)
    -> (outMsg -> model -> ( model, Cmd msg ))
    -> Cmd msg
    -> ( childComponent, Cmd msg, Maybe outMsg )
    -> ( model, Cmd msg )
evaluateMaybe updateModel interpretOutMsg default ( childComponent, cmd, outMsg ) =
    applyWithDefault (state default) (wrap interpretOutMsg) outMsg
        |> run cmd (updateModel childComponent)


{-| Turn a `Result error OutMsg` into effects.

In the case of `Ok outMsg`, the `OutMsg` will be fed to `interpretOutMsg`, in the case of
`Err error`, the error will be fed to the given `onErr` function. The updated child component is always added to the model.
-}
evaluateResult :
    (childComponent -> model)
    -> (outMsg -> model -> ( model, Cmd msg ))
    -> (error -> Cmd msg)
    -> ( childComponent, Cmd msg, Result error outMsg )
    -> ( model, Cmd msg )
evaluateResult updateModel interpretOutMsg onErr ( childComponent, cmd, outMsg ) =
    let
        stateful =
            case outMsg of
                Ok v ->
                    wrap interpretOutMsg v

                Err err ->
                    state (onErr err)
    in
        stateful
            |> run cmd (updateModel childComponent)


{-| Turn a `List OutMsg` into effects.

This function takes care of threading the state through. This means that the
Model that is returned by handling an OutMsg will be the input Model of
`interpretOutMsg` when the next `OutMsg` is turned into effects.
-}
evaluateList :
    (childComponent -> model)
    -> (outMsg -> model -> ( model, Cmd msg ))
    -> ( childComponent, Cmd msg, List outMsg )
    -> ( model, Cmd msg )
evaluateList updateModel interpretOutMsg ( childComponent, cmd, outMsgs ) =
    State.traverse (wrap interpretOutMsg) outMsgs
        |> State.map Cmd.batch
        |> run cmd (updateModel childComponent)


{-| Apply a function over the Msg from the child.
-}
mapChildCmd : (childmsg -> parentmsg) -> ( a, Cmd childmsg, c ) -> ( a, Cmd parentmsg, c )
mapChildCmd f ( x, childCmd, z ) =
    ( x, Cmd.map f childCmd, z )


{-| Apply a function over the updated child component.
-}
mapComponent : (childComponent -> a) -> ( childComponent, b, c ) -> ( a, b, c )
mapComponent f ( childComponent, y, z ) =
    ( f childComponent, y, z )


{-| Apply a function over the child's OutMsg.
-}
mapOutMsg : (outMsg -> c) -> ( a, b, outMsg ) -> ( a, b, c )
mapOutMsg f ( x, y, outMsg ) =
    ( x, y, f outMsg )



-- Handy functions


{-| Helper to split the OutMsg from the normal type that `update` has.

The functions `fst` and `snd` can now be used, which can be handy.
-}
toNested : ( a, b, c ) -> ( ( a, b ), c )
toNested ( x, y, z ) =
    ( ( x, y ), z )


{-| Join the component, command and outmessage into a flat tuple.
-}
fromNested : ( ( a, b ), c ) -> ( a, b, c )
fromNested ( ( x, y ), z ) =
    ( x, y, z )
