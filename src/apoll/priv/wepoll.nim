# apoll: A simple asynchronous event system using epoll and wepoll,
# supporting only sockets and timers.

# MIT License

# Copyright (c) 2025 haoyu

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

{.passL: "-lws2_32".}
{.compile: "wepoll/wepoll.c".}

import os
from std/winlean import SocketHandle

{.pragma: c_header, header: currentSourcePath().splitPath.head & "/wepoll/wepoll.h".}

type
  WEpoll* {.importc: "HANDLE", c_header.} = pointer
  WEpollSocket* {.importc: "SOCKET", c_header.} = SocketHandle

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

type
  EpollData* {.importc: "epoll_data_t", c_header, pure, final, union.} = object
    `ptr`*: pointer
    fd*: cint
    u32*: uint32
    u64*: uint64

  EpollEvent* {.importc: "struct epoll_event", c_header, pure, final.} = object
    events*: uint32
    data*: EpollData

proc epoll_create*(size: cint): WEpoll {.importc: "epoll_create", c_header.}
proc epoll_create1*(size: cint): WEpoll {.importc: "epoll_create1", c_header.}
proc epoll_ctl*(
  epfd: WEpoll, op: cint, fd: WEpollSocket, event: ptr EpollEvent
): cint {.importc: "epoll_ctl", c_header.}

proc epoll_wait*(
  epfd: WEpoll, events: ptr EpollEvent, maxEvents: cint, timeout: cint
): cint {.importc: "epoll_wait", c_header.}

proc epoll_close*(epfd: WEpoll): cint {.importc: "epoll_close", c_header.}
