defmodule Amap.Falcon.WireTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Wire

  describe "ids!/2" do
    test "joins ids with commas" do
      assert Wire.ids!([1, 2, 3], ":gfids") == "1,2,3"
    end

    test "passes the sentinel through" do
      assert Wire.ids!(:all, ":gfids") == "#all"
    end

    test "raises rather than letting Amap truncate a long list" do
      # Amap keeps the first 100 and answers success, so 150 would look acted on.
      assert_raise ArgumentError, ~r/:gfids must be between 1 and 100, got: 101/, fn ->
        Wire.ids!(Enum.to_list(1..101), ":gfids")
      end

      assert_raise ArgumentError, ~r/:tids must be between 1 and 100, got: 0/, fn ->
        Wire.ids!([], ":tids")
      end
    end
  end

  describe "decode_ids/1" do
    test "reads a list of ids, numbers or strings" do
      assert Wire.decode_ids([1, "2"]) == [1, 2]
    end

    test "reads the sentinel case as empty, since Amap sends nothing" do
      assert Wire.decode_ids(nil) == []
      assert Wire.decode_ids([]) == []
    end
  end

  describe "flag!/1 and decode_flag/1" do
    test "encode a boolean as Amap writes it, leaving nil absent" do
      assert Wire.flag!(true) == "1"
      assert Wire.flag!(false) == "0"
      assert Wire.flag!(nil) == nil
    end

    test "decode Amap's flag, treating a missing field as nil rather than false" do
      assert Wire.decode_flag(1) == true
      assert Wire.decode_flag(0) == false
      assert Wire.decode_flag("1") == true
      assert Wire.decode_flag("0") == false
      assert Wire.decode_flag(nil) == nil
      assert Wire.decode_flag("maybe") == nil
    end

    test "the encoding direction rejects what is not a boolean" do
      assert_raise ArgumentError, ~r/expected a boolean, got: "yes"/, fn ->
        Wire.flag!("yes")
      end
    end
  end
end
