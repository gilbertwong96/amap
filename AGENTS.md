# AGENTS.md

Conventions this repository holds itself to. They are enforced in review, and where a
tool can check them, by `mix ci`.

## Types: name every shape

A `@spec` is a promise, and its value is in how much it rules out. This library talks to
one API and knows the shape of nearly everything it handles, so a broad type is almost
always a missed narrowing rather than an honest description.

**Never write, in a spec or in a struct's field type:**

| Don't | Write instead |
|---|---|
| `map()` | the shape itself: `%{String.t() => String.t()}`, a named `row()`, a JSON value |
| `struct()` | the struct: `%Amap.Falcon.TerminalColumn{}`, `__MODULE__.t()` |
| `module()` | the modules actually passed, or a callback type that says what it returns |
| `any()`, `term()` | a named union of what can really arrive — see below |

**`term()` and `any()` are the worst of those**, because they read as "I did not look",
and a reader cannot tell a deliberate one from a lazy one. There is exactly one
legitimate use — a total parser or validator, whose whole job is to survive whatever a
call site passed and answer `nil` or raise — and even there the answer is to name the
union once, with a `@typedoc` that says why it is that wide:

```elixir
@typedoc """
A value a call site may pass as a parameter: what can be written in Elixir, which is
exactly what a validator has to survive.
"""
@type input :: String.t() | number() | boolean() | atom() | tuple() | nil | [input()]
```

```elixir
@typedoc "A value a decoded payload can carry, which is all a parser ever sees."
@type json_value ::
        String.t() | number() | boolean() | nil | [json_value()] | %{optional(String.t()) => json_value()}
```

**A helper that maps rows into a struct it does not own gives up its specificity.**
Either it returns the rows, narrowly typed, and the module that owns the struct maps
them — or it takes a callback and promises what the callback returns. What it must not
do is promise `struct()` and leave the caller to find out which struct:

```elixir
# Amap.Falcon.Column: the rows are Amap's, so name/type is all this can promise.
@type row :: %{String.t() => String.t()}
@spec list(Amap.Client.t(), String.t(), integer()) :: {:ok, [row()]} | {:error, Amap.Error.t()}

# Amap.Falcon.Columns: generated into a module that knows its own struct.
@spec list(Amap.Client.t(), integer()) :: {:ok, [__MODULE__.t()]} | {:error, Amap.Error.t()}
```

**When a macro generates a function, the spec goes inside the `quote` and names
`__MODULE__.t()`.** The generated function belongs to the module it lands in, and that
module is the only place where its concrete type is known.
