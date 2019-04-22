defmodule ServerSentEventStageTest do
  use ExUnit.Case
  import ServerSentEventStage
  alias ServerSentEventStage.Event

  @moduletag :capture_log

  @assert_receive_timeout 500

  describe "start_link/1" do
    test "returns a pid when a URL is provided" do
      assert {:ok, pid} = start_link(url: "http://httpbin.org/get")
      assert is_pid(pid)
    end

    test "raises an error if a URL isn't provided" do
      assert_raise KeyError, fn -> start_link([]) end
    end

    test "does not connect to the URL without a consumer" do
      assert {:ok, _pid} = start_link(url: "http://does-not-exist.test")
    end
  end

  describe "handle_info/2" do
    test "connects after 200 status" do
      state = %ServerSentEventStage{}

      assert {:noreply, [], new_state} = handle_info(%HTTPoison.AsyncStatus{code: 200}, state)
      assert new_state.state == :connected
    end

    test "re-connects on a non-200 status" do
      state = %ServerSentEventStage{}

      assert {:noreply, [], _state} = handle_info(%HTTPoison.AsyncStatus{code: 401}, state)
      assert_received :connect
    end

    test "ignores headers" do
      state = %ServerSentEventStage{}

      assert {:noreply, [], ^state} = handle_info(%HTTPoison.AsyncHeaders{}, state)
    end

    test "does nothing with a partial chunk" do
      state = %ServerSentEventStage{state: :connected}

      assert {:noreply, [], _state} = handle_info(%HTTPoison.AsyncChunk{chunk: "data:"}, state)
    end

    test "with a full chunk, returns an event" do
      state = %ServerSentEventStage{state: :connected}

      assert {:noreply, [], state} = handle_info(%HTTPoison.AsyncChunk{chunk: "data:"}, state)

      assert {:noreply, [event], _state} =
               handle_info(%HTTPoison.AsyncChunk{chunk: "data\n\n"}, state)

      assert event.data == "data\n"
    end

    test "reconnects if there's an error" do
      state = %ServerSentEventStage{}

      assert {:noreply, [], _state} = handle_info(%HTTPoison.Error{reason: :closed}, state)
      assert_received :connect
    end

    @tag :capture_log
    test "ignores unexpected messages" do
      state = %ServerSentEventStage{}
      assert {:noreply, [], ^state} = handle_info(:unexpected, state)
    end
  end

  describe "bypass" do
    setup do
      Application.ensure_all_started(:bypass)
      Application.ensure_all_started(:httpoison)
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "sends an event when fully parsed", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "accept") == ["text/event-stream"]
        Plug.Conn.send_resp(conn, 200, ~s(data: %{}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
    end

    test "verify custom headers are sent", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        # verify custom header was set
        assert Plug.Conn.get_req_header(conn, "test") == ["confirmed"]
        # verify that header we didn't set wasn't
        assert Plug.Conn.get_req_header(conn, "nottest") != ["confirmed"]
        Plug.Conn.send_resp(conn, 200, ~s(data: %{}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
    end

    test "reconnects when it gets disconnected", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s(data: %{}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
      # should receive another event
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
    end

    test "reconnects after refresh", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, ~s(data: %{}\n\n))
        Process.sleep(1_000)
        {:ok, conn} = Plug.Conn.chunk(conn, ~s(data: %{}\n\n))
        conn
      end)

      {:ok, pid} = start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
      refresh(pid)
      # should receive another event
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
    end

    test "redirects to a new URL if provided", %{bypass: bypass} do
      redirected_bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "http://127.0.0.1:#{redirected_bypass.port}")
        |> Plug.Conn.send_resp(307, "data: ignore me\n\n")
      end)

      Bypass.expect(redirected_bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s(data: %{}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{data: "%{}\n"}]}, @assert_receive_timeout
      refute_receive {:events, [%Event{data: "ignore me\n"}]}, @assert_receive_timeout
    end

    test "can connect to a URL given by a function", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s(data: %{}\n\n))
      end)

      {:ok, pid} = start_link(url: {__MODULE__.Url, :url, [bypass.port]})
      assert %Event{} = Enum.at(GenStage.stream([pid]), 0)
    end

    defp start_producer(bypass) do
      url = "http://127.0.0.1:#{bypass.port}"
      headers = [{"test", "confirmed"}]
      {:ok, producer} = start_link(url: url, headers: headers)

      {:ok, _consumer} = __MODULE__.SimpleSubscriber.start_link(self(), producer)

      {:ok, producer}
    end
  end

  defmodule SimpleSubscriber do
    @moduledoc """
    Simple consumer which sends the events to a parent PID.
    """
    use GenStage

    def start_link(parent, producer) do
      GenStage.start_link(__MODULE__, {parent, producer})
    end

    def init({parent, producer}) do
      {:consumer, parent, subscribe_to: [{producer, max_demand: 1}]}
    end

    def handle_events(events, _from, parent) do
      send(parent, {:events, events})
      {:noreply, [], parent}
    end
  end

  defmodule Url do
    def url(port) do
      "http://127.0.0.1:#{port}"
    end
  end
end
