defmodule LangChain.MCP.ConfigTest do
  use ExUnit.Case, async: true

  # Create a dummy module for testing
  defmodule TestClient do
    def some_function, do: :ok
  end

  alias LangChain.MCP.Config

  describe "new!/1" do
    test "creates valid config with required fields" do
      config = Config.new!(client: TestClient)

      assert config.client == TestClient
      assert config.cache_tools == true
      assert config.timeout == 30_000
      assert config.async == false
    end

    test "creates config with custom values" do
      config =
        Config.new!(
          client: TestClient,
          cache_tools: false,
          timeout: 60_000,
          async: true
        )

      assert config.cache_tools == false
      assert config.timeout == 60_000
      assert config.async == true
    end

    test "accepts fallback client" do
      config =
        Config.new!(
          client: TestClient,
          fallback_client: TestClient
        )

      assert config.fallback_client == TestClient
    end

    test "accepts callback functions" do
      before_fallback_fn = fn _config, _tool, _args -> :continue end
      filter_fn = fn _tool -> true end

      config =
        Config.new!(
          client: TestClient,
          before_fallback: before_fallback_fn,
          tool_filter: filter_fn
        )

      assert is_function(config.before_fallback, 3)
      assert is_function(config.tool_filter, 1)
    end

    test "accepts context map" do
      context = %{user_id: 123, session: "abc"}

      config =
        Config.new!(
          client: TestClient,
          context: context
        )

      assert config.context == context
    end

    test "raises on missing client" do
      assert_raise ArgumentError, fn ->
        Config.new!([])
      end
    end

    test "raises on invalid timeout" do
      assert_raise ArgumentError, fn ->
        Config.new!(client: TestClient, timeout: -1)
      end
    end

    test "raises on wrong callback arity" do
      wrong_arity_fn = fn -> :ok end

      assert_raise ArgumentError, fn ->
        Config.new!(
          client: TestClient,
          before_fallback: wrong_arity_fn
        )
      end
    end
  end

  describe "has_fallback?/1" do
    test "returns true when fallback client configured" do
      config =
        Config.new!(
          client: TestClient,
          fallback_client: TestClient
        )

      assert Config.has_fallback?(config) == true
    end

    test "returns false when no fallback client" do
      config = Config.new!(client: TestClient)

      assert Config.has_fallback?(config) == false
    end
  end

  describe "filter_tool?/2" do
    test "returns true when no filter configured" do
      config = Config.new!(client: TestClient)
      tool = %{"name" => "any_tool"}

      assert Config.filter_tool?(config, tool) == true
    end

    test "applies filter function when configured" do
      config =
        Config.new!(
          client: TestClient,
          tool_filter: fn tool -> tool["name"] == "allowed" end
        )

      assert Config.filter_tool?(config, %{"name" => "allowed"}) == true
      assert Config.filter_tool?(config, %{"name" => "blocked"}) == false
    end
  end

  describe "before_fallback/3" do
    test "returns :continue when no callback configured" do
      config = Config.new!(client: TestClient)

      result = Config.before_fallback(config, "tool", %{})

      assert result == :continue
    end

    test "calls callback when configured" do
      config =
        Config.new!(
          client: TestClient,
          before_fallback: fn _config, tool_name, _args ->
            if tool_name == "skip_me", do: :skip, else: :continue
          end
        )

      assert Config.before_fallback(config, "skip_me", %{}) == :skip
      assert Config.before_fallback(config, "other", %{}) == :continue
    end

    test "defaults to :continue for non-standard return values" do
      config =
        Config.new!(
          client: TestClient,
          before_fallback: fn _, _, _ -> :something_else end
        )

      result = Config.before_fallback(config, "tool", %{})

      assert result == :continue
    end
  end

  describe "new!/1 with PID client" do
    test "accepts a PID as client" do
      # Spawn a dummy process to get a valid PID
      pid = spawn(fn -> Process.sleep(:infinity) end)

      config = Config.new!(client: pid)

      assert config.client == pid

      Process.exit(pid, :kill)
    end

    test "rejects dead PID" do
      pid = spawn(fn -> :ok end)
      # Let it die
      Process.sleep(10)

      assert_raise ArgumentError, ~r/not alive/, fn ->
        Config.new!(client: pid)
      end
    end
  end

  describe "new!/1 with via tuple client" do
    test "accepts {:via, Registry, {name, key}}" do
      config = Config.new!(client: {:via, Registry, {MyRegistry, "key"}})

      assert config.client == {:via, Registry, {MyRegistry, "key"}}
    end

    test "accepts {:global, name}" do
      config = Config.new!(client: {:global, :my_client})

      assert config.client == {:global, :my_client}
    end
  end

  describe "new!/1 with PID fallback_client" do
    test "accepts a PID as fallback_client" do
      primary_pid = spawn(fn -> Process.sleep(:infinity) end)
      fallback_pid = spawn(fn -> Process.sleep(:infinity) end)

      config = Config.new!(client: primary_pid, fallback_client: fallback_pid)

      assert config.client == primary_pid
      assert config.fallback_client == fallback_pid

      Process.exit(primary_pid, :kill)
      Process.exit(fallback_pid, :kill)
    end

    test "accepts via tuple as fallback_client" do
      primary_pid = spawn(fn -> Process.sleep(:infinity) end)

      config =
        Config.new!(
          client: primary_pid,
          fallback_client: {:via, Registry, {MyRegistry, "fallback"}}
        )

      assert config.fallback_client == {:via, Registry, {MyRegistry, "fallback"}}

      Process.exit(primary_pid, :kill)
    end

    test "rejects dead PID as fallback_client" do
      primary_pid = spawn(fn -> Process.sleep(:infinity) end)
      fallback_pid = spawn(fn -> :ok end)
      # Let it die
      Process.sleep(10)

      assert_raise ArgumentError, ~r/not alive/, fn ->
        Config.new!(client: primary_pid, fallback_client: fallback_pid)
      end

      Process.exit(primary_pid, :kill)
    end
  end
end
