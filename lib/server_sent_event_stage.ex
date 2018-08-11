defmodule ServerSentEventStage do
  @moduledoc """
  A GenStage producer which parses the ServerSentEvent (SSE) protocol.

  SSEs are used in browsers via the EventSource API, but they can be used for
  any kind of one-directional streaming.

  For more information, see the [W3C](https://html.spec.whatwg.org/multipage/server-sent-events.html).
  """
  use GenStage
  require Logger
  alias ServerSentEventStage.Event

  # Client functions
  @doc """
  Starts a producer stage which parse the ServerSentEvent protocol and send those messages as events.

  The only required argument is `url`: it can be either a binary of the URL
  to connect to or a {module, fun, arguments} tuple.

  Other arguments are passed as options to `GenStage.start_link/3`.
  """
  def start_link(args) do
    url = Keyword.fetch!(args, :url)
    headers = Keyword.get(args, :headers, [])
    opts = Keyword.take(args, ~w(debug name timeout spawn_opt)a)
    GenStage.start_link(__MODULE__, %{url: url, headers: headers}, opts)
  end

  # Server functions
  defstruct [:url, :headers, buffer: "", state: :not_connected]

  @doc false
  def init(%{url: url, headers: headers}) do
    state = %__MODULE__{url: url, headers: headers}
    {:producer, state}
  end

  @doc false
  def handle_info(:connect, state) do
    url = compute_url(state)
    %{url: _url, headers: headers} = state
    :ok = connect_to_url(url, headers)
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncStatus{code: 200}, state) do
    Logger.debug(fn -> "#{__MODULE__} connected" end)
    state = %{state | state: :connected}
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncStatus{code: code}, state)
      when code in [301, 302, 303, 307, 308] do
    state = %{state | state: :redirecting}
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncHeaders{headers: headers}, %{state: :redirecting} = state) do
    {_, location} = Enum.find(headers, &(String.downcase(elem(&1, 0)) == "location"))
    state = %{state | state: {:redirect, location}}
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncHeaders{}, state) do
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, %{state: :connected} = state) do
    buffer = state.buffer <> chunk
    event_binaries = String.split(buffer, "\n\n")
    {event_binaries, [buffer]} = Enum.split(event_binaries, -1)
    events = Enum.map(event_binaries, &Event.from_string/1)

    unless events == [] do
      Logger.info(fn -> "#{__MODULE__} sending #{length(events)} events" end)

      for event <- events do
        Logger.debug(fn ->
          inspect(event, limit: :infinity, printable_limit: :infinity)
        end)
      end
    end

    state = %{state | buffer: buffer}
    {:noreply, events, state}
  end

  def handle_info(%HTTPoison.AsyncChunk{}, state) do
    # ignore chunks received unexpectedly
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.Error{reason: reason}, state) do
    Logger.error(fn -> "#{__MODULE__} HTTP error: #{inspect(reason)}" end)
    state = %{state | buffer: ""}
    send(self(), :connect)
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncEnd{}, %{state: {:redirect, new_url}} = state) do
    %{url: _url, headers: headers} = state
    :ok = connect_to_url(new_url, headers)
    state = %{state | buffer: "", state: :connected}
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncEnd{}, state) do
    Logger.info(fn -> "#{__MODULE__} disconnected, reconnecting..." end)
    state = %{state | buffer: "", state: :connected}
    send(self(), :connect)
    {:noreply, [], state}
  end

  @doc false
  def handle_demand(_demand, state) do
    :ok = maybe_connect(state)
    {:noreply, [], state}
  end

  defp connect_to_url(url, headers) do
    Logger.debug(fn -> "#{__MODULE__} requesting #{url}" end)

    headers = [
      {"Accept", "text/event-stream"} | headers
    ]

    {:ok, _} =
      HTTPoison.get(
        url,
        headers,
        recv_timeout: 60_000,
        stream_to: self()
      )

    :ok
  end

  defp maybe_connect(%{state: :not_connected}) do
    send(self(), :connect)
    :ok
  end

  defp maybe_connect(_state) do
    :ok
  end

  defp compute_url(%{url: {m, f, a}}) do
    apply(m, f, a)
  end

  defp compute_url(%{url: url}) when is_binary(url) do
    url
  end
end
