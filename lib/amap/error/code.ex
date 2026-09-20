defmodule Amap.Error.Code do
  @moduledoc """
  Maps Amap status codes to stable reason atoms.

  The two API families do not share one code table. They overlap on 24 codes
  and each has codes the other does not, so the lookup is family-aware. Only
  one code, `10021`, carries different wording per family (account-scoped
  versus IP-scoped QPS), and both normalize to `:qps_exceeded`.

  **Never branch on the numeric code.** The same number can mean different
  things in different families; `reason` is the stable key.
  """

  @shared %{
    10000 => :ok,
    10001 => :invalid_key,
    10002 => :service_not_available,
    10003 => :daily_quota_exceeded,
    10004 => :access_too_frequent,
    10005 => :invalid_user_ip,
    10006 => :invalid_user_domain,
    10007 => :invalid_user_signature,
    10008 => :invalid_user_scode,
    10009 => :userkey_plat_nomatch,
    10010 => :ip_query_over_limit,
    10011 => :not_support_https,
    10012 => :insufficient_privileges,
    10013 => :user_key_recycled,
    10014 => :qps_exceeded,
    10015 => :gateway_timeout,
    10016 => :server_is_busy,
    10017 => :resource_unavailable,
    10019 => :qps_exceeded,
    10020 => :qps_exceeded,
    20000 => :invalid_params,
    20001 => :missing_required_params,
    20002 => :illegal_request,
    20003 => :unknown_error
  }

  @restapi %{
    10021 => :qps_exceeded,
    # 10022 is deliberately absent, and not only because the Web-service table omits it.
    # The wire has carried it both ways on this family: `CGQPS_HAS_EXCEEDED_THE_LIMIT`
    # (S4's first live run, 2026-09-19) and `INVALID_PARAMS` for an over-length keyword
    # (S5's live run, 2026-09-20). `reason/2` sees only code and family, so a
    # `:qps_exceeded` entry would make the recorded parameter error retryable
    # (`:backoff`), and an `:invalid_params` entry would deny a QPS refusal its retry.
    # It falls through to `:unknown` with `retry: :no`: no wrong retry, and the caller
    # can read the wire's own `info` in `%Amap.Error{}.message`. See coverage
    # inventory §6 #7 for the decision and what it leaves unknown.
    10026 => :account_banned,
    10029 => :abroad_daily_quota_exceeded,
    10041 => :interface_privilege_expired,
    10044 => :user_daily_quota_exceeded,
    10045 => :user_abroad_daily_quota_exceeded,
    20011 => :insufficient_abroad_privileges,
    20012 => :illegal_content,
    20800 => :out_of_service_area,
    20801 => :no_roads_nearby,
    20802 => :route_fail,
    20803 => :over_direction_range,
    40000 => :quota_plan_run_out,
    40001 => :geofence_max_count_reached,
    40002 => :service_expired,
    40003 => :abroad_quota_plan_run_out
  }

  @tsapi %{
    10021 => :qps_exceeded,
    10022 => :qps_exceeded,
    10023 => :qps_exceeded,
    10024 => :insufficient_permissions,
    20004 => :id_not_found,
    20005 => :file_upload_failed,
    20006 => :invalid_binary_protocol,
    20007 => :decryption_failed,
    20008 => :request_breaker,
    20009 => :existing_element,
    20010 => :unexisting_element,
    20050 => :service_not_found,
    20051 => :terminal_not_found,
    20100 => :partial_success,
    20101 => :nothing_success,
    20150 => :beyond_limit,
    # 抓路失败 (a grasp-road/map-matching failure), documented only on the 轨迹纠偏 page.
    # The code is a v4 Web-service one, but that page's `/v4/grasproad/driving` answers the
    # Falcon envelope, so the lookup that reaches it is this family's — the envelope selects
    # the table. Deliberately not in `@retry`: Amap says the cause is the input (传入点数较少
    # 或较稀疏), so the same request fails again and `retry/1` defaults to `:no`.
    30001 => :grasproad_failed,
    32005 => :too_long_track
  }

  @retry %{
    server_is_busy: :immediate,
    resource_unavailable: :immediate,
    request_breaker: :immediate,
    engine_response_error: :immediate,
    access_too_frequent: :backoff,
    qps_exceeded: :backoff,
    gateway_timeout: :backoff
  }

  @retry_after %{access_too_frequent: 60_000}

  @engine_range 30_000..39_999

  @typedoc """
  An envelope with a numeric code table. The other two described envelopes,
  `:code_msg` and `:apilocate`, carry no numeric codes, so they are not families
  here.
  """
  @type family :: :restapi | :tsapi

  @spec reason(integer(), family()) :: atom()
  def reason(10000, _family), do: :ok

  def reason(code, family) when is_integer(code) do
    Map.get(@shared, code) ||
      Map.get(family_table(family), code) ||
      engine_reason(code)
  end

  defp family_table(:restapi), do: @restapi
  defp family_table(:tsapi), do: @tsapi

  defp engine_reason(code) do
    if code in @engine_range, do: :engine_response_error, else: :unknown
  end

  @doc """
  Whether a failure is worth retrying.

  `:backoff` means waiting is required — Amap suspends the caller for a window
  rather than rejecting one request — while `:immediate` means the same request
  can be retried straight away.
  """
  @spec retry(atom()) :: :no | :immediate | :backoff
  def retry(reason), do: Map.get(@retry, reason, :no)

  @doc "Documented suspension window for a reason, when Amap states one."
  @spec retry_after(atom()) :: pos_integer() | nil
  def retry_after(reason), do: Map.get(@retry_after, reason)
end
