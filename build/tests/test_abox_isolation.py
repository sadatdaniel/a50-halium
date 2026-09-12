from pathlib import Path
import subprocess

base = Path('/tmp/abox-isolation')
(base/'sound/soc/samsung/abox').mkdir(parents=True)
source = Path('/ksrc/sound/soc/samsung/abox/abox.c').read_text()
(base/'sound/soc/samsung/abox/abox.c').write_text(source)
subprocess.run(['patch','-p1','-i','/port/kernel/patches-experimental/abox-freezer-isolation.patch'],cwd=base,check=True)
source = (base/'sound/soc/samsung/abox/abox.c').read_text()
start = source.index('static int abox_pm_notifier(')
end = source.index('\nstatic int abox_modem_notifier',start)
function = source[start:end]
prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#define PM_SUSPEND_PREPARE 1
#define PM_POST_SUSPEND 2
#define MODE_IN_CALL 2
#define NOTIFY_BAD 2
#define NOTIFY_OK 1
#define NOTIFY_DONE 0
#define TEST_FREEZER 5
#define ABOX_QUIRK_OFF_ON_SUSPEND 1
#define READ_ONCE(x) (x)
#define atomic_read(x) (*(x))
#define atomic_set(x,v) (*(x)=(v))
#define dev_dbg(...) ((void)0)
#define dev_info(...) ((void)0)
#define dev_warn(...) ((void)0)
enum calliope_state { CALLIOPE_DISABLED, CALLIOPE_ENABLED, CALLIOPE_ENABLING };
struct device { struct { int usage_count; } power; };
struct platform_device { struct device dev; };
struct notifier_block { int unused; };
struct abox_data { struct notifier_block pm_nb; struct platform_device *pdev; int audio_mode; enum calliope_state calliope_state; int ipc_workqueue; int suspend_state; };
static struct abox_data test_data;
#define container_of(...) (&test_data)
static bool freezer_skip_pm, freezer_skip_pm_active;
static int pm_test_level, effects, resumes;
#define pm_runtime_barrier(...) (++effects)
#define abox_clear_cpu_gear_requests(...) (++effects)
#define abox_cpu_gear_barrier(...) (++effects)
#define flush_workqueue(...) (++effects)
#define abox_test_quirk(...) 1
#define pm_runtime_put_sync(...) (++effects,0)
#define pm_runtime_suspend(...) (++effects,0)
#define pm_runtime_get(...) (++resumes)
#define pm_runtime_get_sync(...) (++resumes)
#define abox_print_power_usage(...) ((void)0)
'''
suffix = r'''
int main(void) {
 struct platform_device pdev={0}; test_data.pdev=&pdev; test_data.calliope_state=CALLIOPE_ENABLED;
 freezer_skip_pm=true;
 for(pm_test_level=0;pm_test_level<5;pm_test_level++) {
   assert(abox_pm_notifier(0,PM_SUSPEND_PREPARE,0)==NOTIFY_BAD);
   abox_pm_notifier(0,PM_POST_SUSPEND,0);
   assert(effects==0 && resumes==0);
 }
 pm_test_level=TEST_FREEZER;
 assert(abox_pm_notifier(0,PM_SUSPEND_PREPARE,0)==NOTIFY_OK);
 assert(freezer_skip_pm_active && effects==0);
 freezer_skip_pm=false; /* POST pairs with PREPARE despite option changes. */
 assert(abox_pm_notifier(0,PM_POST_SUSPEND,0)==NOTIFY_OK);
 assert(!freezer_skip_pm_active && resumes==0);
 assert(abox_pm_notifier(0,PM_SUSPEND_PREPARE,0)==NOTIFY_DONE);
 assert(effects>0 && test_data.suspend_state==1);
 abox_pm_notifier(0,PM_POST_SUSPEND,0);
 assert(resumes==1 && test_data.suspend_state==0);
 puts("PASS: deeper levels refused, freezer skips paired notifier paths, default runs original PM path");
}
'''
Path('/tmp/abox-isolation-test.c').write_text(prefix+function+suffix)
subprocess.run(['cc','-O2','-Wall','/tmp/abox-isolation-test.c','-o','/tmp/abox-isolation-test'],check=True)
subprocess.run(['/tmp/abox-isolation-test'],check=True)

