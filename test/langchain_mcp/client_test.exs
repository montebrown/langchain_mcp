defmodule LangChain.MCP.ClientTest do
  use ExUnit.Case, async: true

  describe "LangChain.MCP.Client wrapper" do
    test "defines a client module that inherits from Anubis.Client" do
      defmodule TestBasicClient do
        use LangChain.MCP.Client,
          name: "Test Client",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      # Should define child_spec and start_link
      assert function_exported?(TestBasicClient, :child_spec, 1)
      assert function_exported?(TestBasicClient, :start_link, 1)
    end

    test "can start a client successfully" do
      defmodule TestClientBasic do
        use LangChain.MCP.Client,
          name: "Test Client",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      {:ok, pid} =
        TestClientBasic.start_link(transport: {:streamable_http, base_url: "http://localhost:5000"})

      assert is_pid(pid)

      # Cleanup
      Supervisor.stop(pid)
    end
  end

  describe "LangChain.MCP.Client documentation" do
    test "module has proper @moduledoc" do
      # Check that the module has documentation
      {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(LangChain.MCP.Client)
      assert module_doc != :hidden
      assert module_doc != :none
    end
  end
end
