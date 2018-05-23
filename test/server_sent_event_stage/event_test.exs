defmodule ServerSentEventStage.EventTest do
  use ExUnit.Case, async: true
  alias ServerSentEventStage.Event
  import Event

  doctest Event
end
