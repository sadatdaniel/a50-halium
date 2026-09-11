#!/usr/bin/env python3
"""Exercise the actual vendor call_int_hook macro without booting a kernel.

Usage: python3 build/test-security-hook-default.py path/to/security/security.c
Requires a host C compiler. The tiny list adapter supplies zero or one hook;
the macro under test is extracted verbatim from the provided kernel source.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'^#define call_int_hook\(.*?^\}\)', source, re.M | re.S)
if not match:
    sys.exit('call_int_hook macro not found')

fixture = r'''
#include <stdio.h>
struct security_hook_list {
    struct security_hook_list *next;
    struct { int (*test)(void); } hook;
};
static struct { struct security_hook_list *test; } security_hook_heads;
static int integrity_result, hook_result, calls;
static int security_integrity_current(void) { return integrity_result; }
static int test_hook(void) { ++calls; return hook_result; }
#define list_for_each_entry(p, head, member) \
    for ((p) = *(head); (p); (p) = (p)->next)
'''
checks = r'''
int main(void) {
    int failures = 0, result;
    struct security_hook_list entry = { .hook.test = test_hook };
#define CHECK(label, value, expected) do { \
    result = (value); \
    if (result != (expected)) { \
        printf("FAIL %s: got %d expected %d\n", label, result, expected); \
        ++failures; \
    } \
} while (0)
    CHECK("empty secid hook", call_int_hook(test, -95), -95);
    CHECK("empty positive default", call_int_hook(test, 1), 1);
    CHECK("empty success default", call_int_hook(test, 0), 0);
    security_hook_heads.test = &entry;
    integrity_result = -13;
    CHECK("integrity denial", call_int_hook(test, -95), -13);
    CHECK("denied hook not called", calls, 0);
    integrity_result = 0;
    hook_result = 0;
    CHECK("registered success", call_int_hook(test, -95), 0);
    hook_result = -22;
    CHECK("registered error", call_int_hook(test, -95), -22);
    CHECK("registered call count", calls, 2);
    if (!failures) puts("PASS: default returns, integrity denial, registered hooks");
    return failures != 0;
}
'''
with tempfile.TemporaryDirectory() as work:
    cfile = pathlib.Path(work) / 'hook.c'
    exe = pathlib.Path(work) / 'hook'
    cfile.write_text(fixture + '\n' + match.group() + '\n' + checks)
    subprocess.run(['cc', '-std=gnu11', '-Wall', '-Wextra', '-Werror',
                    str(cfile), '-o', str(exe)], check=True)
    sys.exit(subprocess.run([str(exe)]).returncode)
