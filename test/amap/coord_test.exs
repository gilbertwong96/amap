defmodule Amap.CoordTest do
  use ExUnit.Case, async: true

  alias Amap.Coord

  describe "parse_location/1" do
    test "parses a lon,lat string into a tuple" do
      assert Coord.parse_location("116.397428,39.90923") == {116.397428, 39.90923}
      assert Coord.parse_location("114.158,22.279") == {114.158, 22.279}
    end

    test "returns nil for anything unparseable" do
      assert Coord.parse_location(nil) == nil
      assert Coord.parse_location("not,a,point") == nil
      assert Coord.parse_location("abc,def") == nil
      assert Coord.parse_location(123) == nil
    end

    # Amap writes "no value" as an empty array, so a missing coordinate reaches
    # the mapper as a list rather than as a string.
    test "returns nil for a value that is not a string" do
      assert Coord.parse_location([]) == nil
    end
  end

  describe "parse_locations/1" do
    test "parses a semicolon-separated string into a list of tuples" do
      assert Coord.parse_locations("116.397428,39.90923;114.158,22.279") ==
               [{116.397428, 39.90923}, {114.158, 22.279}]
    end

    test "parses a single point into a one-element list" do
      assert Coord.parse_locations("116.397428,39.90923") == [{116.397428, 39.90923}]
    end

    test "returns nil when the value or any of its points is unparseable" do
      assert Coord.parse_locations(nil) == nil
      assert Coord.parse_locations("") == nil
      assert Coord.parse_locations("116.397428,39.90923;nope") == nil
      assert Coord.parse_locations([]) == nil
    end
  end

  describe "parse_polyline/1" do
    test "parses a pipe-separated boundary into one list of points per part" do
      assert Coord.parse_polyline("116.0,39.0;116.1,39.1|117.0,40.0") ==
               [[{116.0, 39.0}, {116.1, 39.1}], [{117.0, 40.0}]]
    end

    test "parses a boundary of one part into a one-element list of lists" do
      assert Coord.parse_polyline("116.0,39.0;116.1,39.1") == [[{116.0, 39.0}, {116.1, 39.1}]]
    end

    test "returns nil when the value or any part is unparseable" do
      assert Coord.parse_polyline(nil) == nil
      assert Coord.parse_polyline("116.0,39.0|nope") == nil
      assert Coord.parse_polyline(123) == nil
    end
  end
end
