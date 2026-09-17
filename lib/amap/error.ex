defmodule Amap.Error do
  @moduledoc """
  A failure from the Amap API, or from the SDK on the way there.

  Amap reports failures in the body with an HTTP 200 status, so this struct is
  the only reliable signal. Branch on `reason`, never on `code`: codes are
  family-scoped and the same number can mean different things in the Web
  service API and the Falcon track service.
  """

  alias Amap.Error.Code

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

  @type t :: %__MODULE__{
          code: integer() | nil,
          message: String.t() | nil,
          detail: String.t() | nil,
          reason: atom(),
          family: Amap.Client.family() | nil,
          retry: :no | :immediate | :backoff,
          retry_after: pos_integer() | nil,
          http_status: integer() | nil,
          request: map(),
          response: map(),
          raw: map() | nil
        }

  @doc "Builds an error from a Web service envelope."
  @spec from_restapi(map(), integer() | nil) :: t()
  def from_restapi(body, http_status) do
    code = body |> Map.get("infocode") |> to_integer()

    build(code, :restapi, http_status, body,
      message: body["info"],
      detail: nil
    )
  end

  @doc "Builds an error from a Falcon envelope."
  @spec from_tsapi(map(), integer() | nil) :: t()
  def from_tsapi(body, http_status) do
    code = body |> Map.get("errcode") |> to_integer()

    build(code, :tsapi, http_status, body,
      message: body["errmsg"],
      detail: body["errdetail"]
    )
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
  @spec unexpected_response(integer() | nil, term()) :: t()
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

  @doc "Redacts credentials from a parameter map."
  @spec mask(keyword() | map()) :: map()
  def mask(params) do
    params
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.new(fn {k, v} -> if k in @sensitive, do: {k, @filtered}, else: {k, v} end)
  end

  @doc """
  Records which call failed, with credentials masked.

  `params` must be the raw parameters after `Amap.Param.encode/1`, before
  signing, so the stored copy never contains a `sig` derived from a private key.
  """
  @spec attach_request(t(), :get | :post, String.t(), keyword() | map()) :: t()
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

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_integer(_), do: nil
end
