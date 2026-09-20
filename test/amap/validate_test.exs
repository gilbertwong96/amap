defmodule Amap.ValidateTest do
  use ExUnit.Case, async: true

  alias Amap.Validate

  describe "name!/2" do
    test "accepts Chinese, letters, digits, underscore and hyphen" do
      assert Validate.name!("货车01", ":name") == "货车01"
      assert Validate.name!("truck_1-a", ":desc") == "truck_1-a"
      assert Validate.name!(String.duplicate("a", 128), ":name") == String.duplicate("a", 128)
    end

    test "raises, naming the field, for every documented rule" do
      assert_raise ArgumentError, ~r/:name must be a non-empty string/, fn ->
        Validate.name!("", ":name")
      end

      assert_raise ArgumentError, ~r/:name may not start with an underscore/, fn ->
        Validate.name!("_x", ":name")
      end

      assert_raise ArgumentError, ~r/:name must be at most 128 characters, got: 129/, fn ->
        Validate.name!(String.duplicate("a", 129), ":name")
      end

      assert_raise ArgumentError, ~r/may only contain Chinese, letters, digits/, fn ->
        Validate.name!("货车 01", ":name")
      end

      # An empty string, not nil: `optional!/3` filters nil before a validator
      # sees it, so emptiness is the shape worth pinning here.
      assert_raise ArgumentError, ~r/:desc must be a non-empty string/, fn ->
        Validate.name!("", ":desc")
      end
    end
  end

  describe "text!/2" do
    test "allows an empty string, which an update uses to clear a field" do
      assert Validate.text!("", ":desc") == ""
    end

    test "still applies the character and length rules" do
      assert Validate.text!("货车01", ":name") == "货车01"

      assert_raise ArgumentError, ~r/may not start with an underscore/, fn ->
        Validate.text!("_x", ":desc")
      end

      assert_raise ArgumentError, ~r/may only contain Chinese, letters, digits/, fn ->
        Validate.text!("a b", ":desc")
      end

      assert_raise ArgumentError, ~r/must be at most 128 characters/, fn ->
        Validate.text!(String.duplicate("a", 129), ":desc")
      end

      # Not a string is still `text!`'s own error: the clause that reads
      # `String.length/1` is guarded, so this has to stay a raised ArgumentError.
      assert_raise ArgumentError, ~r/:desc must be a string/, fn ->
        Validate.text!(1, ":desc")
      end
    end
  end

  describe "optional_enum!/3" do
    test "returns the wire string for a documented value" do
      assert Validate.optional_enum!(:base, ":extensions", [:base, :all]) == "base"
      assert Validate.optional_enum!(:all, ":extensions", [:base, :all]) == "all"
    end

    test "treats nil as absent" do
      assert Validate.optional_enum!(nil, ":extensions", [:base, :all]) == nil
    end

    test "raises, naming the allowed values, for anything else" do
      assert_raise ArgumentError,
                   ~r/:extensions must be one of \[:base, :all\], got: :full/,
                   fn -> Validate.optional_enum!(:full, ":extensions", [:base, :all]) end

      assert_raise ArgumentError,
                   ~r/:coordsys must be one of \[:gps\], got: "gps"/,
                   fn -> Validate.optional_enum!("gps", ":coordsys", [:gps]) end
    end
  end

  describe "point!/2 and points!/2" do
    test "accepts pairs of numbers, and a list of them" do
      assert Validate.point!({116.48, 39.99}, ":location") == {116.48, 39.99}
      assert Validate.point!({116, 39}, ":location") == {116, 39}

      assert Validate.points!([{116.48, 39.99}, {114.15, 22.27}], ":locations") ==
               [{116.48, 39.99}, {114.15, 22.27}]
    end

    test "raises for anything Amap would not read as a coordinate" do
      assert_raise ArgumentError,
                   ~r/:location must be a \{lon, lat\} pair of numbers, got: \[116.48, 39.99\]/,
                   fn ->
                     Validate.point!([116.48, 39.99], ":location")
                   end

      assert_raise ArgumentError,
                   ~r/:locations must be a non-empty list of \{lon, lat\} pairs/,
                   fn ->
                     Validate.points!([], ":locations")
                   end

      assert_raise ArgumentError,
                   ~r/:locations must be a \{lon, lat\} pair of numbers, got: "116.48,39.99"/,
                   fn ->
                     Validate.points!(["116.48,39.99"], ":locations")
                   end
    end
  end

  describe "range!/4" do
    test "accepts the documented interval" do
      assert Validate.range!(500, ":radius", 1, 5000) == 500
      assert Validate.range!(1, ":pagesize", 1, 100) == 1
    end

    test "raises outside it" do
      assert_raise ArgumentError, ~r/:radius must be between 1 and 5000, got: 0/, fn ->
        Validate.range!(0, ":radius", 1, 5000)
      end

      assert_raise ArgumentError, ~r/:pagesize must be between 1 and 100, got: 101/, fn ->
        Validate.range!(101, ":pagesize", 1, 100)
      end

      assert_raise ArgumentError, ~r/:radius must be an integer, got: "500"/, fn ->
        Validate.range!("500", ":radius", 1, 5000)
      end
    end
  end

  describe "optional!/3" do
    test "passes a given value to the validator" do
      assert Validate.optional!(&Validate.name!/2, "货车01", ":desc") == "货车01"
    end

    test "treats nil as absent rather than as a value to check" do
      assert Validate.optional!(&Validate.name!/2, nil, ":desc") == nil
    end
  end

  describe "optional_present!/2" do
    test "passes a non-empty string through and treats nil as absent" do
      assert Validate.optional_present!("B000A7BD6C", ":origin_id") == "B000A7BD6C"
      assert Validate.optional_present!(nil, ":origin_id") == nil
    end

    test "refuses an empty string, which is not an id Amap can use" do
      assert_raise ArgumentError, ~r/:city must be a non-empty string/, fn ->
        Validate.optional_present!("", ":city")
      end
    end

    test "applies present!'s own rules rather than the Falcon charset" do
      # A plate has no letters-and-digits-only rule, and `/` is not in `text!`'s charset.
      assert Validate.optional_present!("京AHA322", ":plate") == "京AHA322"
      assert Validate.optional_present!("a/b", ":filter") == "a/b"
    end
  end

  describe "optional_boolean!/3" do
    test "writes the form the endpoint takes" do
      assert Validate.optional_boolean!(true, ":nosteps", as: :int) == "1"
      assert Validate.optional_boolean!(false, ":nosteps", as: :int) == "0"
      assert Validate.optional_boolean!(true, ":roadaggregation", as: :bool) == "true"
      assert Validate.optional_boolean!(false, ":roadaggregation", as: :bool) == "false"
    end

    test "treats nil as absent" do
      assert Validate.optional_boolean!(nil, ":nosteps", as: :int) == nil
    end

    test "raises for a value that is neither boolean, naming the field" do
      assert_raise ArgumentError, ~r/:isindoor must be a boolean, got: 1/, fn ->
        Validate.optional_boolean!(1, ":isindoor", as: :int)
      end
    end
  end

  describe "integer_one_of!/3" do
    test "returns the number for a documented value" do
      assert Validate.integer_one_of!(32, ":strategy", [0, 1, 2] ++ Enum.to_list(32..45)) == 32
      assert Validate.integer_one_of!(3, ":type", [0, 1, 3]) == 3
    end

    test "treats nil as absent" do
      assert Validate.integer_one_of!(nil, ":strategy", [1, 2, 3]) == nil
    end

    test "raises, naming the allowed values, for anything else" do
      assert_raise ArgumentError, ~r/:strategy must be one of \[1, 2, 3\], got: 4/, fn ->
        Validate.integer_one_of!(4, ":strategy", [1, 2, 3])
      end

      assert_raise ArgumentError, ~r/:type must be one of \[0, 1, 3\], got: "1"/, fn ->
        Validate.integer_one_of!("1", ":type", [0, 1, 3])
      end
    end
  end

  describe "optional_show_fields!/3" do
    @groups [:cost, :navi, :walk_type]

    test "comma-joins the groups and treats nil as absent" do
      assert Validate.optional_show_fields!(nil, ":show_fields", @groups) == nil

      assert Validate.optional_show_fields!([:cost, :navi], ":show_fields", @groups) ==
               "cost,navi"
    end

    test "raises, naming the unknown groups, for a group this endpoint lacks" do
      assert_raise ArgumentError,
                   ~r/:show_fields must be a subset of \[:cost, :navi, :walk_type\], got unknown: \[:typo\]/,
                   fn ->
                     Validate.optional_show_fields!([:cost, :typo], ":show_fields", @groups)
                   end
    end

    test "raises for an empty list and for a value that is not a list" do
      assert_raise ArgumentError, ~r/:show_fields must be a non-empty list of/, fn ->
        Validate.optional_show_fields!([], ":show_fields", @groups)
      end

      assert_raise ArgumentError, ~r/:show_fields must be a non-empty list of/, fn ->
        Validate.optional_show_fields!(:cost, ":show_fields", @groups)
      end
    end
  end
end
