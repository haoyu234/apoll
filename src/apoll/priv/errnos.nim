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

when defined(windows):
  const
    E2BIG* = cint(7)
    EACCES* = cint(13)
    EAGAIN* = cint(11)
    EBADF* = cint(9)
    EBUSY* = cint(16)
    ECHILD* = cint(10)
    EDEADLK* = cint(36)
    EDEADLOCK* = cint(36)
    EDOM* = cint(33)
    EEXIST* = cint(17)
    EFAULT* = cint(14)
    EFBIG* = cint(27)
    EILSEQ* = cint(42)
    EINTR* = cint(4)
    EINVAL* = cint(22)
    EIO* = cint(5)
    EISDIR* = cint(21)
    EMFILE* = cint(24)
    EMLINK* = cint(31)
    ENAMETOOLONG* = cint(38)
    ENFILE* = cint(23)
    ENODEV* = cint(19)
    ENOENT* = cint(2)
    ENOEXEC* = cint(8)
    ENOLCK* = cint(39)
    ENOMEM* = cint(12)
    ENOSPC* = cint(28)
    ENOSYS* = cint(40)
    ENOTDIR* = cint(20)
    ENOTEMPTY* = cint(41)
    ENOTTY* = cint(25)
    ENXIO* = cint(6)
    EPERM* = cint(1)
    EPIPE* = cint(32)
    ERANGE* = cint(34)
    EROFS* = cint(30)
    ESPIPE* = cint(29)
    ESRCH* = cint(3)
    EXDEV* = cint(18)
    STRUNCATE* = cint(80)

  var errno* {.importc, header: "<errno.h>".}: cint
else:
  import std/posix

  export errno
  export
    E2BIG, EACCES, EADDRINUSE, EADDRNOTAVAIL, EAFNOSUPPORT, EAGAIN, EALREADY, EBADF,
    EBADMSG, EBUSY, ECANCELED, ECHILD, ECONNABORTED, ECONNREFUSED, ECONNRESET, EDEADLK,
    EDESTADDRREQ, EDOM, EDQUOT, EEXIST, EFAULT, EFBIG, EHOSTUNREACH, EIDRM, EILSEQ,
    EINPROGRESS, EINTR, EINVAL, EIO, EISCONN, EISDIR, ELOOP, EMFILE, EMLINK, EMSGSIZE,
    EMULTIHOP, ENAMETOOLONG, ENETDOWN, ENETRESET, ENETUNREACH, ENFILE, ENOBUFS, ENODATA,
    ENODEV, ENOENT, ENOEXEC, ENOLCK, ENOLINK, ENOMEM, ENOMSG, ENOPROTOOPT, ENOSPC,
    ENOSR, ENOSTR, ENOSYS, ENOTCONN, ENOTDIR, ENOTEMPTY, ENOTSOCK, ENOTSUP, ENOTTY,
    ENXIO, EOPNOTSUPP, EOVERFLOW, EPERM, EPIPE, EPROTO, EPROTONOSUPPORT, EPROTOTYPE,
    ERANGE, EROFS, ESPIPE, ESRCH, ESTALE, ETIME, ETIMEDOUT, ETXTBSY, EWOULDBLOCK, EXDEV
