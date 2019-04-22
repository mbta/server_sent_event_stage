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
    _url = Keyword.fetch!(args, :url)
    opts = Keyword.take(args, ~w(debug name timeout spawn_opt)a)
    GenStage.start_link(__MODULE__, args, opts)
  end

  # Server functions
  defstruct [:url, :headers, :id, buffer: "", state: :not_connected]

  @doc false
  def init(args) do
    state = %__MODULE__{
      url: Keyword.fetch!(args, :url),
      headers: Keyword.get(args, :headers, [])
    }

    {:producer, state}
  end

  @doc false
  def handle_info(:connect, state) do
    url = compute_url(state)
    {:ok, id} = connect_to_url(url, state.headers)
    {:noreply, [], %{state | id: id}}
  end

  def handle_info(%HTTPoison.AsyncStatus{id: id, code: 200}, %{id: id} = state) do
    Logger.debug(fn -> "#{__MODULE__} connected" end)
    state = %{state | state: :connected}
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncHeaders{id: id}, %{id: id} = state) do
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncChunk{id: id, chunk: chunk}, %{id: id, state: :connected} = state) do
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

  def handle_info(%HTTPoison.AsyncChunk{id: id}, %{id: id} = state) do
    # ignore chunks received unexpectedly
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.Error{id: id, reason: reason}, %{id: id} = state) do
    Logger.error(fn -> "#{__MODULE__} HTTP error: #{inspect(reason)}" end)
    state = %{state | buffer: ""}
    send(self(), :connect)
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncEnd{id: id}, %{id: id} = state) do
    Logger.info(fn -> "#{__MODULE__} disconnected, reconnecting..." end)
    state = reset_state(state)
    send(self(), :connect)
    {:noreply, [], state}
  end

  def handle_info(%HTTPoison.AsyncRedirect{id: id, to: location}, %{id: id} = state) do
    {:ok, id} = connect_to_url(location, state.headers)
    state = reset_state(state)
    {:noreply, [], %{state | id: id}}
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

    {:ok, %{id: id}} =
      HTTPoison.get(
        url,
        headers,
        recv_timeout: 60_000,
        follow_redirect: true,
        stream_to: self()
      )

    {:ok, id}
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

  defp reset_state(state) do
    %{state | id: nil, buffer: ""}
  end
end
