import apoll
import unittest

import std/times
import std/monotimes

let p = newPoller()

test "sleep":
  let milliseconds = 1234

  let a = getMonoTime()
  let fut = sleep(p, milliseconds)
  waitFor(p, fut)

  let dur = getMonoTime() - a
  check dur.inMilliseconds == milliseconds

test "timer":
  let timer = addTimer(p)
  defer:
    removeSource(p, timer)

  let milliseconds = 1234

  let a = getMonoTime()

  let fut = poll(p, timer, kNotify, milliseconds)
  let res = waitFor(p, fut)
  check res == kNotify

  let dur = getMonoTime() - a
  check dur.inMilliseconds == milliseconds
