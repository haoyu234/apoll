import apoll
import apoll/priv/errnos

import std/nativesockets

const LISTEN_PORT = 2025

let poller = newPoller()

type AsyncSocket {.borrow: `.`.} = distinct Source

proc bindAddr*(s: AsyncSocket, port: Port) =
  var a: Sockaddr_in
  a.sin_addr.s_addr = INADDR_ANY
  a.sin_family = typeof(a.sin_family)(AF_INET.toInt)
  a.sin_port = htons(uint16(port))

  let err = s.socket.bindAddr(cast[ptr SockAddr](a.addr), SockLen(sizeof(a)))
  if err != 0:
    assert false

proc listen*(s: AsyncSocket) =
  let err = s.socket.listen(cint(128))
  if err != 0:
    assert false

proc accept*(s: AsyncSocket): AsyncSocket {.async.} =
  let res = await poll(poller, Source(s), kRead)
  if res != kRead:
    assert false

  let (socket, _) = accept(s.socket)
  socket.setBlocking(false)
  let source = registerSocket(poller, socket)
  AsyncSocket(source)

when not defined(windows):
  proc read*(s: AsyncSocket, data: pointer, size: int): int {.async.} =
    while true:
      let n = recv(s.socket, data, size, 0)
      if n < 0:
        if errno == EAGAIN:
          let res = await poll(poller, Source(s), kRead)
          if res != kRead:
            assert false
          continue

        if errno == EINTR:
          continue
        else:
          assert false

      return n

  proc write*(s: AsyncSocket, data: pointer, size: int) {.async.} =
    var offset = 0

    while offset < size:
      let p = cast[ptr UncheckedArray[byte]](data)[offset].addr
      let n = send(s.socket, p, size - offset, 0)
      if n < 0:
        if errno == EAGAIN:
          let res = await poll(poller, Source(s), kWrite)
          if res != kWrite:
            assert false
          continue

        if errno == EINTR:
          continue
        else:
          assert false

      offset = offset + n

proc doClient(s: AsyncSocket) {.async.} =
  defer:
    unregisterHandle(poller, Source(s))
    close(s.socket)

  when not defined(windows):
    var buff: array[1024, byte]

    while true:
      let n = await read(s, buff[0].addr, sizeof(buff))
      if n <= 0:
        return

      await write(s, buff[0].addr, n)
  else:
    await sleep(poller, 5000)

proc amain() {.async.} =
  let s = block:
    let socket = createNativeSocket()
    socket.setBlocking(false)
    let source = registerSocket(poller, socket)
    AsyncSocket(source)

  defer:
    unregisterHandle(poller, Source(s))
    close(s.socket)

  s.bindAddr(Port(LISTEN_PORT))
  s.listen()

  echo "listen: ", LISTEN_PORT

  while true:
    let client = await s.accept()
    discard doClient(client)

proc main() =
  waitFor poller, amain()

main()
