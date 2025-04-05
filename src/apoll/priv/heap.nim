# instru/heap.nim
# intrusive heap implementation

# MIT License

# Copyright (c) 2023 haoyu

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

import std/bitops

type
  InstruLessThen = proc(a, b: ptr InstruHeapNode): bool {.raises: [].}

  InstruHeap* = object
    len: int
    top: ptr InstruHeapNode
    lessThen: InstruLessThen

  InstruHeapNode* = object
    heap: ptr InstruHeap
    left: ptr InstruHeapNode
    right: ptr InstruHeapNode
    parent: ptr InstruHeapNode

  InstruTraverseResult = object
    parentAddr: ptr InstruHeapNode
    nodeAddr: ptr ptr InstruHeapNode

template len*(h: InstruHeap): int =
  h.len

template top*(h: InstruHeap): ptr InstruHeapNode =
  h.top

template isEmpty*(h: InstruHeap): bool =
  isNil(h.top)

template isEmpty*(n: InstruHeapNode): bool =
  isNil(n.heap)

proc initEmpty*(h: var InstruHeap, lessThen: InstruLessThen) {.inline.} =
  h.len = 0
  h.top = nil
  h.lessThen = lessThen

proc initEmpty*(h: var InstruHeapNode) {.inline.} =
  reset(h)

proc swap(h: ptr InstruHeap, a, b: ptr InstruHeapNode) {.inline.} =
  swap(a.left, b.left)
  swap(a.right, b.right)
  swap(a.parent, b.parent)

  a.parent = b

  let sibling =
    if b.left == b:
      b.left = a
      b.right
    else:
      b.right = a
      b.left

  if not isNil(sibling):
    sibling.parent = b

  if not isNil(a.left):
    a.left.parent = a

  if not isNil(a.right):
    a.right.parent = a

  if isNil(b.parent):
    h.top = b
  elif b.parent.left == a:
    b.parent.left = b
  else:
    b.parent.right = b

proc traverse(h: ptr InstruHeap, n: int): InstruTraverseResult {.inline.} =
  var c = h.top.addr
  var p = default(ptr InstruHeapNode)

  if n >= 2:
    var count = sizeof(n) * 8 - countLeadingZeroBits(n) - 1
    while count > 0:
      dec count

      p = c[]

      let mask = 1 shl count
      if (n and mask) > 0:
        c = c.right.addr
      else:
        c = c.left.addr

  InstruTraverseResult(parentAddr: p, nodeAddr: c)

proc shiftUp(h: ptr InstruHeap, n: ptr InstruHeapNode) {.inline.} =
  let lessThen = h.lessThen

  while not isNil(n.parent) and lessThen(n, n.parent):
    swap(h, n.parent, n)

proc insert*(h: var InstruHeap, n: var InstruHeapNode) =
  assert n.isEmpty()

  inc h.len

  let r = traverse(h.addr, h.len)
  r.nodeAddr[] = n.addr

  n.heap = h.addr
  n.parent = r.parentAddr

  shiftUp(h.addr, n.addr)

proc remove*(n: var InstruHeapNode) =
  assert not n.isEmpty()

  let h = n.heap

  let c = block:
    let r = traverse(h, h.len)
    move r.nodeAddr[]

  dec h.len

  if c == n.addr:
    if c == h.top:
      h.top = nil

    n.initEmpty()
    return

  c[] = n

  if not isNil(n.left):
    n.left.parent = c

  if not isNil(n.right):
    n.right.parent = c

  if isNil(n.parent):
    h.top = c
  elif n.parent.left == n.addr:
    n.parent.left = c
  else:
    n.parent.right = c

  let lessThen = h.lessThen

  while true:
    var s = c

    if not isNil(c.left) and lessThen(c.left, s):
      s = c.left

    if not isNil(c.right) and lessThen(c.right, s):
      s = c.right

    if s != c:
      swap(h, c, s)
      continue

    break

  shiftUp(h, c)

  n.initEmpty()

proc pop*(h: var InstruHeap): ptr InstruHeapNode {.inline.} =
  let n = h.top
  remove(h.top[])
  n
