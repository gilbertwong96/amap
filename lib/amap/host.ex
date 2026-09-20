defmodule Amap.Host do
  @moduledoc """
  What each Amap host looks like on the wire.

  A host used to be described by a base URL plus one of two families, and the
  family decided both the response envelope and whether the request was signed.
  The evidence says the axes move independently: the `/v4/` generation on
  `restapi.amap.com` answers the Falcon envelope (`errcode`/`errmsg`/`errdetail`
  around `data`) and documents no signature, and two further hosts answer
  envelopes and auth the SDK never had a name for. So each host states its four
  axes here — its base URL, the envelope it answers, how it authenticates, and
  what it calls the account key — and the request path reads them rather than
  inferring one axis from another.

  A host may answer more than one envelope, with different auth: `:restapi`
  answers the flat `status`/`info`/`infocode` envelope, signed, and the
  `/v4/` generation's Falcon envelope, key only. `describe/2` resolves a host
  and, when the endpoint's envelope is not the host's default, that envelope, to
  the axes one request needs.

  The two further described hosts differ in what is missing:

    * `:et_api` (交通事件) cannot be called: it authenticates with `clientKey` +
      `timestamp` + `digest`, and Amap publishes the digest algorithm only with
      the commercial grant — `Amap.Request` describes the shape but refuses to
      build it;
    * `:apilocate` (智能硬件定位 v1) can be called through `Amap.request/6` —
      plain `key=`, no `sig` — and its envelope (no `infocode` row, symbolic
      `info` values) parses, but no endpoint module uses it.
  """

  @enforce_keys [:name, :base_url, :envelope, :auth, :key_param]
  defstruct [:name, :base_url, :envelope, :auth, :key_param]

  @typedoc "A host the SDK describes."
  @type name :: :restapi | :tsapi | :et_api | :apilocate

  @typedoc """
  A response envelope: the key set that wraps a payload. `:code_msg` is
  described because its shape (code + msg + data) is on the page, but it is not
  parsed the way the others are — the page does not say which `code` means
  success, so `Amap.Response` refuses to guess.
  """
  @type envelope :: :restapi | :tsapi | :code_msg | :apilocate

  @typedoc """
  How a request presents the account.

    * `:signature` — the key parameter, plus a `sig` over the parameters and the
      client's private key when one is configured;
    * `:key_only` — the key parameter and nothing else;
    * `:digest` — `clientKey` with a `timestamp` and a `digest` derived from a
      key Amap hands out with the commercial grant. The algorithm is not public,
      so a request requiring it can be described but not built.
  """
  @type auth :: :signature | :key_only | :digest

  @type t :: %__MODULE__{
          name: name(),
          base_url: String.t(),
          envelope: envelope(),
          auth: auth(),
          key_param: String.t()
        }

  # The evidence for each row is the per-host pages checked on 2026-09-18.
  @hosts %{
    restapi: %{
      base_url: "https://restapi.amap.com",
      key_param: "key",
      default: :restapi,
      envelopes: %{restapi: :signature, tsapi: :key_only}
    },
    tsapi: %{
      base_url: "https://tsapi.amap.com",
      key_param: "key",
      default: :tsapi,
      envelopes: %{tsapi: :key_only}
    },
    et_api: %{
      base_url: "https://et-api.amap.com",
      key_param: "clientKey",
      default: :code_msg,
      envelopes: %{code_msg: :digest}
    },
    apilocate: %{
      base_url: "https://apilocate.amap.com",
      key_param: "key",
      default: :apilocate,
      envelopes: %{apilocate: :key_only}
    }
  }

  @names @hosts |> Map.keys() |> Enum.sort()

  @doc "Every host this SDK describes."
  @spec names() :: [name()]
  def names, do: @names

  @doc """
  The default base URL of each host.

  A client carries a copy so a caller can point one at a proxy or a test
  server; this is where the defaults come from.
  """
  @spec default_base_urls() :: %{name() => String.t()}
  def default_base_urls, do: Map.new(@hosts, fn {name, host} -> {name, host.base_url} end)

  @doc """
  Resolves a host, and the envelope the endpoint answers when it is not the
  host's default, to the four axes a request needs.

  Raises `ArgumentError` for a host this SDK does not describe and for an
  envelope the host does not answer — both are combinations the evidence does
  not support, so there is no fallback.
  """
  @spec describe(name(), envelope() | nil) :: t()
  def describe(host, envelope \\ nil) do
    declared =
      Map.get(@hosts, host) ||
        raise ArgumentError,
              "invalid host: #{inspect(host)}; expected one of #{inspect(@names)}"

    envelope = envelope || declared.default

    auth =
      Map.get(declared.envelopes, envelope) ||
        raise ArgumentError,
              "invalid envelope: #{inspect(envelope)} for the #{inspect(host)} host; " <>
                "it answers #{inspect(declared.envelopes |> Map.keys() |> Enum.sort())}"

    %__MODULE__{
      name: host,
      base_url: declared.base_url,
      envelope: envelope,
      auth: auth,
      key_param: declared.key_param
    }
  end
end
