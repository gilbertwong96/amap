defmodule Amap.Error do
  @moduledoc """
  A failure from the Amap API, or from the SDK on the way there.

  Amap reports failures in the body with an HTTP 200 status, so this struct is
  the only reliable signal. Branch on `reason`, never on `code`: codes are
  family-scoped and the same number can mean different things in the Web
  service API and the Falcon track service.
  """

  alias Amap.Error.Code
  alias Amap.Host
  alias Amap.Numeric

  @filtered "[FILTERED]"
  @sensitive ~w(key private_key sig)

  defstruct code: nil,
            message: nil,
            detail: nil,
            reason: :unknown,
            family: nil,
            retry: :no,
            retry_after: nil,
            http_status: nil,
            request: %{},
            response: %{},
            raw: nil

  @typedoc """
  A response body, as far as this module can know it.

  `Amap.Response` has already matched the envelope by the time these are called,
  but what the request pipeline hands over is typed as a map, so that is what
  arrives here — named rather than written inline, so the width is a decision.
  """
  @type body :: map()

  @typedoc """
  A body that matched neither envelope.

  The clauses above have claimed everything that did, so what reaches this one is
  whatever else the pipeline produced. This is the only place in the SDK where no
  narrower type can be proved, and it is named so that stays visible.
  """
  @type unhandled_body :: any()

  @typedoc """
  A value the pipeline produced, which carries no type Dialyzer can prove.

  A transport failure arrives as whatever Finch answered with, a malformed body as
  whatever the JSON layer saw, and a `rescue` binding is untyped too. Named once
  here rather than written inline, so that the width is a stated decision.
  """
  @type runtime_value :: any()

  @typedoc """
  What the failure answered with, or what stood in for it.

  An Amap envelope when there was one — `build/5` keeps that in `raw` and leaves
  this empty — and otherwise the piece of the pipeline that broke: the exception a
  transport failure arrived as, or the body that did not parse.
  """
  @type response ::
          %{optional(String.t()) => Amap.JSON.value()}
          | %{exception: runtime_value()}
          | %{body: runtime_value()}
          | %{}

  @typedoc """
  The call that failed: its method, its path, and its parameters with credentials
  masked. A JSON array body is stored as the list it was, each element masked.
  Empty for a failure that never reached `attach_request/4`.
  """
  @type request :: %{
          optional(:method) => :get | :post,
          optional(:path) => String.t(),
          optional(:params) => Amap.JSON.object() | [Amap.JSON.object()]
        }

  @type t :: %__MODULE__{
          code: integer() | nil,
          message: String.t() | nil,
          detail: String.t() | nil,
          reason: atom(),
          family: Host.envelope() | nil,
          retry: :no | :immediate | :backoff,
          retry_after: pos_integer() | nil,
          http_status: integer() | nil,
          request: request(),
          response: response(),
          raw: body() | binary() | nil
        }

  @doc "Builds an error from a Web service envelope."
  @spec from_restapi(body(), integer() | nil) :: t()
  def from_restapi(body, http_status) do
    code = body |> Map.get("infocode") |> Numeric.to_integer()

    build(code, :restapi, http_status, body,
      message: body["info"],
      detail: nil
    )
  end

  @doc "Builds an error from a Falcon envelope."
  @spec from_tsapi(body(), integer() | nil) :: t()
  def from_tsapi(body, http_status) do
    code = body |> Map.get("errcode") |> Numeric.to_integer()

    build(code, :tsapi, http_status, body,
      message: body["errmsg"],
      detail: body["errdetail"]
    )
  end

  @doc """
  Builds an error from the 智能硬件定位 v1 envelope.

  That host has no `infocode` row — its `info` carries symbolic names such as
  `INVALID_USER_KEY` — so there is no numeric code to classify and `reason` is
  `:unknown` rather than a guess. No endpoint module uses it yet; it exists so
  the described envelope has a failure shape when one does.
  """
  @spec from_apilocate(body(), integer() | nil) :: t()
  def from_apilocate(body, http_status) do
    %__MODULE__{
      message: body["info"],
      reason: :unknown,
      family: :apilocate,
      http_status: http_status,
      raw: body
    }
  end

  @doc "Builds an error for a failure that never reached the API."
  @spec from_transport(Exception.t()) :: t()
  def from_transport(exception) do
    %__MODULE__{
      reason: :transport,
      retry: :immediate,
      response: %{exception: exception}
    }
  end

  @doc "Builds an error for a body that is not valid JSON."
  @spec invalid_json(integer() | nil, binary()) :: t()
  def invalid_json(http_status, body) do
    %__MODULE__{
      reason: :invalid_json,
      retry: :immediate,
      http_status: http_status,
      response: %{body: body}
    }
  end

  @doc "Builds an error for a body that matches neither known envelope."
  @spec unexpected_response(integer() | nil, unhandled_body()) :: t()
  def unexpected_response(http_status, body) do
    %__MODULE__{
      reason: :unexpected_response,
      retry: :no,
      http_status: http_status,
      response: %{body: body}
    }
  end

  @doc "Builds an error for a request that waited too long for a rate limit token."
  @spec limiter_timeout() :: t()
  def limiter_timeout do
    %__MODULE__{reason: :limiter_timeout, retry: :no}
  end

  @doc """
  Redacts credentials from a call's parameters: a map or keyword list, or a JSON
  array body's list of maps.

  Only the top level is walked. An array body's elements are that top level — each
  one is masked — while a value nested inside a map is left as it was sent.
  """
  @spec mask(keyword() | Amap.JSON.props() | [Amap.JSON.props()]) ::
          Amap.JSON.object() | [Amap.JSON.object()]
  def mask(params) when is_map(params), do: mask_map(params)

  def mask(params) when is_list(params) do
    if Keyword.keyword?(params) do
      mask_map(params)
    else
      Enum.map(params, &mask_element/1)
    end
  end

  defp mask_element(element) when is_map(element), do: mask_map(element)
  defp mask_element(element), do: element

  defp mask_map(params) do
    params
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.new(fn {k, v} -> if k in @sensitive, do: {k, @filtered}, else: {k, v} end)
  end

  @doc """
  Records which call failed, with credentials masked.

  `params` must be the raw parameters after `Amap.Param.encode/1`, before
  signing, so the stored copy never contains a `sig` derived from a private key.
  """
  @spec attach_request(
          t(),
          :get | :post,
          String.t(),
          keyword() | Amap.JSON.props() | [Amap.JSON.props()]
        ) :: t()
  def attach_request(%__MODULE__{} = error, method, path, params) do
    %{error | request: %{method: method, path: path, params: mask(params)}}
  end

  defp build(code, family, http_status, raw, fields) do
    reason = if is_integer(code), do: Code.reason(code, family), else: :unknown

    %__MODULE__{
      code: code,
      message: Keyword.get(fields, :message),
      detail: Keyword.get(fields, :detail),
      reason: reason,
      family: family,
      retry: Code.retry(reason),
      retry_after: Code.retry_after(reason),
      http_status: http_status,
      raw: raw
    }
  end
end
