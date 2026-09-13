from pathlib import Path
import subprocess

base = Path('/tmp/watchdog-freezer-test')
(base/'drivers/watchdog').mkdir(parents=True)
target = base/'drivers/watchdog/s3c2410_wdt.c'
target.write_text(Path('/ksrc/drivers/watchdog/s3c2410_wdt.c').read_text())
subprocess.run(['patch','-p1','-i','/port/kernel/patches-experimental/watchdog-freezer-preserve-state.patch'],cwd=base,check=True)
source=target.read_text()
start=source.index('int s3c2410wdt_emergency_multistage_wdt_stop(void)')
end=source.index('\nstatic int s3c2410wdt_get_multistage_index(void)',start)
functions=source[start:end]
prefix=r'''
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <errno.h>
#define S3C2410_WTCON 0
#define S3C2410_WTDAT 4
#define S3C2410_WTCNT 8
#define S3C2410_WTCON_ENABLE (1 << 5)
#define S3C2410_WTCON_INTEN (1 << 2)
#define S3C2410_WTCON_RSTEN 1
#define S3C2410_WTCON_DIV128 (3 << 3)
struct s3c2410_wdt { void *dev; unsigned char *reg_base; unsigned int count; int lock; bool freezer_wdt_was_enabled; };
static unsigned int registers[3];
static struct s3c2410_wdt watchdog={.reg_base=(unsigned char *)registers,.count=0xb32b};
static struct s3c2410_wdt *s3c_wdt[]={&watchdog};
static int index_result, writes, locked;
#define spin_lock_irqsave(lock,flags) do { assert(!locked); locked=1; flags=0; } while(0)
#define spin_unlock_irqrestore(lock,flags) do { assert(locked); locked=0; (void)flags; } while(0)
#define dev_info(...) ((void)0)
static unsigned int readl(void *address) { assert(locked); return *(unsigned int *)address; }
static void writel(unsigned int value,void *address) { assert(locked); *(unsigned int *)address=value; writes++; }
static int s3c2410wdt_get_multistage_index(void) { return index_result; }
static int s3c2410wdt_multistage_wdt_stop(void) {
 unsigned int control=readl(watchdog.reg_base);
 writel(control & ~(S3C2410_WTCON_ENABLE|S3C2410_WTCON_INTEN),watchdog.reg_base);
 return 0;
}
'''
suffix=r'''
int main(void) {
 int prior_writes;
 /* An unmatched restore must not arm hardware. */
 registers[0]=0x5c18;
 assert(s3c2410wdt_emergency_multistage_wdt_start()==0);
 assert(registers[0]==0x5c18 && writes==0 && !locked);
 /* Both freezer passes and repeated cycles preserve an inactive watchdog. */
 for(int i=0;i<4;i++) {
  assert(s3c2410wdt_emergency_multistage_wdt_stop()==0);
  assert(!watchdog.freezer_wdt_was_enabled);
  prior_writes=writes;
  assert(s3c2410wdt_emergency_multistage_wdt_start()==0);
  assert(registers[0]==0x5c18 && writes==prior_writes && !locked);
 }
 /* A running multistage watchdog retains the original stop/reload/start. */
 registers[0]=0x5c3c;
 for(int i=0;i<4;i++) {
  assert(s3c2410wdt_emergency_multistage_wdt_stop()==0);
  assert(watchdog.freezer_wdt_was_enabled && registers[0]==0x5c18);
  assert(s3c2410wdt_emergency_multistage_wdt_start()==0);
  assert(registers[0]==0x5c3c && registers[1]==0xb32b && registers[2]==0xb32b);
  assert(!watchdog.freezer_wdt_was_enabled && !locked);
 }
 /* No device returns an error and never accesses register storage. */
 index_result=-ENODEV; prior_writes=writes;
 assert(s3c2410wdt_emergency_multistage_wdt_stop()==-ENODEV);
 assert(s3c2410wdt_emergency_multistage_wdt_start()==-ENODEV);
 assert(writes==prior_writes && !locked);
 puts("PASS: inactive stays inactive; active reloads/restarts; repeated pairs, unmatched start and missing device handled");
}
'''
Path('/tmp/watchdog-freezer-test.c').write_text(prefix+functions+suffix)
subprocess.run(['cc','-std=gnu11','-O2','-Wall','-Wextra','-Werror','/tmp/watchdog-freezer-test.c','-o','/tmp/watchdog-freezer-test-bin'],check=True)
subprocess.run(['/tmp/watchdog-freezer-test-bin'],check=True)
