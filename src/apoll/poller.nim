import ./priv/heap
import ./priv/epoll
import ./priv/macros
import ./priv/errnos

import yasync

when defined(windows):
  import std/winlean
else:
  import std/posix

import std/times
import std/tables
import std/monotimes
import std/oserrors

const MAX_EPOLL_EVENTS = 64

type
  Event* = enum
    kRead
    kWrite
    kNotify
    kError

  HandleType = enum
    kTimer
    kSocket

  Source* = object
    id*: uint64
    kind*: HandleType
    socket*: EpollSocketHandle

  SoltRange = kRead .. kWrite

  HandleData = object
    registeredEvents: set[Event]
    solt: array[SoltRange, TimerEnv]

  TimerEnv = ptr TimerEnvObj
  TimerEnvObj = object of Cont[Event]
    want: Event
    source: Source
    time: MonoTime
    node: InstruHeapNode

  PollErrorObj = object of OsError

  Poller* = ref PollerObj
  PollerObj = object
    time: MonoTime
    efd: EpollHandle
    uniq: uint64
    timers: InstruHeap
    infos: Table[uint64, HandleData]

proc newPollError(osErr: OSErrorCode): ref PollErrorObj =
  (ref PollErrorObj)(errorCode: int32(osErr), msg: osErrorMsg(osErr))

proc raisePollError(osErr: OSErrorCode) =
  raise (ref PollErrorObj)(errorCode: int32(osErr), msg: osErrorMsg(osErr))

proc `=destroy`(p: PollerObj) =
  assert p.infos.len <= 0
  assert p.timers.len <= 0

  let err = epoll_close(p.efd)
  if err != 0:
    discard

proc lessThen(a, b: var InstruHeapNode): bool =
  let t1 = containerOf(a.addr, TimerEnvObj, node)
  let t2 = containerOf(b.addr, TimerEnvObj, node)

  if t1.time < t2.time or (t1.time == t2.time and t1.source.id < t2.source.id):
    result = true

proc modifyEpoll(
    poller: Poller, id: uint64, fd: EpollSocketHandle, op: cint, events: set[Event]
): cint =
  var epv = default(EpollEvent)
  epv.events = EPOLLONESHOT or EPOLLRDHUP
  epv.data.u64 = id

  if kRead in events:
    epv.events = epv.events or EPOLLIN
  if kWrite in events:
    epv.events = epv.events or EPOLLOUT

  let res = epoll_ctl(poller.efd, op, cast[EpollSocketHandle](fd), epv.addr)
  if res != 0:
    result = errno

proc newPoller*(): Poller =
  let efd = epoll_create(1024)
  if cast[int](efd) <= 0:
    raisePollError(osLastError())

  let poller = Poller()

  poller.time = getMonoTime()
  poller.efd = efd
  poller.timers.initEmpty(lessThen)

  poller

template updateTimeNow(poller: Poller) =
  poller.time = getMonoTime()

template topTimer(poller: Poller): TimerEnv =
  let top = poller.timers.top
  containerOf(top, TimerEnvObj, node)

proc getPriv(poller: Poller, id: uint64): ptr HandleData =
  withValue poller.infos, id, data:
    result = data

proc registerSocket*(poller: Poller, socket: SocketHandle): Source =
  result.kind = kSocket
  result.id = succ(poller.uniq)
  result.socket = cast[EpollSocketHandle](socket)

  let err = modifyEpoll(poller, result.id, result.socket, EPOLL_CTL_ADD, {})
  if err != 0:
    raisePollError(osLastError())

  poller.uniq = result.id
  poller.infos[result.id] = default(HandleData)

proc registerTimer*(poller: Poller): Source =
  result.kind = kTimer
  result.id = succ(poller.uniq)
  result.socket = cast[EpollSocketHandle](0)

  poller.uniq = result.id
  poller.infos[result.id] = default(HandleData)

proc removeTimer(poller: Poller, timer: TimerEnv) =
  if not timer.node.isEmpty():
    remove(timer.node)

proc unregisterHandle*(poller: Poller, source: Source) {.raises: [].} =
  var data: HandleData
  if poller.infos.pop(source.id, data):
    case source.kind
    of kSocket:
      discard modifyEpoll(poller, source.id, source.socket, EPOLL_CTL_DEL, {})

      for idx in SoltRange:
        let env = move data.solt[idx]
        if env.isNil:
          continue

        removeTimer(poller, env)

        complete(env, kError)
    of kTimer:
      let env = move data.solt[kRead]
      if env.isNil:
        return

      removeTimer(poller, env)

      complete(env, kError)

proc completeEnv(poller: Poller, data: ptr HandleData, env: TimerEnv, res: Event) =
  removeTimer(poller, env)

  if not data.isNil:
    data.registeredEvents.excl(env.want)

    if env.source.kind != kTimer:
      data.solt[env.want] = nil

      if env.source.id > 0:
        let err = modifyEpoll(
          poller, env.source.id, env.source.socket, EPOLL_CTL_MOD, data.registeredEvents
        )
        if err != 0:
          fail(env, newPollError(osLastError()))
          return
    else:
      data.solt[kRead] = nil

  complete(env, res)

proc waitEpoll(poller: Poller, timeout: int) =
  var epvs: array[MAX_EPOLL_EVENTS, EpollEvent]
  let count = epoll_wait(poller.efd, epvs[0].addr, MAX_EPOLL_EVENTS, cint(timeout))

  if count < 0:
    if errno != EINTR:
      raisePollError(osLastError())
    return

  for i in 0 ..< count:
    let mask = uint32(epvs[i].events)
    let id = epvs[i].data.u64

    if id <= 0:
      continue

    let data = getPriv(poller, id)
    if data.isNil:
      assert false

    var events = default(set[Event])

    if (mask and EPOLLERR) != 0 or (mask and EPOLLHUP) != 0:
      events.incl(kRead)
      events.incl(kWrite)
    else:
      if (mask and EPOLLOUT) != 0:
        events.incl(kWrite)

      if (mask and EPOLLIN) != 0:
        events.incl(kRead)

    for event in events:
      completeEnv(poller, data, data.solt[event], event)

proc runTimer(poller: Poller) =
  while not poller.timers.isEmpty:
    let env = poller.topTimer
    if env.time > poller.time:
      break

    let data =
      if env.source.id > 0:
        getPriv(poller, env.source.id)
      else:
        nil

    completeEnv(poller, data, env, kNotify)

proc poll*(poller: Poller, milliseconds: int = -1) =
  updateTimeNow(poller)

  let time = block:
    if not poller.timers.isEmpty:
      let timer = poller.topTimer
      if timer.time >= poller.time:
        let dur = (timer.time - poller.time).inMilliseconds
        if milliseconds > 0:
          min(milliseconds, dur)
        else:
          dur
      else:
        0
    else:
      milliseconds

  waitEpoll(poller, time)

  updateTimeNow(poller)

  runTimer(poller)

proc pollImpl(
    poller: Poller,
    source: Source,
    data: ptr HandleData,
    want: Event,
    milliseconds: int,
    env: TimerEnv,
) {.asyncRaw.} =
  env.want = want
  env.source = source
  env.node.initEmpty()

  if not data.isNil:
    let events = data.registeredEvents + {want}

    if source.kind != kTimer:
      let err = modifyEpoll(poller, source.id, source.socket, EPOLL_CTL_MOD, events)
      if err != 0:
        fail(env, newPollError(osLastError()))
        return

      data.solt[want] = env
    else:
      data.solt[kRead] = env

    data.registeredEvents = events

  if milliseconds >= 0:
    env.time = getMonoTime() + initDuration(milliseconds = milliseconds)

    poller.timers.insert(env.node)

proc poll*(
    poller: Poller, source: Source, want: Event, milliseconds: int = -1
): Event {.async.} =
  assert milliseconds >= -1
  assert (source.kind == kTimer and want == kNotify) or
    (source.kind == kSocket and want in low(SoltRange) .. high(SoltRange))

  let data = getPriv(poller, source.id)
  if data.isNil:
    assert false

  if source.kind != kTimer:
    assert data.solt[want].isNil
  else:
    assert data.solt[kRead].isNil

  assert not (want in data.registeredEvents)

  await pollImpl(poller, source, data, want, milliseconds)

proc sleep*(poller: Poller, milliseconds: int) {.async.} =
  assert milliseconds >= 0

  let source = Source(id: 0, kind: kTimer, socket: default(EpollSocketHandle))

  let res = await pollImpl(poller, source, nil, kNotify, milliseconds)
  assert res == kNotify

template waitFor*[T](poller: Poller, f: Future[T]): T =
  block:
    type Env = asyncCallEnvType(f)
    when Env is void:
      while not f.finished:
        poll(poller)
      f.read()
    else:
      if false:
        discard f
      var e: Env
      asyncLaunchWithEnv(e, f)
      while not e.finished:
        poll(poller)
      e.read()
