defmodule Amap.SignatureTest do
  use ExUnit.Case, async: true

  # Values from the official FAQ example:
  # https://lbs.amap.com/faq/quota-key/key/41181/
  test "matches the official example" do
    params = [{"a", "23"}, {"b", "12"}, {"d", "48"}, {"f", "8"}, {"c", "67"}]

    assert Amap.Signature.sign(params, "bbbbb") ==
             "a89e8c2266d888860c46672d77d069f3"
  end

  test "sorts by parameter name ascending" do
    sorted = Amap.Signature.sign([{"b", "2"}, {"a", "1"}], "k")
    reversed = Amap.Signature.sign([{"a", "1"}, {"b", "2"}], "k")

    assert sorted == reversed
  end

  test "returns lowercase hex" do
    sig = Amap.Signature.sign([{"a", "1"}], "k")

    assert sig == String.downcase(sig)
    assert String.length(sig) == 32
  end

  test "signs raw values without url-encoding them" do
    # A space must be signed as a space, matching md5("q=a b" <> "k").
    expected = Base.encode16(:erlang.md5("q=a bk"), case: :lower)

    assert Amap.Signature.sign([{"q", "a b"}], "k") == expected
  end

  test "treats a plus sign literally" do
    expected = Base.encode16(:erlang.md5("q=a+bk"), case: :lower)

    assert Amap.Signature.sign([{"q", "a+b"}], "k") == expected
  end

  test "ignores an existing sig parameter" do
    with_sig = Amap.Signature.sign([{"a", "1"}, {"sig", "stale"}], "k")
    without_sig = Amap.Signature.sign([{"a", "1"}], "k")

    assert with_sig == without_sig
  end

  test "signs multibyte values as UTF-8 bytes" do
    expected = Base.encode16(:erlang.md5("name=北京k"), case: :lower)

    assert Amap.Signature.sign([{"name", "北京"}], "k") == expected
  end
end
