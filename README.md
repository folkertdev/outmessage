Streamlining parent-child communication with TEA
================================================



#OutMsg 

Using OutMsg means that the update function of a child component returns a value of type OutMsg. Instead of the 
usual type:

```elm
update : ChildMsg -> ChildModel -> (ChildModel, Cmd ChildMsg)
```

Its return type is something like this. 

```elm
update : ChildMsg -> ChildModel -> (ChildModel, Cmd ChildMsg, OutMsg)
```

The `OutMsg` value is captured in the parent's update function, and handled accordingly. The basic pattern
can be extended to return multiple `OutMsg` (using `List`) or to return no `OutMsg` (using `Maybe`).

**Technical writing is hard:** If anything is unclear, please open an issue, or create a PR.

#Why this library 

As a running example, let's look at [TEA]()s Gif.

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

Now let's say that the child (an individual counter) wants to tell its parent that fetching an image has failed.  
A possibility is for the parent to pattern match on the message that it will feed to the child's update function in the parent update
function

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

This has several downsides. Abusing `Msg` for child-parent communication takes you far off the TEA path. It will seem weird to other 
Elm users. In addition, there are cases where what you want to send to the parent is not based on a message. That case would necessitate an 
empty `Msg` on the child, just so that it can be intercepted and dealt with by the parent. 


There is a better way: extending the type of `return` of the child component:

```elm
-- Counter.elm 

type OutMsg 
    = SomethingWentWrong Http.Error 

update : Msg -> Model -> (Model, Cmd Msg, Maybe OutMsg)
update msg model =
  case msg of
    MorePlease ->
      (model, getRandomGif model.topic, Nothing)

    FetchSucceed newUrl ->
      (Model model.topic newUrl, Cmd.none, Nothing)

    FetchFail err ->
      (model, Cmd.none, SomethingWentWrong err)
```

The `OutMsg` value can now be extracted by the parent

```elm
-- Parent.elm
    ( left, leftCmds, outMsg) = 
        Gif.update leftMsg model.left
```

It is likely that the `OutMsg` needs to be turned into 
a side-effect, for which we need a function of the type

```elm
interpretOutMsg : OutMsg -> Model -> (Model, Cmd Msg)
```

Notice the similarity between

* `update :             Msg -> Model -> (Model, Cmd Msg)`
* `interpretOutMsg : OutMsg -> Model -> (Model, Cmd Msg)`

A dummy interpretOutMsg could be 

```elm 
-- Parent.elm 

interpretOutMsg : OutMsg -> Model -> (Model, Cmd Msg) 
interpretOutMsg outmsg model = 
    case outmsg of 
        SomethingWentWrong err -> 
            Debug.log "A child component had an http error" (toString err) 
```
*Obviously you'd want to have more robust error handling. This is just an example*


##Wiring

The only thing that remains is wiring, but that seems to become a hairy affair very quickly. That is where this 
library comes in.

For brevity I will only work with the `Right` branch of the parent's update function. 

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

Not very pretty. This kind of code is extremely error-prone, because you have to manually update the state (your model) and accumulate the 
effects. Most of these steps are boilerplate. Using this package, the above can be written much more succinctly as 

```elm
        Right rightMsg ->
            let
                -- add the updated child component to the model
                updateModel model rightChild = 
                    Model model.left rightChild
            in 
                -- call update of the child component
                    Gif.update rightMsg model.right
                        -- map the child's commands
                        |> mapCommand Right 
                        -- OutMessage takes care of the rest
                        |> OutMessage.evaluateMaybe (updateModel model) interpretOutMsg
```

At the end of this, you are left with normal `(Model, Cmd Msg)` pair. 



#Thanks 

This idea is not mine, and has been shaped by chats with numerous people on the elm slack channel. 



