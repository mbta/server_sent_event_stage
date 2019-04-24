# Changelog

## 0.4.1

- Support refreshing the connection. For some SSE clients, they'll send a final message but not disconnected. This allows the upstream consumer of the stream to reconnect.
- Update ex_doc dependency.

## 0.3.0

- Support passing custom headers (@mogorman)

## 0.2.0

- Support streams which redirect to a different URL

## 0.1.0

- Initial public release
