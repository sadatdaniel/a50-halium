from pathlib import Path
import subprocess

base=Path('/tmp/usb-sleep-test')
for name in ('core.c','core.h','gadget.c'):
    dst=base/'drivers/usb/dwc3'/name
    dst.parent.mkdir(parents=True,exist_ok=True)
    dst.write_text((Path('/ksrc/drivers/usb/dwc3')/name).read_text())
subprocess.run(['patch','-p1','-i','/port/kernel/patches-experimental/usb-otg-system-sleep.patch'],cwd=base,check=True)
def function(source,name):
    start=source.index(name+'(')
    start=source.rfind('\n',0,start)+1
    brace=source.index('{',start)
    depth=1; end=brace+1
    while depth:
        depth += (source[end]=='{')-(source[end]=='}'); end+=1
    return source[start:end]+'\n'
core=(base/'drivers/usb/dwc3/core.c').read_text()
gadget=(base/'drivers/usb/dwc3/gadget.c').read_text()
functions=''.join(function(gadget,n) for n in ['dwc3_gadget_suspend','dwc3_gadget_resume'])
functions+=''.join(function(core,n) for n in ['dwc3_suspend_common','dwc3_resume_common','dwc3_resume'])
prefix=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <errno.h>
enum { USB_DR_MODE_PERIPHERAL, USB_DR_MODE_OTG, USB_DR_MODE_HOST };
enum { OTG_STATE_B_PERIPHERAL=1, OTG_STATE_A_HOST, OTG_STATE_B_IDLE };
struct device { void *data; };
struct dotg { struct {int lock;} fsm; struct {int state;} otg; };
struct dwc3 {
 struct device *dev; struct dotg *dotg; void *gadget_driver;
 int lock, irq_gadget, dr_mode;
 bool system_sleep_gadget, pullups_connected, softconnect, vbus_session;
 void *usb3_phy,*usb2_phy,*usb2_generic_phy,*usb3_generic_phy;
};
static int spin,mutex,waits,refs,get_error,stop_error,start_error,run_error;
static int stops,starts,disconnects,cleanups,setups,host_ops;
#define spin_lock_irqsave(l,f) do { assert(!spin); spin=1; f=0; } while(0)
#define spin_unlock_irqrestore(l,f) do { assert(spin); spin=0; (void)f; } while(0)
static void mutex_lock(int *l) { (void)l; assert(!mutex && !spin); mutex=1; }
static void mutex_unlock(int *l) { (void)l; assert(mutex && !spin); mutex=0; }
static void synchronize_irq(int irq) { (void)irq; assert(!spin && !mutex); waits++; }
static int pm_runtime_get_sync(struct device *dev) { (void)dev; refs++; return get_error; }
static void pm_runtime_put_noidle(struct device *dev) { (void)dev; refs--; }
static void pm_runtime_put_sync(struct device *dev) { (void)dev; refs--; }
static void pm_runtime_disable(struct device *dev) { (void)dev; }
static void pm_runtime_set_active(struct device *dev) { (void)dev; }
static void pm_runtime_enable(struct device *dev) { (void)dev; }
static void pinctrl_pm_select_default_state(struct device *dev) { (void)dev; }
static void *dev_get_drvdata(struct device *dev) { return dev->data; }
#define dev_info(...) ((void)0)
#define pr_info(...) ((void)0)
static int dwc3_gadget_run_stop(struct dwc3 *d,bool run,bool suspend) {
 (void)suspend; assert(spin);
 if (!run) { stops++; if(stop_error) return stop_error; }
 else if(run_error) return run_error;
 d->pullups_connected=run; return 0;
}
static void dwc3_disconnect_gadget(struct dwc3 *d) { (void)d; assert(spin); disconnects++; }
static void __dwc3_gadget_stop(struct dwc3 *d) { (void)d; assert(spin); }
static int __dwc3_gadget_start(struct dwc3 *d) { (void)d; assert(spin); starts++; return start_error; }
static void dwc3_event_buffers_cleanup(struct dwc3 *d) { (void)d; assert(!spin && !mutex); cleanups++; }
static void dwc3_event_buffers_setup(struct dwc3 *d) { (void)d; setups++; }
static void usb_phy_shutdown(void *p) { (void)p; host_ops++; }
static void phy_exit(void *p) { (void)p; host_ops++; }
static void phy_power_off(void *p) { (void)p; host_ops++; }
'''
suffix=r'''
static struct device dev;
static struct dotg otg;
static struct dwc3 d;
static void reset(void) {
 spin=mutex=waits=refs=get_error=stop_error=start_error=run_error=0;
 stops=starts=disconnects=cleanups=setups=host_ops=0;
 otg=(struct dotg){.otg={.state=OTG_STATE_B_PERIPHERAL}};
 d=(struct dwc3){.dev=&dev,.dotg=&otg,.gadget_driver=&dev,
 .dr_mode=USB_DR_MODE_OTG,.pullups_connected=true,.softconnect=true,.vbus_session=true};
 dev.data=&d;
}
int main(void) {
 /* Repeated connected cycles quiesce and restore exactly once per cycle. */
 reset();
 for(int i=1;i<=3;i++) {
  assert(!dwc3_suspend_common(&d)); assert(refs==1 && d.system_sleep_gadget);
  assert(!d.pullups_connected && waits==i && stops==i && disconnects==i);
  assert(!dwc3_resume(&dev)); assert(!refs && !d.system_sleep_gadget && d.pullups_connected);
  assert(starts==i && cleanups==i);
 }
 /* Inactive/unbound/host-role OTG must not arm a gadget on resume. */
 for(int mode=0;mode<4;mode++) {
  reset();
  if(mode==0) d.pullups_connected=false;
  if(mode==1) d.gadget_driver=NULL;
  if(mode==2) otg.otg.state=OTG_STATE_A_HOST;
  if(mode==3) d.dotg=NULL;
  assert(!dwc3_suspend_common(&d)); assert(!d.system_sleep_gadget && !waits && !stops);
  assert(!dwc3_resume(&dev)); assert(!starts && !refs);
 }
 /* Unplug, host switch, gadget unbind and soft disconnect during sleep. */
 for(int mode=0;mode<5;mode++) {
  reset(); assert(!dwc3_suspend_common(&d));
  if(mode==0) d.vbus_session=false;
  if(mode==1) otg.otg.state=OTG_STATE_A_HOST;
  if(mode==2) d.gadget_driver=NULL;
  if(mode==3) d.softconnect=false;
  if(mode==4) d.dotg=NULL;
  assert(!dwc3_resume(&dev)); assert(!starts && !d.system_sleep_gadget && !refs);
 }
 /* No prior suspend means no unsolicited OTG reconnect. */
 reset(); assert(!dwc3_resume_common(&d)); assert(!starts && !refs);
 /* Callback failure must propagate; PM usage must not leak. */
 reset(); get_error=-EIO; assert(dwc3_suspend_common(&d)==-EIO); assert(!refs && !stops);
 reset(); stop_error=-ETIMEDOUT; assert(dwc3_suspend_common(&d)==-ETIMEDOUT);
 assert(!refs && !d.system_sleep_gadget && !disconnects && !cleanups);
 for(int mode=0;mode<2;mode++) {
  reset(); assert(!dwc3_suspend_common(&d));
  if(mode==0) start_error=-EIO; else run_error=-ETIMEDOUT;
  assert(dwc3_resume(&dev)==(mode==0 ? -EIO : -ETIMEDOUT));
  assert(!refs && !d.system_sleep_gadget && !spin && !mutex);
 }
 /* Existing peripheral path now waits for IRQ outside the spinlock. */
 reset(); d.dr_mode=USB_DR_MODE_PERIPHERAL;
 assert(!dwc3_suspend_common(&d)); assert(waits==1 && stops==1);
 assert(!dwc3_resume(&dev)); assert(starts==1 && !refs);
 /* Existing fixed host path remains untouched. */
 reset(); d.dr_mode=USB_DR_MODE_HOST;
 assert(!dwc3_suspend_common(&d)); assert(host_ops==6 && !stops && !waits);
 assert(!dwc3_resume(&dev)); assert(!starts && !refs);
 puts("USB system-sleep helper tests passed");
}
'''
c=base/'test.c'; c.write_text(prefix+functions+suffix)
subprocess.run(['cc','-std=gnu11','-O2','-Wall','-Wextra','-Werror','-Wno-implicit-fallthrough',str(c),'-o',str(base/'test')],check=True)
subprocess.run([str(base/'test')],check=True)
