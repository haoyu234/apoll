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
import ./priv/core

import yasync
import std/times
import std/tables
import std/monotimes
import std/oserrors

when defined(windows):
  from std/winlean import SocketHandle
else:
  from std/posix import SocketHandle

export Event

type
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
    poller: EverntCore
    time: MonoTime
    idSeq: uint64
    timers: InstruHeap
    infos: Table[uint64, HandleData]

proc `=destroy`(p: PollerObj) =
  assert p.infos.len <= 0
  assert p.timers.len <= 0

  close(p.poller)

proc lessThen(a, b: ptr InstruHeapNode): bool =
  let t1 = containerOf(a, TimerEnvObj, node)
  let t2 = containerOf(b, TimerEnvObj, node)

  if t1.time < t2.time or (t1.time == t2.time and t1.source.id < t2.source.id):
    result = true

proc newPoller*(): Poller =
  let poller = Poller()

  poller.time = getMonoTime()
  poller.poller = createCore()
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

proc addSocket*(poller: Poller, socket: SocketHandle): Source =
  result.kind = kSocket
  result.id = succ(poller.idSeq)
  result.socket = socket

  let err = poller.poller.add(result.id, result.socket)
  if err != 0:
    raiseOSError(osLastError())

  poller.idSeq = result.id
  poller.infos[result.id] = default(HandleData)

proc addTimer*(poller: Poller): Source =
  result.kind = kTimer
  result.id = succ(poller.idSeq)
  result.socket = cast[SocketHandle](0)

  poller.idSeq = result.id
  poller.infos[result.id] = default(HandleData)

proc removeTimer(poller: Poller, timer: TimerEnv) =
  if not timer.node.isEmpty():
    remove(timer.node)

proc removeSource*(poller: Poller, source: Source) {.raises: [].} =
  var data: HandleData
  if poller.infos.pop(source.id, data):
    case source.kind
    of kSocket:
      discard poller.poller.remove(source.id, source.socket)

      for idx in SlotRange:
        let env = move data.slot[idx]
        if env.isNil:
          continue

        removeTimer(poller, env)

        complete(env, kInterrupt)
    of kTimer:
      let env = move data.slot[kRead]
      if env.isNil:
        return

      removeTimer(poller, env)

      complete(env, kInterrupt)

proc completeEnv(poller: Poller, data: ptr HandleData, env: TimerEnv, res: Event) =
  removeTimer(poller, env)

  if not data.isNil:
    data.registeredEvents.excl(env.want)

    if env.source.kind != kTimer:
      data.slot[env.want] = nil

      if env.source.id > 0:
        let err =
          poller.poller.update(env.source.id, env.source.socket,
              data.registeredEvents)
        if err != 0:
          fail(env, newOSError(osLastError()))
          return
    else:
      data.slot[kRead] = nil

  complete(env, res)

proc processEvents(poller: Poller, id: uint64, events: set[
    Event]) {.inline.} =
  let data = getPriv(poller, id)
  if data.isNil:
    assert false

  for idx in SlotRange:
    let env = data.slot[idx]
    if not env.isNil:
      if idx in events:
        completeEnv(poller, data, data.slot[idx], idx)
      elif kError in events:
        completeEnv(poller, data, data.slot[idx], kError)

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

  for id, events in poll(poller.poller, time):
    processEvents(poller, id, events)

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
      let err = poller.poller.update(source.id, source.socket, events)
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
