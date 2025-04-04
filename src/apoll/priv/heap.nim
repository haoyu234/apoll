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

type
  LessThen = proc(a, b: var InstruHeapNode): bool {.raises: [].}

  InstruHeap* = object
    len: int
    top: ptr InstruHeapNode
    lessThan: LessThen

  InstruHeapNode* = object
    heap: ptr InstruHeap
    left: ptr InstruHeapNode
    right: ptr InstruHeapNode
    parent: ptr InstruHeapNode

  TraverseResult = object
    parentAddr: ptr ptr InstruHeapNode
    nodeAddr: ptr ptr InstruHeapNode

template len*(h: InstruHeap): int =
  h.len

template top*(h: InstruHeap): ptr InstruHeapNode =
  h.top

template isEmpty*(h: InstruHeap): bool =
  isNil(h.top)

template isEmpty*(n: InstruHeapNode): bool =
  isNil(n.heap)

proc initEmpty*(h: var InstruHeap, lessThan: LessThen) {.inline.} =
  h.len = 0
  h.top = nil
  h.lessThan = lessThan

proc initEmpty*(h: var InstruHeapNode) {.inline.} =
  reset(h)

proc swap(h: var InstruHeap, a, b: var InstruHeapNode) =
  swap(a, b)

  a.parent = b.addr

  var sibling = block:
    if b.left == b.addr:
      b.left = a.addr
      b.right
    else:
      b.right = a.addr
      b.left

  if not isNil(sibling):
    sibling[].parent = b.addr

  if not isNil(a.left):
    a.left.parent = a.addr

  if not isNil(a.right):
    a.right.parent = a.addr

  if isNil(b.parent):
    h.top = b.addr
  elif b.parent.left == a.addr:
    b.parent.left = b.addr
  else:
    b.parent.right = b.addr

proc traverse(h: var InstruHeap, n: int): TraverseResult =
  var k: uint32 = 0
  var path: uint32 = 0

  var num = uint32(n)
  while num >= 2:
    path = (path shl 1) or (num and 0x1)
    num = num shr 1
    inc k

  var c = h.top.addr
  var p = h.top.addr

  while k > 0:
    p = c
    if (path and 0x1) > 0:
      c = c[].right.addr
    else:
      c = c[].left.addr

    path = path shr 1
    dec k

  TraverseResult(parentAddr: p, nodeAddr: c)

proc shiftUp(h: var InstruHeap, n: var InstruHeapNode) {.inline.} =
  let lessThan = h.lessThan

  while not isNil(n.parent) and lessThan(n, n.parent[]):
    swap(h, n.parent[], n)

proc insert*(h: var InstruHeap, n: var InstruHeapNode) =
  assert n.isEmpty()

  n.heap = h.addr

  let r = traverse(h, succ h.len)
  n.parent = r.parentAddr[]
  r.nodeAddr[] = n.addr

  inc h.len

  shiftUp(h, n)

proc remove*(n: var InstruHeapNode) =
  assert not n.isEmpty()

  let h = n.heap

  var c = block:
    let r = traverse(h[], h.len)
    var result = r.nodeAddr[]
    r.nodeAddr[] = nil
    result

  dec h.len

  if c == n.addr:
    if c == h.top:
      h.top = nil

    n.initEmpty()
    return

  c[] = n

  if not isNil(c.left):
    c.left.parent = c

  if not isNil(c.right):
    c.right.parent = c

  if isNil(n.parent):
    h.top = c
  elif n.parent.left == n.addr:
    n.parent.left = c
  else:
    n.parent.right = c

  let lessThan = h.lessThan

  while true:
    var s = c

    if not isNil(c.left) and lessThan(c.left[], s[]):
      s = c.left

    if not isNil(c.right) and lessThan(c.right[], s[]):
      s = c.right

    if s != c:
      swap(h[], c[], s[])
      continue

    break

  shiftUp(h[], c[])

  n.initEmpty()

proc pop*(h: var InstruHeap): ptr InstruHeapNode {.inline.} =
  let n = h.top
  remove(h.top[])
  n
