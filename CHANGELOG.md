# Changelog

## 1.2.1

- Allow version 1.x of the optional `ca_store` dependency, as there are no breaking changes from 0.1.x.

## 1.2.0

- feat: optionally time out if stream goes idle (@boringcactus)
- chore: upgrade to Erlang 24 (@boringcactus)

This bumps the minimum supported version of Erlang to 24, and of Elixir to
1.11.4. It also bumps the versions of `gen_stage` and `ex_doc`.

## 1.1.0

- Bump mint to version 1.4 to support OTP 24.

## 1.0.2

- Bump gen_stage to version 1.0.
- Update ex_doc and excoveralls dependencies.

## 1.0.1

- Fix a process leak when re-connecting to the remote server
- Include the URL along with the log messages to distinguish multiple stages

## 1.0.0

- Switch to Mint as our HTTP library. We optionally depend on `ca_store` for certificate validation.
- Bump the minimum supported Elixir version to 1.7

## 0.4.1

- Support refreshing the connection. For some SSE clients, they'll send a final message but not disconnected. This allows the upstream consumer of the stream to reconnect.
- Update ex_doc dependency.

## 0.3.0

- Support passing custom headers (@mogorman)

## 0.2.0

- Support streams which redirect to a different URL

## 0.1.0

- Initial public release
