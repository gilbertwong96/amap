defmodule Amap.Error.CodeTest do
  use ExUnit.Case, async: true

  @fixture "test/fixtures/error_codes.json" |> File.read!() |> JSON.decode!()

  defp table(family) do
    @fixture["shared"] |> Map.merge(@fixture["divergent"]) |> Map.merge(@fixture[family])
  end

  describe "reason/2 completeness" do
    for family <- [:restapi, :tsapi] do
      test "every #{family} code has an explicit reason" do
        codes = table(unquote(to_string(family)))

        for {code, expected} <- codes do
          code = String.to_integer(code)
          reason = Amap.Error.Code.reason(code, unquote(family))

          assert reason == String.to_atom(expected),
                 "code #{code} mapped to #{inspect(reason)}, expected #{expected}"
        end
      end

      test "#{family}-only codes do not resolve for the other family" do
        other = if unquote(family) == :restapi, do: :tsapi, else: :restapi

        for code <- Map.keys(@fixture[unquote(to_string(family))]) do
          code = String.to_integer(code)

          assert Amap.Error.Code.reason(code, unquote(family)) != :unknown

          if code in 30_000..39_999 do
            # The Web service API documents the whole 3xxxx block generically as
            # engine errors, so a Falcon-specific 32005 still resolves there.
            assert Amap.Error.Code.reason(code, other) == :engine_response_error
          else
            assert Amap.Error.Code.reason(code, other) == :unknown
          end
        end
      end
    end
  end

  describe "reason/2 specifics" do
    test "10021 diverges in wording but normalizes to the same reason" do
      assert Amap.Error.Code.reason(10021, :restapi) == :qps_exceeded
      assert Amap.Error.Code.reason(10021, :tsapi) == :qps_exceeded
    end

    test "unknown codes fall through to :unknown" do
      assert Amap.Error.Code.reason(99_999, :restapi) == :unknown
      assert Amap.Error.Code.reason(99_999, :tsapi) == :unknown
    end

    test "specific codes win over the engine range on tsapi" do
      # 32005 is a documented Falcon code, while 3xxxx generally means an engine error.
      assert Amap.Error.Code.reason(32005, :tsapi) == :too_long_track
    end

    test "30001 is the grasp-road failure, looked up by the family that answers it" do
      assert Amap.Error.Code.reason(30_001, :tsapi) == :grasproad_failed
      # The code belongs to the v4 Web-service generation, but the envelope selects
      # the table: `/v4/grasproad/driving` is parsed as Falcon, and no flat-envelope
      # page documents 30001. On restapi it still falls through to the engine range.
      assert Amap.Error.Code.reason(30_001, :restapi) == :engine_response_error
    end

    test "the engine range covers unlisted 3xxxx codes" do
      assert Amap.Error.Code.reason(30_001, :restapi) == :engine_response_error
      assert Amap.Error.Code.reason(32_203, :tsapi) == :engine_response_error
    end
  end

  describe "retry/1" do
    test "classifies transient failures as immediate retries" do
      assert Amap.Error.Code.retry(:server_is_busy) == :immediate
      assert Amap.Error.Code.retry(:resource_unavailable) == :immediate
      assert Amap.Error.Code.retry(:engine_response_error) == :immediate
    end

    test "classifies quota failures as backoff retries" do
      assert Amap.Error.Code.retry(:access_too_frequent) == :backoff
      assert Amap.Error.Code.retry(:qps_exceeded) == :backoff
      assert Amap.Error.Code.retry(:gateway_timeout) == :backoff
    end

    test "refuses to retry configuration and parameter failures" do
      for reason <- [
            :invalid_key,
            :service_not_available,
            :invalid_params,
            :missing_required_params,
            :no_roads_nearby,
            :grasproad_failed
          ] do
        assert Amap.Error.Code.retry(reason) == :no
      end
    end

    test "defaults unknown reasons to no retry" do
      assert Amap.Error.Code.retry(:unknown) == :no
    end
  end

  describe "retry_after/1" do
    test "reports the one minute suspension Amap documents for 10004" do
      assert Amap.Error.Code.retry_after(:access_too_frequent) == 60_000
    end

    test "is nil when Amap documents no suspension window" do
      assert Amap.Error.Code.retry_after(:qps_exceeded) == nil
      assert Amap.Error.Code.retry_after(:invalid_key) == nil
    end
  end
end
