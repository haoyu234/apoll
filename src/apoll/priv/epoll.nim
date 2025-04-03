when defined(windows):
  {.passL: "-lws2_32".}
  {.compile: "wepoll/wepoll.c".}

  import os
  from std/winlean import SocketHandle

  {.pragma: c_header, header: currentSourcePath().splitPath.head & "/wepoll/wepoll.h".}

  type
    EpollHandle* {.importc: "HANDLE", c_header.} = distinct pointer
    EpollSocketHandle* {.importc: "SOCKET", c_header.} = SocketHandle

  const
    EPOLLIN* = uint32(1 shl 0)
    EPOLLPRI* = uint32(1 shl 1)
    EPOLLOUT* = uint32(1 shl 2)
    EPOLLERR* = uint32(1 shl 3)
    EPOLLHUP* = uint32(1 shl 4)
    EPOLLRDNORM* = uint32(1 shl 6)
    EPOLLRDBAND* = uint32(1 shl 7)
    EPOLLWRNORM* = uint32(1 shl 8)
    EPOLLWRBAND* = uint32(1 shl 9)
    EPOLLMSG* = uint32(1 shl 10)
    EPOLLRDHUP* = uint32(1 shl 13)
    EPOLLONESHOT* = uint32(1 shl 31)

  const
    EPOLL_CTL_ADD* = cint(1)
    EPOLL_CTL_MOD* = cint(2)
    EPOLL_CTL_DEL* = cint(3)
else:
  from std/posix import SocketHandle, close

  {.pragma: c_header, header: "<sys/epoll.h>".}

  type
    EpollHandle* = distinct cint
    EpollSocketHandle* = SocketHandle

  const
    EPOLLIN* = uint32(0x001)
    EPOLLPRI* = uint32(0x002)
    EPOLLOUT* = uint32(0x004)
    EPOLLERR* = uint32(0x008)
    EPOLLHUP* = uint32(0x010)
    EPOLLRDNORM* = uint32(0x040)
    EPOLLRDBAND* = uint32(0x080)
    EPOLLWRNORM* = uint32(0x100)
    EPOLLWRBAND* = uint32(0x200)
    EPOLLMSG* = uint32(0x400)
    EPOLLRDHUP* = uint32(0x2000)
    EPOLLEXCLUSIVE* = uint32(1 shl 28)
    EPOLLWAKEUP* = uint32(1 shl 29)
    EPOLLONESHOT* = uint32(1 shl 30)

  const
    EPOLL_CTL_ADD* = cint(1)
    EPOLL_CTL_DEL* = cint(2)
    EPOLL_CTL_MOD* = cint(3)

type
  EpollData* {.importc: "epoll_data_t", c_header, pure, final, union.} = object
    `ptr`*: pointer
    fd*: cint
    u32*: uint32
    u64*: uint64

  EpollEvent* {.importc: "struct epoll_event", c_header, pure, final.} = object
    events*: uint32
    data*: EpollData

proc epoll_create*(size: cint): EpollHandle {.importc: "epoll_create", c_header.}
proc epoll_create1*(size: cint): EpollHandle {.importc: "epoll_create1", c_header.}
proc epoll_ctl*(
  epfd: EpollHandle, op: cint, fd: EpollSocketHandle, event: ptr EpollEvent
): cint {.importc: "epoll_ctl", c_header.}

proc epoll_wait*(
  epfd: EpollHandle, events: ptr EpollEvent, maxEvents: cint, timeout: cint
): cint {.importc: "epoll_wait", c_header.}

when defined(windows):
  proc epoll_close*(epfd: EpollHandle): cint {.importc: "epoll_close", c_header.}
else:
  proc epoll_close*(epfd: EpollHandle): cint {.inline.} =
    close(cint(epfd))
