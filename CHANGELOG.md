# Changelog

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
