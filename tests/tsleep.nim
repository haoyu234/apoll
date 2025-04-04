import apoll
import unittest

import std/times
import std/monotimes

let p = newPoller()

test "sleep":
  let milliseconds = 1234

  let a = getMonoTime()
  waitFor p, sleep(p, milliseconds)

  let dur = getMonoTime() - a
  check dur.inMilliseconds == milliseconds

test "timer":
  let timer = registerTimer(p)
  defer:
    unregisterSource(p, timer)

  let milliseconds = 1234

  let a = getMonoTime()

  let fut = poll(p, timer, kNotify, milliseconds)
  let res = waitFor(p, fut)
  check res == kNotify

  let dur = getMonoTime() - a
  check dur.inMilliseconds == milliseconds
