import std/oserrors

type
  Core = enum
    kEpoll
    kKqueue

  Event* = enum
    kRead
    kWrite
    kNotify
    kInterrupt
    kError

const MAX_POLL_EVENTS = 64

when defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd) or
    defined(dragonfly):
  import std/kqueue
  const eventCore = kKqueue
elif defined(windows):
  import ./wepoll
  const eventCore = kEpoll
else:
  import std/epoll
  const eventCore = kEpoll

when defined(windows):
  import std/winlean

  type EverntCore* = object
    poll: WEpoll

else:
  import std/posix

  type EverntCore* = object
    poll: cint

    when eventCore == kKqueue:
      changes: seq[KEvent]

when eventCore == kEpoll:
  proc createCore*(): EverntCore =
    let poll = epoll_create(1024)

    when defined(windows):
      if poll.isNil:
        raiseOSError(osLastError())
    else:
      if poll < 0:
        raiseOSError(osLastError())

    EverntCore(poll: poll)

  proc add*(poller: var EverntCore, id: uint64, socket: SocketHandle): cint =
    var epv = default(EpollEvent)
    epv.data.u64 = id

    let err = epoll_ctl(poller.poll, cint(EPOLL_CTL_ADD), socket, epv.addr)
    if err != 0:
      result = errno

  proc update*(
      poller: var EverntCore, id: uint64, socket: SocketHandle, events: set[Event]
  ): cint =
    var epv = default(EpollEvent)
    epv.events = EPOLLONESHOT or EPOLLRDHUP
    epv.data.u64 = id

    if kRead in events:
      epv.events = epv.events or EPOLLIN
    if kWrite in events:
      epv.events = epv.events or EPOLLOUT

    let err = epoll_ctl(poller.poll, cint(EPOLL_CTL_MOD), socket, epv.addr)
    if err != 0:
      result = errno

  proc remove*(poller: var EverntCore, id: uint64, socket: SocketHandle): cint =
    discard id

    let err = epoll_ctl(poller.poll, cint(EPOLL_CTL_DEL), socket, nil)
    if err != 0:
      result = errno

elif eventCore == kKqueue:
  proc createCore*(): EverntCore =
    let poll = kqueue()
    if poll <= 0:
      raiseOSError(osLastError())

    EverntCore(poll: poll)

  template registerEvent(
      poller: var EverntCore, id: uint64, socket: SocketHandle, filter: cint, ctrl: cint
  ) =
    var event = default(KEvent)
    EV_SET(
      event.addr,
      cast[uint](socket),
      cshort(filter),
      cushort(ctrl),
      0,
      0,
      cast[pointer](id),
    )

    poller.changes.add(event)

  proc add*(poller: var EverntCore, id: uint64, socket: SocketHandle): cint =
    registerEvent(poller, id, socket, EVFILT_READ, EV_ADD or EV_DISABLE)
    registerEvent(poller, id, socket, EVFILT_WRITE, EV_ADD or EV_DISABLE)

  proc update*(
      poller: var EverntCore, id: uint64, socket: SocketHandle, events: set[Event]
  ): cint =
    if kRead in events:
      registerEvent(poller, id, socket, EVFILT_READ, EV_ADD or EV_ENABLE)
    else:
      registerEvent(poller, id, socket, EVFILT_READ, EV_ADD or EV_DISABLE)

    if kWrite in events:
      registerEvent(poller, id, socket, EVFILT_WRITE, EV_ADD or EV_ENABLE)
    else:
      registerEvent(poller, id, socket, EVFILT_WRITE, EV_ADD or EV_DISABLE)

  proc remove*(poller: var EverntCore, id: uint64, socket: SocketHandle): cint =
    registerEvent(poller, id, socket, EVFILT_WRITE, EV_DELETE)
    registerEvent(poller, id, socket, EVFILT_WRITE, EV_DELETE)

proc close*(poller: EverntCore) {.raises: [].} =
  when defined(windows):
    let err = epoll_close(poller.poll)
  else:
    let err = close(poller.poll)

  if err != 0:
    discard

when eventCore == kEpoll:
  iterator poll*(poller: var EverntCore, timeout: int): (uint64, set[Event]) =
    var epvs: array[MAX_POLL_EVENTS, EpollEvent]
    let count = epoll_wait(poller.poll, epvs[0].addr, MAX_POLL_EVENTS, cint(timeout))

    if count < 0:
      if errno != EINTR:
        raiseOSError(osLastError())
    else:
      for i in 0 ..< count:
        let mask = uint32(epvs[i].events)
        let id = epvs[i].data.u64

        if id <= 0:
          continue

        var events = default(set[Event])

        if (mask and EPOLLERR) != 0 or (mask and EPOLLHUP) != 0:
          events.incl(kError)
        else:
          if (mask and EPOLLOUT) != 0:
            events.incl(kWrite)

          if (mask and EPOLLIN) != 0:
            events.incl(kRead)

        yield (id, events)

elif eventCore == kKqueue:
  iterator poll*(poller: var EverntCore, timeout: int): (uint64, set[Event]) =
    var
      tv = default(Timespec)
      ptv = default(ptr Timespec)
      changes = default(ptr KEvent)
      epvs: array[MAX_POLL_EVENTS, KEvent]

    if timeout >= 0:
      if timeout >= 1000:
        tv.tv_sec = posix.Time(timeout div 1_000)
        tv.tv_nsec = (timeout %% 1_000) * 1_000_000
      else:
        tv.tv_sec = posix.Time(0)
        tv.tv_nsec = timeout * 1_000_000

      ptv = tv.addr

    if len(poller.changes) > 0:
      changes = poller.changes[0].addr

    let count = kevent(
      poller.poll,
      changes,
      cint(poller.changes.len),
      addr(epvs[0]),
      cint(MAX_POLL_EVENTS),
      ptv,
    )

    poller.changes.setLen(0)

    if count < 0:
      if errno != EINTR:
        raiseOSError(osLastError())
    else:
      for i in 0 ..< count:
        let mask = uint32(epvs[i].flags)
        let id = cast[uint64](epvs[i].udata)

        if id <= 0:
          continue

        var events = default(set[Event])

        if (mask and EV_ERROR) != 0 or (mask and EV_EOF) != 0:
          events.incl(kError)

        case epvs[i].filter
        of EVFILT_READ:
          events.incl(kRead)
        of EVFILT_WRITE:
          events.incl(kWrite)
        else:
          discard

        yield (id, events)
