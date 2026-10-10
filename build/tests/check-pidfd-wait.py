#!/usr/bin/env python3
"""Check real pidfd polling and waitid semantics using only our own child."""
import errno
import fcntl
import os
import select
import signal
import subprocess


def main():
    def timed_out(signum, frame):
        raise TimeoutError("pidfd probe exceeded ten seconds")

    previous_handler = signal.signal(signal.SIGALRM, timed_out)
    signal.alarm(10)
    failed = False
    fd = None
    child = subprocess.Popen(["/bin/sh", "-c", "read ignored; exit 37"], stdin=subprocess.PIPE)
    try:
        fd = os.pidfd_open(child.pid, 0)
        print("pidfd_open: PASS", flush=True)
        kind = getattr(os, "P_PIDFD", 3)
        try:
            assert os.waitid(kind, fd, os.WEXITED | os.WNOHANG) is None
            print("waitid running child: PASS", flush=True)
        except OSError as error:
            print(f"waitid running child: FAIL errno={error.errno} ({error.strerror})", flush=True)
            failed = True
        flags = fcntl.fcntl(fd, fcntl.F_GETFL)
        fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        try:
            os.waitid(kind, fd, os.WEXITED)
        except OSError as error:
            if error.errno == errno.EAGAIN:
                print("nonblocking pidfd: PASS", flush=True)
            else:
                print(f"nonblocking pidfd: FAIL errno={error.errno}", flush=True)
                failed = True
        else:
            raise AssertionError("live nonblocking pidfd did not return EAGAIN")
        finally:
            fcntl.fcntl(fd, fcntl.F_SETFL, flags)
        poller = select.poll()
        poller.register(fd, select.POLLIN)
        assert not poller.poll(0), "live child unexpectedly readable"
        child.stdin.close()
        events = poller.poll(5000)
        assert any(event_fd == fd and mask & select.POLLIN for event_fd, mask in events), "exit not signalled"
        print("pidfd exit polling: PASS", flush=True)
        try:
            info = os.waitid(kind, fd, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            assert info is not None and info.si_pid == child.pid and info.si_status == 37
            assert info.si_code == os.CLD_EXITED
            reaped = os.waitid(kind, fd, os.WEXITED | os.WNOHANG)
            assert reaped == info
            child.returncode = 37
            print("waitid exit status / WNOWAIT / reap: PASS", flush=True)
            try:
                os.waitid(kind, fd, os.WEXITED | os.WNOHANG)
            except OSError as error:
                assert error.errno == errno.ECHILD
            else:
                raise AssertionError("reaped child did not return ECHILD")
        except OSError as error:
            print(f"waitid exit status: FAIL errno={error.errno} ({error.strerror})", flush=True)
            failed = True
        assert child.wait(timeout=5) == 37
    finally:
        if child.stdin and not child.stdin.closed:
            child.stdin.close()
        if fd is not None:
            os.close(fd)
        if child.poll() is None:
            child.kill()
        child.wait(timeout=5)
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous_handler)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
