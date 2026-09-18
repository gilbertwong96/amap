defmodule Amap.Falcon.CorrectionTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Correction

  @documented "denoise=1,mapmatch=0,attribute=0,threshold=0,mode=driving"

  describe "encode/1" do
    test "leaves the parameter out when nothing was given" do
      assert Correction.encode(nil) == nil
    end

    test "emits Amap's documented defaults, in the documented order" do
      assert Correction.encode([]) == @documented
    end

    test "turns a flag on in place, rather than appending it" do
      # The first cut used Keyword.merge, which moved an overridden key to the
      # end of the string — so the order only held when nothing was overridden.
      assert Correction.encode(mapmatch: true) ==
               "denoise=1,mapmatch=1,attribute=0,threshold=0,mode=driving"
    end

    test "sets several options at once" do
      assert Correction.encode(threshold: 20, mode: :driving) ==
               "denoise=1,mapmatch=0,attribute=0,threshold=20,mode=driving"

      assert Correction.encode(denoise: false, attribute: true) ==
               "denoise=0,mapmatch=0,attribute=1,threshold=0,mode=driving"
    end

    test "rejects a value Amap does not accept" do
      assert_raise ArgumentError, ~r/unsupported correction value for threshold: -1/, fn ->
        Correction.encode(threshold: -1)
      end

      assert_raise ArgumentError, ~r/unsupported correction value for mode: :flying/, fn ->
        Correction.encode(mode: :flying)
      end
    end

    test "rejects a key Amap does not have, rather than dropping it" do
      assert_raise ArgumentError, ~r/unknown keys \[:modee\]/, fn ->
        Correction.encode(modee: :driving)
      end
    end
  end

  describe "window!/4" do
    @now 1_700_000_000_000

    test "accepts a trace id on its own" do
      assert Correction.window!(20, nil, nil, @now) == :ok
    end

    test "accepts a window that ends now or earlier, within 24 hours" do
      assert Correction.window!(nil, @now - 60_000, @now, @now) == :ok
      assert Correction.window!(nil, @now - 24 * 3_600_000, @now, @now) == :ok
    end

    test "rejects a call that does not say what to read" do
      assert_raise ArgumentError, ~r/needs either :trid or both :starttime and :endtime/, fn ->
        Correction.window!(nil, nil, nil, @now)
      end

      assert_raise ArgumentError, ~r/needs either :trid or both/, fn ->
        Correction.window!(nil, @now - 60_000, nil, @now)
      end
    end

    test "rejects mixing a trace id with a window" do
      assert_raise ArgumentError, ~r/not both/, fn ->
        Correction.window!(20, @now - 60_000, @now, @now)
      end
    end

    test "rejects a window longer than a day, and one ending in the future" do
      assert_raise ArgumentError, ~r/may not exceed 24 hours, got 25.0 hours/, fn ->
        Correction.window!(nil, @now - 25 * 3_600_000, @now, @now)
      end

      assert_raise ArgumentError, ~r/may not end in the future/, fn ->
        Correction.window!(nil, @now, @now + 60_000, @now)
      end
    end
  end
end
