Streamlining parent-child communication with OutMsg
===================================================

The OutMsg pattern is a technique for child-parent communication with The Elm Architecture (TEA). It has two components: 

* `OutMsg`, a user-defined type (just like Msg) with the specific purpose of notifying a parent component.
* `interpretOutMsg`, a function that converts OutMsg values into side-effects (commands and changes to the model)

OutMsg values can be captured in the parent's update function, and handled there by `interpretOutMsg`.
The pattern can be extended to work with multiple `OutMsg` using `List` or to optionally return no `OutMsg` using `Maybe`.

**Technical writing is hard:** If anything is unclear, please open an issue, or create a PR.

## The core idea

Using OutMsg means that the update function of a child component returns a value of type OutMsg. Instead of the 
usual type:

```elm
update : ChildMsg -> ChildModel -> (ChildModel, Cmd ChildMsg)
```

Its return type is something like this. 

```elm
update : ChildMsg -> ChildModel -> (ChildModel, Cmd ChildMsg, OutMsg)
```

In the parent's update function, this library takes care of turning the OutMsg into commands and model changes.

```elm
-- in update : Msg -> Model -> (Model, Cmd Msg)
-- assuming interpretOutMsg : OutMsg -> Model -> (Model, Cmd Msg)
ChildComponentMessageWrapper childMsg ->
    ChildComponentModule.update childMsg model.child
        -- update the model with the new child component
        |> OutMessage.mapComponent
            (\newChild -> { model | child = newChild }
        -- convert child cmd to parent cmd
        |> OutMessage.mapCmd ChildComponentMessageWrapper
        -- apply outmsg changes
        |> OutMessage.evaluate interpretOutMsg
```

# An example

As a running example, let's look at [TEA](https://github.com/evancz/elm-architecture-tutorial/tree/master/nesting)s Gif. 
Let's say that the parent component needs to be notified of any http failures, so it can respond to them. The changes that 
are described here can be found in 
[this commit](https://github.com/folkertdev/outmessage/commit/0ab20bd4e0f28d74e4c00f0248ed2300aff20aed), the full code in the [examples/intro](https://github.com/folkertdev/outmessage/tree/master/examples/intro) folder.

Following the pattern, we need to: 

* Change the child's update function to return an OutMsg
* Write a `interpretOutMsg` function 
* Wire everything up in the parent's update function


### Changes to the child

The child's update function is defined as follows:
```elm
-- Gif.elm 

type Msg
  = MorePlease
  | FetchSucceed String
  | FetchFail Http.Error


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    MorePlease ->
      (model, getRandomGif model.topic)

    FetchSucceed newUrl ->
      (Model model.topic newUrl, Cmd.none)

    FetchFail _ ->
      (model, Cmd.none)
```

We change the return type to include a `Maybe OutMsg`, which means that the following 
needs to change:
```elm
-- old 
update : Msg -> Model -> (Model, Cmd Msg)
(model, getRandomGif model.topic)
-- new
update : Msg -> Model -> (Model, Cmd Msg, Maybe OutMsg)
(model, getRandomGif model.topic, Nothing)
```

The complete new update function becomes: 

```elm
-- Gif.elm 

-- explicitly expose all OutMsg constructors
module Gif exposing (Model, init, Msg, update, view, subscriptions, OutMsg(..))

type OutMsg
    = SomethingWentWrong Http.Error


update : Msg -> Model -> ( Model, Cmd Msg, Maybe OutMsg )
update msg model =
    case msg of
        MorePlease ->
            ( model, getRandomGif model.topic, Nothing )

        FetchSucceed newUrl ->
            ( Model model.topic newUrl, Cmd.none, Nothing )

        FetchFail e ->
            ( model, Cmd.none, Just <| SomethingWentWrong e )
```

### Changes to the parent

The `OutMsg` value can now be extracted by the parent

```elm
-- Parent.elm
    ( left, leftCmds, outMsg) = 
        Gif.update leftMsg model.left
```

To turn the OutMsg into commands and model changes (side-effects), we need a function:

```elm
interpretOutMsg : OutMsg -> Model -> (Model, Cmd Msg)
```

Notice the similarity between update and interpretOutMsg.
```elm
update :             Msg -> Model -> (Model, Cmd Msg)
interpretOutMsg : OutMsg -> Model -> (Model, Cmd Msg)
```

A dummy interpretOutMsg could be 

```elm 
-- Parent.elm 

-- import all the child's OutMsg constructors
import Gif exposing (OutMsg(..))

interpretOutMsg : Gif.OutMsg -> Model -> ( Model, Cmd Msg )
interpretOutMsg outmsg model =
    case outmsg of
        SomethingWentWrong err ->
            let
                _ =
                    Debug.log "A child component had an http error" (toString err)
            in
                ( model, Cmd.none )
```


### Wiring

The only thing that remains is wiring, but that seems to become a hairy affair very quickly. That is where this 
library comes in.

For brevity I will only work with the `Right` branch of the parent's update function. 
This is what the wiring looks like:
```elm
-- Parent.elm 
        Right rightMsg ->
            let
                -- call update of the child component
                ( right, rightCmds, outMsg) =
                    Gif.update rightMsg model.right

                -- add the updated child component to the model
                newModel = 
                    Model model.left right 
    
                -- interpret the outMsg using the updated model
                (newerModel, outCommands) = 
                    case outMsg of 
                        Just v -> 
                            interpretOutMsg v newModel
                        Nothing -> 
                            ( model, Cmd.none )
    
            in
                ( newerModel 
                , Cmd.batch 
                    -- map the child commands (wrap them in a parent Msg)
                    [ Cmd.map Right rightCmds
                    , outCommands
                    ] 
                )
```

Not very pretty. This kind of code is extremely error-prone, because the updating the state and accumulating commands is done manually. Most of these steps are boilerplate. Using this package, the above can be written much more succinctly as 

```elm
    Right rightMsg ->
            Gif.update rightMsg model.right
                -- add the updated child component to the model
                |> OutMessage.mapComponent (\newChild -> Model model.left newChild)
                -- map the child's commands to parent commands
                |> OutMessage.mapCmd Right
                -- Give OutMsg to effects function and a default command (for Nothing)
                |> OutMessage.evaluateMaybe interpretOutMsg Cmd.none
```

At the end of this, you are left with normal `(Model, Cmd Msg)` tuple. 

# <a name="why-not-use-msg">Why not use Msg</a>

A naive way to achieve parent-child communication is to (ab)use the child's Msg type. In the parent's update function, 
the child Msg type can be pattern matched on. When a Msg is of a certain value, the parent can take action. In the Gif example, that
could look like this: 

```elm
-- Parent.elm
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Left leftMsg ->
            let
                ( left, leftCmds ) =
                    Gif.update leftMsg model.left
                
                reportFailure = 
                    case leftMsg of 
                        FetchFail err -> Just err
                        _ -> Nothing
            in
                ( Model left model.right
                , Cmd.map Left leftCmds
                )

        Right rightMsg ->
            let
                ( right, rightCmds ) =
                    Gif.update rightMsg model.right

                reportFailure = 
                    case rightMsg of 
                        FetchFail err -> Just err
                        _ -> Nothing
            in
                ( Model model.left right
                , Cmd.map Right rightCmds
                )
```

The main problem is that this abuse of Msg does not play well with TEA. 
The purpose of Msg is clearly defined within TEA. 
Giving a Msg extra meaning will reliably confuse other elm users and may not play nicely with libraries. 
In addition, there are cases when sending an a message to the parent should not have further effects. Creating a Msg constructor for
this action will extend the child's update function with an extra pattern match that is effectively a NoOp. 



# Thanks 

This idea is not mine, and has been shaped by chats with numerous people on the elm slack channel. 



