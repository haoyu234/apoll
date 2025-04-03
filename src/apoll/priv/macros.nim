import std/macros

macro containerOf*(p: pointer, a: typedesc, b: untyped): untyped =
  let pt = newNimNode(nnkPtrTy).add(a)

  result = quote:
    let
      offset = offsetof(`a`, `b`)
      base = cast[uint](`p`) - cast[uint](offset)
    cast[`pt`](base)
