#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define OUT(...) do { printf(__VA_ARGS__); } while (0)
#define LINE "\n"
#define STATIC_CHECK(expr) typedef char static_assertion_##__LINE__[(expr)?1:-1]

#define MIHOMO_OK 0
#define MIHOMO_ERR_INIT 1
#define MIHOMO_ERR_INVALID_ARG 2
#define MIHOMO_ERR_RUNTIME 3
#define MIHOMO_ERR_NOT_INITIALIZED 4

typedef int MihomoCoreState;
#define MIHOMO_STATE_STOPPED 0
#define MIHOMO_STATE_RUNNING 2

typedef struct { char version[64]; } MihomoVersion;
typedef struct { uint64_t timestamp_ms, up, down; } MihomoTrafficSample;
typedef struct { uint64_t timestamp_ms, inuse; } MihomoMemorySample;
typedef struct { uint64_t timestamp_ms; char level[16]; char payload[512]; } MihomoLogEntry;
typedef struct { char id[64]; char metadata_host[256]; uint16_t metadata_dst_port; char rule[256]; uint64_t start_time_ms; } MihomoConnection;
typedef struct { MihomoConnection* connections; size_t count; } MihomoConnections;
typedef struct { uint8_t* data; size_t length; } MihomoConfigBuffer;
typedef struct { const char* home_dir; const char* config_file; const char* external_controller; const char* secret; int log_level; } MihomoInitOptions;

typedef void (*MihomoTrafficCallback)(const MihomoTrafficSample* sample, void* ctx);
typedef void (*MihomoMemoryCallback)(const MihomoMemorySample* sample, void* ctx);
typedef void (*MihomoLogCallback)(const MihomoLogEntry* entry, void* ctx);
typedef void (*MihomoStateChangeCallback)(MihomoCoreState state, void* ctx);

extern int MihomoInit(const MihomoInitOptions* opts);
extern int MihomoShutdown(void);
extern int MihomoStart(void);
extern int MihomoStop(void);
extern int MihomoGetVersion(MihomoVersion* out);
extern int MihomoSetTrafficCallback(MihomoTrafficCallback cb, void* ctx);
extern int MihomoSetMemoryCallback(MihomoMemoryCallback cb, void* ctx);
extern int MihomoSetLogCallback(MihomoLogCallback cb, void* ctx);
extern int MihomoSetStateChangeCallback(MihomoStateChangeCallback cb, void* ctx);
extern int MihomoUpdateConfig(const uint8_t* jsonPatch, size_t length);
extern int MihomoReloadConfig(const char* path, const char* inlineYaml);
extern int MihomoSelectProxy(const char* group, const char* proxy);
extern int MihomoCloseConnection(const char* id);
extern int MihomoCloseAllConnections(void);
extern int MihomoTriggerGC(void);
extern int MihomoFlushFakeIPCache(void);

static void cb_tx(const MihomoTrafficSample* s, void* c){ (void)c; if(s) OUT("NET:TX=%llu RX=%llu" LINE,(unsigned long long)s->up,(unsigned long long)s->down); }
static void cb_mem(const MihomoMemorySample* s, void* c){ (void)c; if(s) OUT("MEM:USE=%llu" LINE,(unsigned long long)s->inuse); }
static void cb_log(const MihomoLogEntry* s, void* c){ (void)c; if(s) OUT("LOG:%s:%s" LINE,s->level,s->payload); }
static void cb_state(MihomoCoreState s, void* c){ (void)c; OUT("STATE:%d" LINE,s); }

STATIC_CHECK(sizeof(MihomoVersion)==64);
STATIC_CHECK(sizeof(MihomoTrafficSample)==24);
STATIC_CHECK(sizeof(MihomoMemorySample)==16);
STATIC_CHECK(sizeof(MihomoLogEntry)==536);
STATIC_CHECK(sizeof(MihomoConnection)==592);

int main(void) {
    OUT("MIHOMO:ABI" LINE);
    OUT("SIZE:ver=%zu tx=%zu mem=%zu log=%zu conn=%zu opt=%zu" LINE,
        sizeof(MihomoVersion), sizeof(MihomoTrafficSample), sizeof(MihomoMemorySample), sizeof(MihomoLogEntry), sizeof(MihomoConnection), sizeof(MihomoInitOptions));
    OUT("ENUM:ok=%d init=%d halt=%d run=%d" LINE, MIHOMO_OK, MIHOMO_ERR_INIT, MIHOMO_STATE_STOPPED, MIHOMO_STATE_RUNNING);
    OUT("CBPTR:tx=%p mem=%p log=%p state=%p" LINE, (void*)cb_tx, (void*)cb_mem, (void*)cb_log, (void*)cb_state);
    OUT("DECL:link" LINE);
    return 0;
}
