defmodule ServerSentEventStage.Event do
  @moduledoc """
  A single ServerSentEvent (SSE) from a server.

  The SSE protocol is defined by the [W3C](
  https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream).
  """
  defstruct event: "message",
            data: ""

  @type t :: %__MODULE__{
          event: String.t(),
          data: String.t()
        }

  @doc """
  Parse a UTF-8 string into a struct.

  Expects a full SSE block.

      iex> from_string("event: put\\rdata:123\\r\\ndata: 456\\n")
      %Event{event: "put", data: "123\\n456\\n"}

      iex> from_string(":comment\\ndata:  short\\nignored: field")
      %Event{event: "message", data: " short\\n"}
  """
  def from_string(string) do
    string
    |> String.split(~r/\r|\r\n|\n/, trim: true)
    |> Enum.reduce(%__MODULE__{}, &include_line/2)
  end

  defp include_line(":" <> _, acc) do
    # comment
    acc
  end

  defp include_line("event:" <> rest, acc) do
    # event, can only be one
    %{acc | event: trim_one_space(rest)}
  end

  defp include_line("data:" <> rest, acc) do
    # data, gets accumulated separated by newlines
    %{acc | data: add_data(acc.data, trim_one_space(rest))}
  end

  defp include_line(_, acc) do
    # ignored
    acc
  end

  defp trim_one_space(" " <> rest), do: rest
  defp trim_one_space(data), do: data

  defp add_data(first, second) do
    first <> second <> "\n"
  end
end
