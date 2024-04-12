defmodule ServerSentEventStage do
  @moduledoc """
  A GenStage producer which parses the ServerSentEvent (SSE) protocol.

  SSEs are used in browsers via the EventSource API, but they can be used for
  any kind of one-directional streaming.

  For more information, see the [W3C](https://html.spec.whatwg.org/multipage/server-sent-events.html).
  """
  use GenStage
  require Logger
  alias Mint.HTTP
  alias ServerSentEventStage.Event

  # Client functions
  @doc """
  Starts a producer stage which parse the ServerSentEvent protocol and send those messages as events.

  The only required argument is `url`: it can be either a binary of the URL
  to connect to or a {module, fun, arguments} tuple.

  Optional arguments:
  - `headers`: a list of `{"name", "value"}` pairs
  - `idle_timeout`: milliseconds of inactivity after which the connection will be restarted
  - `debug`, `name`, `timeout`, `spawn_opt`: options for `GenStage.start_link/3`
  """
  def start_link(args) do
    _url = Keyword.fetch!(args, :url)
    opts = Keyword.take(args, ~w(debug name timeout spawn_opt)a)
    GenStage.start_link(__MODULE__, args, opts)
  end

  @doc """
  Refresh the connection by disconnecting and reconnecting.

  Some clients will send a final message, but not terminate the
  connection=. This function allows a client of SSES to reconnect.
  """
  def refresh(server) do
    GenStage.cast(server, :refresh)
  end

  # Server functions
  defstruct [
    :url,
    :headers,
    :connected_url,
    :conn,
    :ref,
    :idle_timeout,
    :idle_timer,
    buffer: "",
    redirecting?: false
  ]

  @doc false
  def init(args) do
    state = %__MODULE__{
      url: Keyword.fetch!(args, :url),
      headers: Keyword.get(args, :headers, []),
      idle_timeout: Keyword.get(args, :idle_timeout, nil)
    }

    {:producer, state}
  end

  @doc false
  def handle_info(:connect, state) do
    url = compute_url(state)
    state = do_connect(url, state)
    {:noreply, [], state}
  end

  def handle_info(:idle_timeout, state) do
    Logger.warn(fn -> "#{__MODULE__} idle_timeout url=#{inspect(state.connected_url)}" end)
    do_refresh!()
    {:noreply, [], state}
  end

  def handle_info(message, %{conn: conn} = state) when conn != nil do
    state = reset_idle_timeout(state)

    case HTTP.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn}
        {state, events} = Enum.reduce_while(responses, {state, []}, &handle_mint_response/2)

        {:noreply, events, state}

      {:error, conn, error, responses} ->
        state = %{state | conn: conn}
        ref = state.ref
        {state, events} = Enum.reduce_while(responses, {state, []}, &handle_mint_response/2)
        {_, {state, events}} = handle_mint_response({:error, ref, error}, {state, events})

        {:noreply, events, state}

      :unknown ->
        handle_unknown_info(message, state)
    end
  end

  def handle_info(message, state) do
    handle_unknown_info(message, state)
  end

  defp handle_unknown_info({data_tag, _, _}, state) when data_tag in [:ssl, :tcp] do
    # The can occur after we've re-connected: drop them on the floor
    {:noreply, [], state}
  end

  defp handle_unknown_info({closed_tag, _}, state)
       when closed_tag in [:ssl_closed, :tcp_closed] do
    # These can occur after we've re-connected: drop them on the floor.
    {:noreply, [], state}
  end

  defp handle_unknown_info(message, state) do
    # ignore data received unexpectedly
    Logger.warn(fn ->
      "#{__MODULE__} unexpected message: #{inspect(message)}\nState: #{inspect(state)}"
    end)

    {:noreply, [], state}
  end

  defp handle_mint_response({:status, ref, 200}, {%{ref: ref} = state, _events} = acc) do
    Logger.debug(fn -> "#{__MODULE__} connected url=#{inspect(state.connected_url)}" end)
    {:cont, acc}
  end

  defp handle_mint_response({:status, ref, redirect_code}, {%{ref: ref} = state, events})
       when redirect_code in [301, 302, 307] do
    Logger.debug(fn ->
      "#{__MODULE__} connected, received redirect url=#{inspect(state.connected_url)} code=#{
        redirect_code
      }"
    end)

    state = %{state | redirecting?: true}
    {:cont, {state, events}}
  end

  defp handle_mint_response({:status, ref, code}, {%{ref: ref} = state, events}) do
    Logger.warn(fn ->
      "#{__MODULE__} unexpected status url=#{inspect(state.connected_url)} code=#{code}"
    end)

    do_refresh!()
    {:halt, {state, events}}
  end

  defp handle_mint_response(
         {:headers, ref, _headers},
         {%{ref: ref, redirecting?: false}, _events} = acc
       ) do
    {:cont, acc}
  end

  defp handle_mint_response(
         {:headers, ref, headers},
         {%{ref: ref, redirecting?: true} = state, events}
       ) do
    {"location", new_location} =
      Enum.find(headers, fn {header, _value} -> header == "location" end)

    state = do_connect(new_location, state)
    {:halt, {state, events}}
  end

  defp handle_mint_response({:data, ref, chunk}, {%{ref: ref} = state, events}) do
    buffer = state.buffer <> chunk
    event_binaries = String.split(buffer, "\n\n")
    {event_binaries, [buffer]} = Enum.split(event_binaries, -1)

    new_events = Enum.map(event_binaries, &Event.from_string/1)

    unless new_events == [] do
      Logger.info(fn ->
        "#{__MODULE__} sending events url=#{inspect(state.connected_url)} count=#{
          length(new_events)
        }"
      end)

      for event <- new_events do
        Logger.debug(fn ->
          inspect(event, limit: :infinity, printable_limit: :infinity)
        end)
      end
    end

    state = %{state | buffer: buffer}
    {:cont, {state, events ++ new_events}}
  end

  defp handle_mint_response({:done, ref}, {%{ref: ref} = state, events}) do
    Logger.info(fn ->
      "#{__MODULE__} disconnected, reconnecting... url=#{inspect(state.connected_url)}"
    end)

    do_refresh!()
    {:halt, {state, events}}
  end

  defp handle_mint_response({:error, ref, reason}, {%{ref: ref} = state, events}) do
    Logger.error(fn ->
      "#{__MODULE__} HTTP error url=#{inspect(state.connected_url)} reason=#{inspect(reason)}"
    end)

    do_refresh!()
    {:halt, {state, events}}
  end

  @doc false
  def handle_demand(_demand, state) do
    :ok = maybe_connect(state)
    {:noreply, [], state}
  end

  @doc false
  def handle_cast(:refresh, state) do
    do_refresh!()
    {:noreply, [], state}
  end

  defp do_connect(url, state) do
    state = reset_state(state)

    case connect_to_url(url, state.headers) do
      {:ok, conn, ref} ->
        %{state | connected_url: url, conn: conn, ref: ref}

      {:error, reason} ->
        Logger.error(fn ->
          "#{__MODULE__} unable to connect url=#{inspect(url)} reason=#{inspect(reason)}"
        end)

        do_refresh!()

        state
    end
  end

  defp connect_to_url(url, headers) do
    Logger.debug(fn -> "#{__MODULE__} requesting #{url}" end)

    uri = URI.parse(url)

    uri.scheme
    |> scheme_atom
    |> HTTP.connect(uri.host, uri.port, transport_opts: [timeout: 60_000])
    |> handle_connect_response(uri, headers)
  end

  defp scheme_atom("https"), do: :https
  defp scheme_atom("http"), do: :http

  defp handle_connect_response({:ok, conn}, uri, headers) do
    headers = [
      {"Accept", "text/event-stream"} | headers
    ]

    path =
      case {uri.path, uri.query} do
        {nil, nil} ->
          "/"

        {path, nil} ->
          path

        {nil, query} ->
          "/?" <> query

        {path, query} ->
          path <> "?" <> query
      end

    {:ok, conn, ref} = HTTP.request(conn, "GET", path, headers, nil)

    {:ok, conn, ref}
  end

  defp handle_connect_response({:error, _reason} = e, _uri_, _headers) do
    e
  end

  defp maybe_connect(%{conn: conn}) do
    if conn == nil or not HTTP.open?(conn, :read) do
      send(self(), :connect)
    end

    :ok
  end

  defp compute_url(%{url: {m, f, a}}) do
    apply(m, f, a)
  end

  defp compute_url(%{url: url}) when is_binary(url) do
    url
  end

  defp reset_state(state) do
    if state.conn != nil and HTTP.open?(state.conn, :read) do
      {:ok, _conn} = HTTP.close(state.conn)
    end

    %{state | connected_url: nil, conn: nil, ref: nil, redirecting?: false, buffer: ""}
  end

  defp do_refresh! do
    send(self(), :connect)
  end

  defp reset_idle_timeout(state) do
    if state.idle_timer != nil do
      :ok = Process.cancel_timer(state.idle_timer, async: true, info: false)
    end

    timer =
      if timeout = state.idle_timeout do
        Process.send_after(self(), :idle_timeout, timeout)
      end

    %__MODULE__{state | idle_timer: timer}
  end
end
