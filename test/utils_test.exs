defmodule UtilsTest do
  use ExUnit.Case, async: true
  use Bitwise, only_operators: true

  import PathHelpers

  alias ReleaseManager.Utils

  @example_app_path fixture_path("example_app")
  @old_path         fixture_path("configs/old_relx.config")
  @new_path         fixture_path("configs/new_relx.config")
  @expected_path    fixture_path("configs/merged_relx.config")

  defmacrop with_app(body) do
    quote do
      cwd = File.cwd!
      File.cd! @example_app_path
      unquote(body)
      File.cd! cwd
    end
  end

  test "can merge two relx.config files" do
    old      = @old_path |> Utils.read_terms
    new      = @new_path |> Utils.read_terms
    expected = @expected_path |> Utils.read_terms

    merged = Utils.merge(old, new)

    assert expected == merged
  end

  test "can read terms from string" do
    config   = @expected_path |> File.read!
    expected = @expected_path |> Utils.read_terms

    terms    = Utils.string_to_terms(config)

    assert expected == terms
  end

  test "can run a function in a specific Mix environment" do
    execution_env = Utils.with_env :prod, fn -> Mix.env end
    assert :prod = execution_env
  end

  test "can load the current project configuration for a given environment" do
    with_app do
      [test: config] = Utils.load_config(:prod)
      assert List.keymember?(config, :foo, 0)
    end
  end

  test "can load the current project configuration from project's specified location" do
    project_config = [config_path: "config/explicit_config.exs"]
    with_app do
      [test: config] = Utils.load_config(:prod, project_config)
      assert Keyword.fetch!(config, :foo) == :explicit
    end
  end

  test "can invoke mix to perform a task for a given environment" do
    with_app do
      assert :ok = Utils.mix("clean", :prod)
    end
  end

  test "can get the current elixir library path" do
    elixir_path = Utils.get_elixir_lib_paths |> Enum.filter(&(String.ends_with?("/elixir/ebin", &1)))
    path        = Path.join(elixir_path, "../bin/elixir")
    {result, _} = System.cmd(path, ["--version"])
    version     = result |> String.trim()
    assert String.contains?(version, "Elixir #{System.version}")
  end

  @tag :expensive
  @tag timeout: 120000 # 120s
  test "can build a release and boot it up" do
    with_app do
      #capture_io(fn ->
        # Build release
        assert :ok = Utils.mix("do deps.get, compile", Mix.env, :quiet)
        assert :ok = Utils.mix("release --no-confirm-missing --verbosity=verbose", Mix.env, :verbose)
        assert [{"test", "0.0.1"}] == Utils.get_releases("test")
        # Boot it, ping it, and shut it down
        bin_path = Path.join([File.cwd!, "rel", "test", "bin", "test"])
        assert {_, 0}      = System.cmd(bin_path, ["start"])
        :timer.sleep(1000) # Required, since starting up takes a sec
        assert {result, 0} = System.cmd(bin_path, ["ping"])
        assert String.contains?(result, "pong")
        assert {result, 0} = System.cmd(bin_path, ["stop"])
        assert String.contains?(result, "ok")
        sys_config_path = Path.join([File.cwd!, "rel", "test", "running-config", "sys.config"])
        {res, sysconfig_content} = :file.consult(to_charlist(sys_config_path))
        assert :ok = res
        some_val = Keyword.get(List.first(sysconfig_content), :test) |> Keyword.get(:some_val)
        assert 101 = some_val
        sys_config_rel_path = Path.join([File.cwd!, "rel", "test", "releases", "0.0.1", "sys.config"])
         {:ok, info } = File.stat(sys_config_rel_path)
         assert (info.mode &&& 0o0777) == 0o600
      #end)
    end
  end

  test "can compare semver versions" do
    assert ["1.0.10"|_] = Utils.sort_versions(["1.0.1", "1.0.2", "1.0.9", "1.0.10"])
  end

  test "can compare non-semver versions" do
    assert ["1.3", "1.2", "1.1"] = Utils.sort_versions(["1.1", "1.3", "1.2"])
  end

  test "can compare complex versions" do
    expected = [
      "0.0.3-142-deadbeef",
      "0.0.3-43-aaaabbbb",
      "0.0.3-5-ccccdddd",
      "0.0.3",
      "0.0.2",
      "0.0.1-2-a1d2g3f",
      "0.0.1-1-deadbeef",
      "0.0.1"
    ]
    result = Utils.sort_versions([
      "0.0.3",
      "0.0.2",
      "0.0.3-43-aaaabbbb",
      "0.0.1-1-deadbeef",
      "0.0.1-2-a1d2g3f",
      "0.0.3-142-deadbeef",
      "0.0.3-5-ccccdddd",
      "0.0.1"
    ])
    assert expected == result
  end

end
