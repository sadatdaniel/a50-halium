#!/usr/bin/env python3
"""Exercise the actual driver function's cached intent without hardware access."""
from pathlib import Path
import subprocess
import signal
import sys
import tempfile

source = Path(sys.argv[1]).read_text()
start = source.index('static int dwc3_gadget_pullup(')
end = source.index('\nstatic irqreturn_t dwc3_interrupt', start)
function = source[start:end]
stubs = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
enum { SET_DPPULLUP_ENABLE, SET_DPPULLUP_DISABLE };
struct usb_otg { int state; };
struct dwc3_otg { struct usb_otg otg; };
struct usb_gadget { int unused; };
struct dwc3 {
    void *dev, *usb2_generic_phy, *usb3_generic_phy;
    struct dwc3_otg *dotg;
    int lock;
    bool softconnect, vbus_session;
    bool is_not_vbus_pad;
};
static struct dwc3 controller;
static bool suspended;
static int hardware_calls;
#define gadget_to_dwc(g) (&controller)
#define pm_runtime_suspended(dev) suspended
#define spin_lock_irqsave(lock, flags) ((flags) = 0)
#define spin_unlock_irqrestore(lock, flags) ((void)(flags))
#define pr_info(...) ((void)0)
#define dev_info(...) ((void)0)
static void dwc3_soft_reset(struct dwc3 *dwc) {
    assert(!suspended); hardware_calls++;
}
static void phy_tune(void *phy, int state) {
    assert(!suspended); hardware_calls++;
}
static void phy_set(void *phy, int state, void *unused) {
    assert(!suspended); hardware_calls++;
}
static int dwc3_gadget_run_stop(struct dwc3 *dwc, int on, bool suspend) {
    assert(!suspended && dwc->vbus_session); hardware_calls++; return 0;
}
'''
tests = r'''
int main(void) {
    struct dwc3_otg otg = {0};
    struct usb_gadget gadget = {0};
    controller.dotg = &otg;
    /* Removal powers down before FunctionFS asks to disconnect. */
    controller.softconnect = true;
    suspended = true;
    assert(dwc3_gadget_pullup(&gadget, 0) == 0);
    assert(!controller.softconnect && hardware_calls == 0);
    /* On rebind, the request must no longer be discarded as already on. */
    suspended = false;
    controller.vbus_session = true;
    assert(dwc3_gadget_pullup(&gadget, 9) == 0);
    assert(controller.softconnect && hardware_calls == 4);
    assert(dwc3_gadget_pullup(&gadget, 1) == 0);
    assert(hardware_calls == 4);
    assert(dwc3_gadget_pullup(&gadget, 0) == 0);
    assert(!controller.softconnect && hardware_calls == 5);
    controller.vbus_session = false;
    assert(dwc3_gadget_pullup(&gadget, 1) == 0);
    assert(controller.softconnect && hardware_calls == 5);
    return 0;
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'test.c').write_text(stubs + function + tests)
    subprocess.run(['cc', '-std=c11', '-o', str(path / 'test'), str(path / 'test.c')], check=True)
    result = subprocess.run([str(path / 'test')])
    if sys.argv[2:] == ['--expect-failure']:
        assert result.returncode == -signal.SIGABRT, result.returncode
        print('PASS: original driver fails the suspended-disconnect assertion')
    else:
        result.check_returncode()
        print('PASS: suspended disconnect clears intent; resumed rebind runs; no powered-off hardware access')
