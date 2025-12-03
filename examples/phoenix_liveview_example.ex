defmodule MyAppWeb.MCPStatusLive do
  @moduledoc """
  Phoenix LiveView for real-time MCP client status monitoring.

  This LiveView provides a dashboard to monitor the health and status of all
  registered MCP clients. It automatically updates every 2 seconds to show
  real-time status changes.

  ## Installation

  1. Add to your router:

      live "/mcp/status", MyAppWeb.MCPStatusLive

  2. Define your MCP clients using `LangChain.MCP.Client`:

      defmodule MyApp.GitHubMCP do
        use LangChain.MCP.Client,
          name: "GitHub MCP",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

      defmodule MyApp.FilesystemMCP do
        use LangChain.MCP.Client,
          name: "Filesystem MCP",
          version: "1.0.0",
          protocol_version: "2025-03-26"
      end

  3. Start clients and register with StatusMonitor:

      defmodule MyApp.Application do
        use Application
        alias LangChain.MCP.StatusMonitor

        def start(_type, _args) do
          children = [
            {MyApp.GitHubMCP,
              transport: {:streamable_http, base_url: "http://localhost:5000"}},
            {MyApp.FilesystemMCP,
              transport: :stdio}
          ]

          {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)

          # Register clients for status monitoring
          StatusMonitor.register_client_by_name(MyApp.GitHubMCP, :github)
          StatusMonitor.register_client_by_name(MyApp.FilesystemMCP, :filesystem)

          {:ok, self()}
        end
      end

  ## Features

  - Real-time status updates every 2 seconds
  - Color-coded status indicators (green = healthy, red = unhealthy)
  - Overall health summary with uptime percentage
  - Detailed client information including PID and error messages
  - Responsive design with Tailwind CSS

  """
  use Phoenix.LiveView

  alias LangChain.MCP.StatusMonitor

  @update_interval 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Schedule periodic updates
      schedule_update()
    end

    socket =
      socket
      |> assign(:status, fetch_status())
      |> assign(:last_update, DateTime.utc_now())

    {:ok, socket}
  end

  @impl true
  def handle_info(:update, socket) do
    schedule_update()

    socket =
      socket
      |> assign(:status, fetch_status())
      |> assign(:last_update, DateTime.utc_now())

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 mb-2">
          MCP Client Status Monitor
        </h1>
        <p class="text-gray-600">
          Last updated: <%= Calendar.strftime(@last_update, "%Y-%m-%d %H:%M:%S") %> UTC
        </p>
      </div>

      <!-- Summary Card -->
      <div class="bg-white rounded-lg shadow-lg p-6 mb-8">
        <h2 class="text-xl font-semibold mb-4">Health Summary</h2>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div class="bg-blue-50 rounded-lg p-4">
            <div class="text-sm text-blue-600 font-medium">Total Clients</div>
            <div class="text-3xl font-bold text-blue-900">
              <%= @status.summary.total_clients %>
            </div>
          </div>

          <div class="bg-green-50 rounded-lg p-4">
            <div class="text-sm text-green-600 font-medium">Healthy</div>
            <div class="text-3xl font-bold text-green-900">
              <%= length(@status.summary.healthy_clients) %>
            </div>
          </div>

          <div class="bg-red-50 rounded-lg p-4">
            <div class="text-sm text-red-600 font-medium">Unhealthy</div>
            <div class="text-3xl font-bold text-red-900">
              <%= length(@status.summary.unhealthy_clients) %>
            </div>
          </div>

          <div class="bg-purple-50 rounded-lg p-4">
            <div class="text-sm text-purple-600 font-medium">Uptime</div>
            <div class="text-3xl font-bold text-purple-900">
              <%= Float.round(@status.summary.uptime_percentage, 1) %>%
            </div>
          </div>
        </div>
      </div>

      <!-- Client Status Cards -->
      <div class="space-y-4">
        <h2 class="text-xl font-semibold">Client Details</h2>

        <%= if map_size(@status.clients) == 0 do %>
          <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg
                  class="h-5 w-5 text-yellow-400"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                >
                  <path
                    fill-rule="evenodd"
                    d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div class="ml-3">
                <p class="text-sm text-yellow-700">
                  No MCP clients are currently registered. Make sure your clients are started
                  and registered with StatusMonitor.
                </p>
              </div>
            </div>
          </div>
        <% else %>
          <%= for {name, client_status} <- @status.clients do %>
            <div class="bg-white rounded-lg shadow p-6">
              <div class="flex items-center justify-between">
                <div class="flex items-center space-x-4">
                  <!-- Status Indicator -->
                  <div class={[
                    "w-4 h-4 rounded-full",
                    if(client_status.status == :healthy, do: "bg-green-500", else: "bg-red-500")
                  ]}>
                  </div>

                  <div>
                    <h3 class="text-lg font-semibold text-gray-900">
                      <%= name %>
                    </h3>
                    <p class="text-sm text-gray-600">
                      Status: <span class={[
                        "font-medium",
                        if(client_status.status == :healthy,
                          do: "text-green-600",
                          else: "text-red-600"
                        )
                      ]}>
                        <%= client_status.status %>
                      </span>
                    </p>
                  </div>
                </div>

                <!-- Status Badge -->
                <span class={[
                  "px-3 py-1 rounded-full text-sm font-medium",
                  if(client_status.alive?,
                    do: "bg-green-100 text-green-800",
                    else: "bg-red-100 text-red-800"
                  )
                ]}>
                  <%= if client_status.alive?, do: "Active", else: "Inactive" %>
                </span>
              </div>

              <!-- Client Details -->
              <div class="mt-4 grid grid-cols-1 md:grid-cols-2 gap-4">
                <%= if Map.has_key?(client_status, :pid) do %>
                  <div>
                    <dt class="text-sm font-medium text-gray-500">Process ID</dt>
                    <dd class="mt-1 text-sm text-gray-900 font-mono">
                      <%= inspect(client_status.pid) %>
                    </dd>
                  </div>
                <% end %>

                <%= if Map.has_key?(client_status, :error) do %>
                  <div>
                    <dt class="text-sm font-medium text-gray-500">Error</dt>
                    <dd class="mt-1 text-sm text-red-600">
                      <%= inspect(client_status.error) %>
                    </dd>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <!-- Auto-refresh indicator -->
      <div class="mt-8 text-center text-sm text-gray-500">
        <p>Dashboard auto-refreshes every 2 seconds</p>
      </div>
    </div>
    """
  end

  defp fetch_status do
    StatusMonitor.dashboard_status()
  end

  defp schedule_update do
    Process.send_after(self(), :update, @update_interval)
  end
end
