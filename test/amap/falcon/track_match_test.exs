defmodule Amap.Falcon.TrackMatchTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.TrackMatch
  alias Amap.Falcon.TrackMatch.Match
  alias Amap.Falcon.TrackMatch.Track
  alias Amap.TestServer

  setup do
    server = TestServer.start!()

    client =
      Amap.new(
        key: "test-key",
        base_urls: %{
          restapi: "http://localhost:#{server.port}",
          tsapi: "http://localhost:#{server.port}"
        }
      )

    {:ok, server: server, client: client}
  end

  defp arm(server, body) do
    parent = self()

    TestServer.expect_once(server, "POST", "/v1/track/match", fn req ->
      send(parent, {:body, req.headers["content-type"], JSON.decode!(req.body)})
      {200, body}
    end)

    parent
  end

  @match_body ~s({"errcode":10000,"errmsg":"OK","data":{"matchRatio":"84.7","matchDistance":12000,"mismatchDistance":2000,"mismatchTime":1789703117430,"matchPoints":"114.1589,22.2799;114.16,22.28","baseline":{"points":"114.1589,22.2799;114.16,22.28","distance":14000},"target":{"distance":15000}}})

  test "sends a JSON body with both tracks nested", %{server: server, client: client} do
    arm(server, @match_body)

    assert {:ok, %Match{}} =
             TrackMatch.match(client, {1, 456, 20}, {1, 457, 21}, is_points: true)

    assert_receive {:body, "application/json", body}

    # Nested objects, numbers where Amap writes numbers: this is exactly what a form
    # body could not carry.
    assert body["baseline"] == %{"sid" => 1, "tid" => 456, "trid" => 20}
    assert body["target"] == %{"sid" => 1, "tid" => 457, "trid" => 21}
    assert body["isPoints"] == 1
    assert body["key"] == "test-key"
  end

  test "leaves is_points at 0 when not asked", %{server: server, client: client} do
    arm(server, @match_body)

    TrackMatch.match(client, {1, 456, 20}, {1, 457, 21})

    assert_receive {:body, _content_type, body}
    assert body["isPoints"] == 0
  end

  test "maps the verdict, keeping match_ratio as the string Amap sent", %{
    server: server,
    client: client
  } do
    arm(server, @match_body)

    assert {:ok, match} = TrackMatch.match(client, {1, 456, 20}, {1, 457, 21}, is_points: true)

    assert %Match{match_ratio: "84.7", match_distance: 12_000, mismatch_distance: 2_000} = match
    assert match.mismatch_time == 1_789_703_117_430

    assert match.match_points == [{114.1589, 22.2799}, {114.16, 22.28}]

    assert %Track{points: [{114.1589, 22.2799}, {114.16, 22.28}], distance: 14_000} =
             match.baseline

    # The target's points were not asked for, so they are absent rather than empty.
    assert %Track{points: nil, distance: 15_000} = match.target
  end

  test "reads a flat comma-separated coordinate list too, since Amap documents it that way", %{
    server: server,
    client: client
  } do
    arm(
      server,
      ~s({"errcode":10000,"errmsg":"OK","data":{"matchRatio":"50","baseline":{"points":"114.1589,22.2799,114.16,22.28","distance":1}}})
    )

    assert {:ok, %Match{baseline: %Track{points: [{114.1589, 22.2799}, {114.16, 22.28}]}}} =
             TrackMatch.match(client, {1, 456, 20}, {1, 457, 21}, is_points: true)
  end

  test "rejects a track that is not a triple, and a flag that is not a boolean", %{client: client} do
    assert_raise ArgumentError,
                 ~r/:baseline must be a \{sid, tid, trid\} tuple, got: \[1, 2\]/,
                 fn ->
                   TrackMatch.match(client, [1, 2], {1, 457, 21})
                 end

    assert_raise ArgumentError, ~r/:is_points must be a boolean, got: "yes"/, fn ->
      TrackMatch.match(client, {1, 456, 20}, {1, 457, 21}, is_points: "yes")
    end
  end

  test "an Amap error comes back as the error struct", %{server: server, client: client} do
    arm(server, ~s({"errcode":20051,"errmsg":"TERMINAL_NOT_FOUND"}))

    assert {:error, error} = TrackMatch.match(client, {1, 456, 20}, {1, 457, 21})
    assert error.reason == :terminal_not_found
  end
end
