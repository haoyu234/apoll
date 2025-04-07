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

import ./priv/heap
import ./priv/macros
import ./priv/errnos

import yasync

type EventCore = enum
  kEpoll
  kKqueue

when defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd) or
    defined(dragonfly):
  import std/kqueue

  const eventCore = kKqueue
elif defined(windows):
  import ./priv/wepoll

  import std/winlean

  type EventCoreHandle = WEpoll

  const eventCore = kEpoll
else:
  import std/epoll
  import std/posix

  type EventCoreHandle = cint

  const eventCore = kEpoll

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
    socket*: SocketHandle

  SlotRange = kRead .. kWrite

  HandleData = object
    registeredEvents: set[Event]
    slot: array[SlotRange, TimerEnv]

  TimerEnv = ptr TimerEnvObj
  TimerEnvObj = object of Cont[Event]
    want: Event
    source: Source
    time: MonoTime
    node: InstruHeapNode

  Poller* = ref PollerObj
  PollerObj = object
    time: MonoTime
    poll: EventCoreHandle
    uniq: uint64
    timers: InstruHeap
    infos: Table[uint64, HandleData]

when eventCore == kEpoll:
  proc createEpoll(): EventCoreHandle =
    let poll = epoll_create(1024)

    when defined(windows):
      if poll.isNil:
        raiseOSError(osLastError())
    else:
      if poll < 0:
        raiseOSError(osLastError())

    poll

  proc modifyEpoll(
      poll: EventCoreHandle,
      id: uint64,
      socket: SocketHandle,
      op: cint,
      events: set[Event],
  ): cint {.raises: [].} =
    var epv = default(EpollEvent)
    epv.events = EPOLLONESHOT or EPOLLRDHUP
    epv.data.u64 = id

    if kRead in events:
      epv.events = epv.events or EPOLLIN
    if kWrite in events:
      epv.events = epv.events or EPOLLOUT

    let err = epoll_ctl(poll, op, socket, epv.addr)
    if err != 0:
      result = errno

  proc closeEpoll(poll: EventCoreHandle): cint {.raises: [].} =
    when defined(windows):
      let err = epoll_close(poll)
    else:
      let err = close(poll)

    if err != 0:
      result = errno

elif eventCore == kKqueue:
  discard

proc `=destroy`(p: PollerObj) =
  assert p.infos.len <= 0
  assert p.timers.len <= 0

  when eventCore == kEpoll:
    discard closeEpoll(p.poll)

proc lessThen(a, b: ptr InstruHeapNode): bool =
  let t1 = containerOf(a, TimerEnvObj, node)
  let t2 = containerOf(b, TimerEnvObj, node)

  if t1.time < t2.time or (t1.time == t2.time and t1.source.id < t2.source.id):
    result = true

proc newPoller*(): Poller =
  when eventCore == kEpoll:
    let poll = createEpoll()

  let poller = Poller()

  poller.time = getMonoTime()
  poller.poll = poll
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
  result.socket = socket

  when eventCore == kEpoll:
    let err = modifyEpoll(poller.poll, result.id, result.socket, EPOLL_CTL_ADD, {})
    if err != 0:
      raiseOSError(osLastError())

  poller.uniq = result.id
  poller.infos[result.id] = default(HandleData)

proc registerTimer*(poller: Poller): Source =
  result.kind = kTimer
  result.id = succ(poller.uniq)
  result.socket = cast[SocketHandle](0)

  poller.uniq = result.id
  poller.infos[result.id] = default(HandleData)

proc removeTimer(poller: Poller, timer: TimerEnv) =
  if not timer.node.isEmpty():
    remove(timer.node)

proc unregisterSource*(poller: Poller, source: Source) {.raises: [].} =
  var data: HandleData
  if poller.infos.pop(source.id, data):
    case source.kind
    of kSocket:
      when eventCore == kEpoll:
        discard modifyEpoll(poller.poll, source.id, source.socket, EPOLL_CTL_DEL, {})

      for idx in SlotRange:
        let env = move data.slot[idx]
        if env.isNil:
          continue

        removeTimer(poller, env)

        complete(env, kError)
    of kTimer:
      let env = move data.slot[kRead]
      if env.isNil:
        return

      removeTimer(poller, env)

      complete(env, kError)

proc completeEnv(poller: Poller, data: ptr HandleData, env: TimerEnv, res: Event) =
  removeTimer(poller, env)

  if not data.isNil:
    data.registeredEvents.excl(env.want)

    if env.source.kind != kTimer:
      data.slot[env.want] = nil

      if env.source.id > 0:
        when eventCore == kEpoll:
          let err = modifyEpoll(
            poller.poll, env.source.id, env.source.socket, EPOLL_CTL_MOD,
            data.registeredEvents,
          )
          if err != 0:
            fail(env, newOSError(osLastError()))
            return
    else:
      data.slot[kRead] = nil

  complete(env, res)

when eventCore == kEpoll:
  proc waitEpoll(poller: Poller, timeout: int) =
    var epvs: array[MAX_EPOLL_EVENTS, EpollEvent]
    let count = epoll_wait(poller.poll, epvs[0].addr, MAX_EPOLL_EVENTS, cint(timeout))

    if count < 0:
      if errno != EINTR:
        raiseOSError(osLastError())
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
        completeEnv(poller, data, data.slot[event], event)

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

  when eventCore == kEpoll:
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
      when eventCore == kEpoll:
        let err =
          modifyEpoll(poller.poll, source.id, source.socket, EPOLL_CTL_MOD, events)
        if err != 0:
          fail(env, newOSError(osLastError()))
          return

      data.slot[want] = env
    else:
      data.slot[kRead] = env

    data.registeredEvents = events

  if milliseconds >= 0:
    env.time = getMonoTime() + initDuration(milliseconds = milliseconds)

    poller.timers.insert(env.node)

proc poll*(
    poller: Poller, source: Source, want: Event, milliseconds: int = -1
): Event {.async.} =
  assert milliseconds >= -1
  assert (source.kind == kTimer and want == kNotify) or
    (source.kind == kSocket and want in low(SlotRange) .. high(SlotRange))

  let data = getPriv(poller, source.id)
  if data.isNil:
    assert false

  if source.kind != kTimer:
    assert data.slot[want].isNil
  else:
    assert data.slot[kRead].isNil

  assert not (want in data.registeredEvents)

  await pollImpl(poller, source, data, want, milliseconds)

proc sleep*(poller: Poller, milliseconds: int) {.async.} =
  assert milliseconds >= 0

  let source = Source(id: 0, kind: kTimer, socket: default(SocketHandle))

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
