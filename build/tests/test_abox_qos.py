from pathlib import Path
import subprocess

src = Path('/ksrc/sound/soc/samsung/abox/abox.c').read_text()
start = src.index('static void abox_change_cpu_gear(struct device *dev, struct abox_data *data)')
end = src.index('\nstatic void abox_change_cpu_gear_work_func', start)
func = src[start:end]
old = '\tif (data->cpu_gear != gear) {\n\t\tfreq = (gear <= ARRAY_SIZE(data->pm_qos_aud)) ?\n\t\t\t\tdata->pm_qos_aud[gear - 1] : 0;'
new = '\tfreq = (gear <= ARRAY_SIZE(data->pm_qos_aud)) ?\n\t\t\tdata->pm_qos_aud[gear - 1] : 0;\n\tif (data->cpu_gear != gear) {'
assert func.count(old) == 1
func = func.replace(old, new)
prefix = r'''
#include <assert.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
typedef int s32;
#define ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))
#define ABOX_CPU_GEAR_MIN 12
#define AUD_PLL_RATE_HZ_FOR_48000 1179648000
struct device { int unused; };
struct abox_qos_request { unsigned int id, value; };
struct abox_data { struct abox_qos_request cpu_gear_requests[64]; unsigned int cpu_gear; s32 pm_qos_aud[4]; int clk_pll; };
static struct { int pm_qos_class; } abox_pm_qos_aud;
static int updates, logged, actual = 394000, gets, puts;
#define dev_dbg(...) ((void)0)
#define dev_info(dev, fmt, value, ...) (logged=(value))
#define clk_set_rate(...) ((void)0)
#define clk_get_rate(...) 0
#define pm_runtime_get(...) (++gets)
#define pm_runtime_mark_last_busy(...) ((void)0)
#define pm_runtime_put_autosuspend(...) (++puts)
#define pm_qos_update_request(req, value) (++updates, actual=(value))
#define pm_qos_request(...) actual
#define abox_notify_cpu_gear(...) ((void)0)
'''
# Capture only frequency logging, ignoring clock logging.
func = func.replace('dev_info(dev, "pm qos request aud: req=%dkHz ret=%dkHz\\n", freq,', 'dev_info(dev, "pm qos request aud: req=%dkHz ret=%dkHz\\n", freq,')
suffix = r'''
int main(void) {
 struct device dev = {0};
 struct abox_data data = {.cpu_gear_requests={{1,3}}, .cpu_gear=3, .pm_qos_aud={1180000,800000,600000,394000}};
 abox_change_cpu_gear(&dev,&data);
 assert(logged==600000 && updates==0 && actual==394000 && gets==0 && puts==0);
 data.cpu_gear_requests[0].value=2;
 abox_change_cpu_gear(&dev,&data);
 assert(logged==800000 && updates==1 && actual==800000 && data.cpu_gear==2);
 data.cpu_gear=12; data.cpu_gear_requests[0].value=12;
 abox_change_cpu_gear(&dev,&data);
 assert(logged==0 && updates==1 && gets==0 && puts==0);
 data.cpu_gear=UINT_MAX; data.cpu_gear_requests[0].id=0;
 abox_change_cpu_gear(&dev,&data);
 assert(logged==0 && updates==1);
 puts("PASS: unchanged, changed, idle and empty request paths; QoS updates remain conditional");
}
'''
# Avoid colliding with the C library puts function.
prefix = prefix.replace('gets, puts;', 'gets, put_count;').replace('(++puts)', '(++put_count)')
suffix = suffix.replace('puts==', 'put_count==')
Path('/tmp/abox-qos-test.c').write_text(prefix+func+suffix)
subprocess.run(['cc','-O2','-Wall','-Werror=uninitialized','-Wno-unused-variable','/tmp/abox-qos-test.c','-o','/tmp/abox-qos-test'],check=True)
subprocess.run(['/tmp/abox-qos-test'],check=True)
