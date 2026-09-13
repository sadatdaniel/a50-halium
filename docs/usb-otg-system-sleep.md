# USB OTG system-sleep candidate

Enable with `--usb-otg-sleep-fix` on a fresh source volume. For aa9, retain
`--watchdog-freezer-fix`, full profile and UBports AppArmor. Do not include
ABOX isolation. Hardware validation is pending.

On aa8, two freezer cycles and the devices-stage test returned without the
earlier watchdog cascade. The attached gadget nevertheless failed enumeration
on Windows after device suspend (Device Descriptor Request Failed). Wi-Fi
survived. A software UDC reconnect recovered enumeration; re-establishing the
phone's USB addresses recovered SSH without rebooting.

A controlled devices-stage comparison detached g1 before suspend and restored
it afterward. It returned normally and USB enumerated/SSH worked immediately.
The runtime DT says dr_mode=otg, with debugfs reporting device mode. In the
pinned core.c, the OTG branch only clears event buffers during suspend and
does not call gadget suspend/resume. These observations motivate an active
gadget quiesce/restore pair; they do not yet prove this kernel patch fixes it.

The candidate:

- Quiesces only a bound, active B-peripheral gadget and remembers that action.
- Restores it only when still in device role with a bound driver, VBUS and
  software connection requested. Disconnected/host OTG paths remain unchanged.
- Serializes role checks with the FSM mutex and hardware changes with the
  driver spinlock. IRQ synchronization occurs outside both locks. This also
  corrects the existing peripheral path's wait under the spinlock taken by
  dwc3_interrupt.
- Propagates stop/start errors and balances the runtime PM reference even
  when a resume callback fails. The vendor PHY initialization stays unchanged.

The tests apply the patch to the exact source and compile the actual gadget,
common suspend/resume, and resume wrapper functions against mocked primitives.
They check repeated pairs, inactive/unbound/host OTG, unplug/role change/unbind/
soft disconnect during sleep, unmatched resume, callback failures, PM reference
balance, existing host/peripheral paths, and IRQ waits outside both locks.
Compiled tests and build-shell syntax pass. Mocks cannot establish controller
behavior or real concurrent role-switch correctness; phone tests are required.

Before any deeper sleep test, verify normal boot, protected recovery image,
unchanged security configuration, then one devices-stage cycle with USB attached.
Require automatic re-enumeration, network continuity/recovery and delayed health
checks. Keep Wi-Fi available. A five-second return alone is insufficient.

No raw device logs are committed. aa8 remains the published watchdog milestone.
