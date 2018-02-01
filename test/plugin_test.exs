defmodule PluginTest do
  use ExUnit.Case

  test "can fetch a list of plugins" do
    active = [
      ReleaseManager.Plugin.Appups,
      ReleaseManager.Plugin.Consolidation,
    ] |> Enum.sort

    assert active == ReleaseManager.Plugin.load_all |> Enum.sort
  end
end
