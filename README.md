# ServerSentEventStage

A GenStage producer which parses the ServerSentEvent protocol.

[![Build Status](https://semaphoreci.com/api/v1/mbta/server_sent_event_stage/branches/master/shields_badge.svg)](https://semaphoreci.com/mbta/server_sent_event_stage) [![codecov](https://codecov.io/gh/mbta/server_sent_event_stage/branch/master/graph/badge.svg)](https://codecov.io/gh/mbta/server_sent_event_stage)


## Installation

```elixir
def deps do
  [
    {:server_sent_event_stage, "~> 0.1.0"}
  ]
end
```

## Use

`start_link/1` starts the server:

```elixir
iex> {:ok, pid} = ServerSentEventStage.start_link(url: "https://...")
iex> Enum.take(GenStage.stream([pid]), 2)
[%ServerSentEventStage.Event{}, %ServerSentEventStage.Event{}]
```

More likely, you'll want to add it as a part of a supervision tree:

```elixir
# in a Supervisor.init callback
children = [
    {ServerSentEventStage, url: "https://..."},
    ...
]
```

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/server_sent_event_stage/).

## License

`server_sent_event_stage` is licensed under the [MIT](LICENSE) license.
