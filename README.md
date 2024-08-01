# ServerSentEventStage

A GenStage producer which parses the ServerSentEvent protocol.

[![Build Status](https://github.com/mbta/server_sent_event_stage/actions/workflows/elixir.yml/badge.svg)](https://github.com/mbta/server_sent_event_stage/actions/workflows/elixir.yml)

## Installation

```elixir
def deps do
  [
    {:server_sent_event_stage, "~> 1.0.0"},
    {:castore, "~> 1.0"}
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

## Development

This project is developed against a version of Erlang that has trouble finding
OpenSSL on some systems. You may see `* ssl : No usable OpenSSL found` in the
Erlang compile output, and `mix deps.get` will subsequently fail due to missing
SSL support. To fix this, compile Erlang using the `--with-ssl=<PATH>` option.
For example, on macOS using OpenSSL installed through Homebrew:

    KERL_CONFIGURE_OPTIONS="--with-ssl=$(brew --prefix openssl)" asdf install

## License

`server_sent_event_stage` is licensed under the [MIT](LICENSE) license.
