defmodule ServerSentEventStageTest do
  use ExUnit.Case
  import ServerSentEventStage
  alias ServerSentEventStage.Event
  import ExUnit.CaptureLog

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
    @tag :capture_log
    test "ignores unexpected messages" do
      state = %ServerSentEventStage{}
      assert {:noreply, [], ^state} = handle_info(:unexpected, state)
    end

    @tag :capture_log
    test "ignores {:ssl, _port, _data} messages" do
      state = %ServerSentEventStage{conn: %Mint.HTTP1{}}
      assert {:noreply, [], ^state} = handle_info({:ssl, :port, "data"}, state)
    end

    @tag :capture_log
    test "ignores {:ssl_closed, _port} messages" do
      state = %ServerSentEventStage{conn: %Mint.HTTP1{}}
      assert {:noreply, [], ^state} = handle_info({:ssl_closed, :port}, state)
    end
  end

  describe "bypass" do
    setup do
      Application.ensure_all_started(:bypass)
      bypass = Bypass.open()
      {:ok, bypass: bypass}
    end

    test "sends an event when fully parsed", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        assert Plug.Conn.get_req_header(conn, "accept") == ["text/event-stream"]
        Plug.Conn.send_resp(conn, 200, ~s(data: {}\n\n))
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
        Plug.Conn.send_resp(conn, 200, ~s(data: {}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
    end

    test "reconnects when it gets disconnected", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s(data: {}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
      # should receive another event
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
    end

    test "reconnects when it can't make a TCP connection", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s(data: {}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
      Bypass.down(bypass)
      Process.sleep(100)
      Bypass.up(bypass)
      # should receive another event
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
    end

    test "reconnects after refresh", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, ~s(data: {}\n\n))
        Process.sleep(:infinity)
        conn
      end)

      {:ok, pid} = start_producer(bypass)
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
      refresh(pid)
      # should receive another event
      assert_receive {:events, [%Event{}]}, @assert_receive_timeout
      Bypass.pass(bypass)
    end

    test "redirects to a new URL if provided", %{bypass: bypass} do
      redirected_bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "http://127.0.0.1:#{redirected_bypass.port}")
        |> Plug.Conn.send_resp(307, "data: ignore me\n\n")
      end)

      Bypass.expect(redirected_bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s(data: {}\n\n))
      end)

      start_producer(bypass)
      assert_receive {:events, [%Event{data: "{}\n"}]}, @assert_receive_timeout
      refute_receive {:events, [%Event{data: "ignore me\n"}]}, @assert_receive_timeout
    end

    test "can connect to a URL given by a function", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s(data: {}\n\n))
      end)

      {:ok, pid} = start_link(url: {__MODULE__.Url, :url, [bypass.port]})
      assert %Event{} = Enum.at(GenStage.stream([pid]), 0)
    end

    test "logs a message on invalid status", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      log =
        capture_log(fn ->
          start_producer(bypass)
          Process.sleep(100)
        end)

      assert log =~ "unexpected status"
    end

    test "logs a message on invalid HTTP responses", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("transfer-encoding", "transfer-encoding")
        |> Plug.Conn.put_resp_header("content-length", "1")
        |> Plug.Conn.send_resp(200, "d")
      end)

      log =
        capture_log(fn ->
          start_producer(bypass)
          Process.sleep(100)
        end)

      assert log =~ "HTTP error"
    end

    test "can connect with a path/query", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.send_resp(conn, 200, "data: #{conn.request_path} #{conn.query_string}\n\n")
      end)

      {:ok, pid} = start_link(url: "http://127.0.0.1:#{bypass.port}")
      assert %Event{data: "/ \n"} = Enum.at(GenStage.stream([pid]), 0)
      GenStage.stop(pid)

      {:ok, pid} = start_link(url: "http://127.0.0.1:#{bypass.port}/path")
      assert %Event{data: "/path \n"} = Enum.at(GenStage.stream([pid]), 0)
      GenStage.stop(pid)

      {:ok, pid} = start_link(url: "http://127.0.0.1:#{bypass.port}/path?query")
      assert %Event{data: "/path query\n"} = Enum.at(GenStage.stream([pid]), 0)
      GenStage.stop(pid)

      {:ok, pid} = start_link(url: "http://127.0.0.1:#{bypass.port}?query")
      assert %Event{data: "/ query\n"} = Enum.at(GenStage.stream([pid]), 0)
      GenStage.stop(pid)
    end

    test "applies idle timeout", %{bypass: bypass} do
      idle_timeout = 200

      {:ok, request_count} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        request_count = Agent.get_and_update(request_count, &{&1, &1 + 1})

        conn = Plug.Conn.send_chunked(conn, 200)

        conn =
          case request_count do
            0 ->
              # ignore the connection termination in Bypass
              Bypass.pass(bypass)

              Process.sleep(:infinity)
              conn

            1 ->
              # check that comments properly reset idle timeout
              Process.sleep(idle_timeout - 10)
              {:ok, conn} = Plug.Conn.chunk(conn, ": keep-alive\n")
              Process.sleep(idle_timeout - 10)
              conn

            _ ->
              conn
          end

        {:ok, conn} = Plug.Conn.chunk(conn, ~s(data: #{request_count}\n\n))

        conn
      end)

      start_producer(bypass, idle_timeout: idle_timeout)

      refute_receive {:events, _}, idle_timeout
      assert_receive {:events, [%Event{data: "1\n"}]}, @assert_receive_timeout
    end

    defp start_producer(bypass, opts \\ []) do
      url = "http://127.0.0.1:#{bypass.port}"
      headers = [{"test", "confirmed"}]
      {:ok, producer} = start_link([url: url, headers: headers] ++ opts)

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
