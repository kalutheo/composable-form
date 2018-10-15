module Form.Base exposing
    ( Form
    , field, FieldConfig, custom, FilledField
    , succeed, append, andThen, optional, meta
    , map, mapValues, mapField
    , FilledForm, fill
    )

{-| Build composable forms with your own custom fields.

This is the **base** of the `composable-form` package. It implements a composable [`Form`](#Form)
type that is not tied to any particular `field`.

In order to understand this module, you should be familar with [the basic `Form module`](Form)
first.


# Definition

@docs Form


# Custom fields

Say you need to use a type of field that is not implemented in the [the basic `Form module`](Form).
The recommended way of doing this is to copy [the source code of the basic `Form` module][form-source]
into your own `MyProject.Form` module, and then use [`field`](#field) and [`custom`](#custom) to
define new types of fields.

[form-source]: https://github.com/hecrj/composable-form/tree/master/src/Form.elm

While copy-pasting code might sound like a bad idea, keep in mind that
[the basic `Form module`](Form) does not contain much code at all! It is just a bunch of one-liners
that delegate to this base module. It is the perfect template to build your own form.

If that still does not convince you, you could start your own `MyProject.Form` module like this:

    import Form.Base as Base

    type alias Form values output =
        Base.Form values output (Field values)

    type Field values
        = None

    succeed : output -> Form values output
    succeed =
        Base.succeed

    -- Other useful operations you will probably want to use,
    -- like append, andThen...

Notice that we could avoid redefining `succeed`, `append`, and others, but that would force us to
import `Form.Base` every time we needed to use those operations with our brand new form.

@docs field, FieldConfig, custom, FilledField


# Composition

@docs succeed, append, andThen, optional, meta


# Mapping

@docs map, mapValues, mapField


# Output

@docs FilledForm, fill

-}

import Form.Error as Error exposing (Error)
import Form.Field exposing (Field)


{-| A [`Form`](Form#Form) that can contain any type of `field`.
-}
type Form values output field
    = Form (values -> FilledForm output field)



-- Custom fields


{-| Most form fields require configuration! `FieldConfig` allows you to specify how a
concrete field is validated and updated, alongside its attributes:

  - `parser` must be a function that validates the `input` of the field and produces a `Result`
    of either:
      - the correct `output`
      - a `String` describing a problem
  - `value` defines how the value of the field is obtained from the form `values`
  - `update` defines how the current form `values` should be updated with a new field value
  - `attributes` represent the attributes of the field

-}
type alias FieldConfig attrs input values output =
    { parser : input -> Result String output
    , value : values -> input
    , update : input -> values -> values
    , attributes : attrs
    }


{-| Create functions that build forms that contain a single field with an API that is similar to
[the basic `Form` module](Form).

This function is meant to be partially applied, providing only the two first parameters to
obtain a function that expects the configuration for a particular type of field. See
[`FieldConfig`](#FieldConfig).

For this, you only need to provide:

  - A function that given the `input` of the field tells whether it is empty or not.
  - A function that maps a generic [`Field`](Field#Field) to your own specific `field` type.

For example, [`Form.textField`](Form#textField) could be implemented like this:

    textField :
        { parser : String -> Result String output
        , value : values -> String
        , update : String -> values -> values
        , attributes : TextField.Attributes
        }
        -> Form values output
    textField =
        Base.field { isEmpty = String.isEmpty } (Text TextRaw)

Notice how the configuration record in `textField` is a [`FieldConfig`](#FieldConfig).

**Note:** You can use [`TextField.form`](Form-Base-TextField#form),
[`SelectField.form`](Form-Base-SelectField#form), and others to build fields that are already
present in [`Form`](Form).

-}
field :
    { isEmpty : input -> Bool }
    -> (Field attributes input values -> field)
    -> FieldConfig attributes input values output
    -> Form values output field
field { isEmpty } build config =
    let
        requiredParser value =
            if isEmpty value then
                Err ( Error.RequiredFieldIsEmpty, [] )

            else
                config.parser value
                    |> Result.mapError (\error -> ( Error.ValidationFailed error, [] ))

        parse =
            config.value >> requiredParser

        field_ values =
            let
                value =
                    config.value values

                update newValue =
                    config.update newValue values
            in
            build
                { value = value
                , update = update
                , attributes = config.attributes
                }
    in
    Form
        (\values ->
            let
                result =
                    parse values

                ( error, isEmpty_ ) =
                    case result of
                        Ok _ ->
                            ( Nothing, False )

                        Err ( firstError, _ ) ->
                            ( Just firstError, firstError == Error.RequiredFieldIsEmpty )
            in
            { fields = [ ( field_ values, error ) ]
            , result = result
            , isEmpty = isEmpty_
            }
        )


{-| Represents a field on a form that has been filled with values.

It contains:

  - a field
  - the result of the field
  - whether the field is empty or not

-}
type alias FilledField output field =
    { field : field
    , result : Result ( Error, List Error ) output
    , isEmpty : Bool
    }


{-| Create a custom field with total freedom.

You only need to provide a function that given some `values` produces a [`FilledField`](#FilledField).

You can check the [custom fields example][custom-fields] for some inspiration.

[custom-fields]: https://hecrj.github.io/composable-form/#/custom-fields

-}
custom : (values -> FilledField output field) -> Form values output field
custom fillField =
    Form
        (\values ->
            let
                filled =
                    fillField values
            in
            { fields =
                [ ( filled.field
                  , case filled.result of
                        Ok _ ->
                            Nothing

                        Err ( firstError, _ ) ->
                            Just firstError
                  )
                ]
            , result = filled.result
            , isEmpty = filled.isEmpty
            }
        )



-- Composition


{-| Like [`Form.succeed`](Form#succeed) but not tied to a particular type of `field`.
-}
succeed : output -> Form values output field
succeed output =
    Form (always { fields = [], result = Ok output, isEmpty = True })


{-| Like [`Form.append`](Form#append) but not tied to a particular type of `field`.
-}
append : Form values a field -> Form values (a -> b) field -> Form values b field
append new current =
    Form
        (\values ->
            let
                filledNew =
                    fill new values

                filledCurrent =
                    fill current values

                fields =
                    filledCurrent.fields ++ filledNew.fields

                isEmpty =
                    filledCurrent.isEmpty && filledNew.isEmpty
            in
            case filledCurrent.result of
                Ok fn ->
                    { fields = fields
                    , result = Result.map fn filledNew.result
                    , isEmpty = isEmpty
                    }

                Err (( firstError, otherErrors ) as errors) ->
                    case filledNew.result of
                        Ok _ ->
                            { fields = fields
                            , result = Err errors
                            , isEmpty = isEmpty
                            }

                        Err ( newFirstError, newOtherErrors ) ->
                            { fields = fields
                            , result =
                                Err
                                    ( firstError
                                    , otherErrors ++ (newFirstError :: newOtherErrors)
                                    )
                            , isEmpty = isEmpty
                            }
        )


{-| Like [`Form.andThen`](Form#andThen) but not tied to a particular type of `field`.
-}
andThen : (a -> Form values b field) -> Form values a field -> Form values b field
andThen child parent =
    Form
        (\values ->
            let
                filled =
                    fill parent values
            in
            case filled.result of
                Ok output ->
                    let
                        childFilled =
                            fill (child output) values
                    in
                    { fields = filled.fields ++ childFilled.fields
                    , result = childFilled.result
                    , isEmpty = filled.isEmpty && childFilled.isEmpty
                    }

                Err errors ->
                    { fields = filled.fields
                    , result = Err errors
                    , isEmpty = filled.isEmpty
                    }
        )


{-| Like [`Form.optional`](Form#optional) but not tied to a particular type of `field`.
-}
optional : Form values output field -> Form values (Maybe output) field
optional form =
    Form
        (\values ->
            let
                filled =
                    fill form values
            in
            case filled.result of
                Ok value ->
                    { fields = filled.fields
                    , result = Ok (Just value)
                    , isEmpty = filled.isEmpty
                    }

                Err ( firstError, otherErrors ) ->
                    if filled.isEmpty then
                        { fields = List.map (\( field_, _ ) -> ( field_, Nothing )) filled.fields
                        , result = Ok Nothing
                        , isEmpty = True
                        }

                    else
                        { fields = filled.fields
                        , result = Err ( firstError, otherErrors )
                        , isEmpty = False
                        }
        )


{-| Like [`Form.meta`](Form#meta) but not tied to a particular type of `field`.
-}
meta : (values -> Form values output field) -> Form values output field
meta fn =
    Form (\values -> fill (fn values) values)



-- Mapping


{-| Like [`Form.map`](Form#map) but not tied to a particular type of `field`.
-}
map : (a -> b) -> Form values a field -> Form values b field
map fn form =
    Form
        (\values ->
            let
                filled =
                    fill form values
            in
            { fields = filled.fields
            , result = Result.map fn filled.result
            , isEmpty = filled.isEmpty
            }
        )


{-| Apply a function to the input `values` of the form.
-}
mapValues : (a -> b) -> Form b output field -> Form a output field
mapValues fn form =
    Form (fn >> fill form)


{-| Apply a function to each form `field`.
-}
mapField : (a -> b) -> Form values output a -> Form values output b
mapField fn form =
    Form
        (\values ->
            let
                filled =
                    fill form values
            in
            { fields = List.map (\( field_, error ) -> ( fn field_, error )) filled.fields
            , result = filled.result
            , isEmpty = filled.isEmpty
            }
        )



-- Output


{-| Represents a filled form.

You can obtain this by using [`fill`](#fill).

-}
type alias FilledForm output field =
    { fields : List ( field, Maybe Error )
    , result : Result ( Error, List Error ) output
    , isEmpty : Bool
    }


{-| Like [`Form.fill`](Form#fill) but not tied to a particular type of `field`.
-}
fill : Form values output field -> values -> FilledForm output field
fill (Form fill_) =
    fill_
