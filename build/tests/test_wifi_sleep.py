from pathlib import Path
import subprocess
import tempfile

root = Path(tempfile.mkdtemp(prefix='a50-wifi-test-'))
files = ['ioctl.c', 'ioctl.h', 'dev.h', 'cfg80211_ops.c', 'cfg80211_ops.h', 'dev.c']
base = 'drivers/net/wireless/scsc'
for name in files:
    target = root / base / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes((Path('/ksrc') / base / name).read_bytes())
subprocess.run(['patch', '-p1', '-i', '/port/kernel/patches-experimental/wifi-system-sleep.patch'], cwd=root, check=True)
source = (root / base / 'cfg80211_ops.c').read_text()
callbacks = source[source.index('static int slsi_system_sleep_prepare('):source.index('\nint slsi_set_pmksa(')]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <errno.h>
#include <stdio.h>
#include <stddef.h>
struct notifier_block { int (*notifier_call)(struct notifier_block *, unsigned long, void *); };
#define container_of(p,t,m) ((t *)((char *)(p)-offsetof(t,m)))
#define PM_SUSPEND_PREPARE 1
#define PM_POST_SUSPEND 2
#define NOTIFY_DONE 0
#define NOTIFY_OK 1
static int notifier_from_errno(int ret) { return ret; }
static int rtnl;
static void rtnl_lock(void) { assert(!rtnl); rtnl=1; }
static void rtnl_unlock(void) { assert(rtnl); rtnl=0; }
static struct notifier_block *registered;
static int register_pm_notifier(struct notifier_block *nb) { assert(!registered); registered=nb; return 0; }
static int unregister_pm_notifier(struct notifier_block *nb) { assert(registered==nb); registered=NULL; return 0; }
struct net_device { bool running; };
struct slsi_dev {
 int device_config_mutex, device_state;
 struct wiphy *wiphy;
 struct notifier_block system_sleep_notifier;
 struct { int user_suspend_mode; } device_config;
 bool system_sleep_wifi_prepared;
};
struct wiphy { struct slsi_dev *sdev; };
struct cfg80211_wowlan { int unused; };
#define SDEV_FROM_WIPHY(w) ((w)->sdev)
#define SLSI_DEVICE_STATE_STARTED 1
#define SLSI_NET_INDEX_WLAN 1
#define SLSI_UNUSED_PARAMETER(v) (void)(v)
#define SLSI_INFO(...) ((void)0)
#define SLSI_ERR(...) ((void)0)
static int held, calls, prepare_error, restore_error;
static bool exists;
static struct net_device dev;
#define SLSI_MUTEX_LOCK(v) do { assert(!held); held=1; } while(0)
#define SLSI_MUTEX_UNLOCK(v) do { assert(held); held=0; } while(0)
static struct net_device *slsi_get_netdev(struct slsi_dev *s, int index) {
 (void)s; assert(index==1); return exists ? &dev : NULL;
}
static bool netif_running(struct net_device *d) { return d->running; }
static struct slsi_dev s;
static int slsi_set_host_suspend_mode(struct net_device *d, int mode) {
 assert(d==&dev && !held); assert(mode==0 || mode==1); calls++;
 s.device_config.user_suspend_mode=mode;
 return mode ? prepare_error : restore_error;
}
static void reset(void) {
 s=(struct slsi_dev){.device_state=1}; dev.running=true; exists=true;
 held=calls=prepare_error=restore_error=0;
}
'''
tests = r'''
int main(void) {
 struct wiphy w={.sdev=&s};
 reset();
 for(int i=0;i<3;i++) {
  assert(slsi_system_sleep_prepare(&w)==0); assert(s.system_sleep_wifi_prepared);
  assert(s.device_config.user_suspend_mode==1);
  assert(slsi_system_sleep_restore(&w)==0); assert(!s.system_sleep_wifi_prepared);
  assert(s.device_config.user_suspend_mode==0 && !held);
 }
 assert(calls==6);
 reset(); s.device_config.user_suspend_mode=1;
 assert(!slsi_system_sleep_prepare(&w) && !slsi_system_sleep_restore(&w)); assert(!calls);
 for(int i=0;i<3;i++) {
  reset(); if(i==0) exists=false; if(i==1) dev.running=false; if(i==2) s.device_state=0;
  assert(!slsi_system_sleep_prepare(&w) && !slsi_system_sleep_restore(&w)); assert(!calls);
 }
 reset(); prepare_error=-EIO;
 assert(slsi_system_sleep_prepare(&w)==-EIO); assert(calls==2);
 assert(!s.system_sleep_wifi_prepared && s.device_config.user_suspend_mode==0);
 reset(); prepare_error=-EIO; restore_error=-ETIMEDOUT;
 assert(slsi_system_sleep_prepare(&w)==-EIO && s.system_sleep_wifi_prepared);
 assert(slsi_system_sleep_prepare(&w)==-EBUSY);
 reset(); assert(!slsi_system_sleep_prepare(&w)); restore_error=-EIO;
 assert(slsi_system_sleep_restore(&w)==-EIO && s.system_sleep_wifi_prepared);
 assert(slsi_system_sleep_prepare(&w)==-EBUSY);
 restore_error=0; assert(!slsi_system_sleep_restore(&w) && !s.system_sleep_wifi_prepared);
 reset(); assert(!slsi_system_sleep_prepare(&w)); exists=false;
 assert(!slsi_system_sleep_restore(&w) && !s.system_sleep_wifi_prepared);
 reset(); s.wiphy=&w;
 assert(!slsi_system_sleep_register(&s) && registered);
 assert(registered->notifier_call(registered,99,NULL)==NOTIFY_DONE && !calls);
 assert(!registered->notifier_call(registered,PM_SUSPEND_PREPARE,NULL));
 assert(s.system_sleep_wifi_prepared && !rtnl);
 /* The late cfg80211 callbacks must neither prepare twice nor restore early. */
 assert(!slsi_suspend(&w,NULL) && !slsi_resume(&w) && calls==1);
 assert(registered->notifier_call(registered,PM_POST_SUSPEND,NULL)==NOTIFY_OK);
 assert(!s.system_sleep_wifi_prepared && calls==2 && !rtnl);
 prepare_error=-EIO;
 assert(registered->notifier_call(registered,PM_SUSPEND_PREPARE,NULL)==-EIO);
 assert(!s.system_sleep_wifi_prepared && !rtnl);
 prepare_error=0;
 assert(!registered->notifier_call(registered,PM_SUSPEND_PREPARE,NULL));
 restore_error=-EIO;
 assert(registered->notifier_call(registered,PM_POST_SUSPEND,NULL)==NOTIFY_OK);
 assert(s.system_sleep_wifi_prepared && !rtnl);
 assert(registered->notifier_call(registered,PM_SUSPEND_PREPARE,NULL)==-EBUSY);
 restore_error=0;
 assert(registered->notifier_call(registered,PM_POST_SUSPEND,NULL)==NOTIFY_OK);
 assert(!s.system_sleep_wifi_prepared);
 slsi_system_sleep_unregister(&s); assert(!registered);
 puts("Wi-Fi early PM and callback tests passed (firmware operations mocked)");
}
'''
c = root / 'test.c'
c.write_text(prefix + callbacks + tests)
subprocess.run(['cc', '-std=gnu11', '-Wall', '-Wextra', '-Werror', str(c), '-o', str(root/'test')], check=True)
subprocess.run([str(root/'test')], check=True)
