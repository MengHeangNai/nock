#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "GlassDockMediaRemote.h"

typedef void (^InfoHandler)(NSDictionary *info);
typedef void (^PlayingHandler)(Boolean playing);
typedef void (^PIDHandler)(int pid);

static dispatch_queue_t queue;
static dispatch_source_t parentWatch;
static BOOL emitPending;

static void *MediaRemoteSymbol(const char *name) {
    static void *framework;
    if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    return framework ? dlsym(framework, name) : NULL;
}

static void EmitNowPlaying(void) {
    void (*getInfo)(dispatch_queue_t, InfoHandler) = MediaRemoteSymbol("MRMediaRemoteGetNowPlayingInfo");
    void (*getPlaying)(dispatch_queue_t, PlayingHandler) = MediaRemoteSymbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    void (*getPID)(dispatch_queue_t, PIDHandler) = MediaRemoteSymbol("MRMediaRemoteGetNowPlayingApplicationPID");
    if (!getInfo || !getPlaying || !getPID) exit(1);

    getPID(queue, ^(int pid) {
        getPlaying(queue, ^(Boolean playing) {
            getInfo(queue, ^(NSDictionary *info) {
                NSMutableDictionary *line = [NSMutableDictionary dictionary];
                if (pid > 0 && info.count > 0) {
                    line[@"pid"] = @(pid);
                    line[@"playing"] = playing ? @YES : @NO;
                    for (NSString *key in @[@"title", @"artist", @"album", @"duration", @"elapsedTime"]) {
                        NSString *infoKey = [NSString stringWithFormat:@"kMRMediaRemoteNowPlayingInfo%@%@",
                                             [key substringToIndex:1].uppercaseString, [key substringFromIndex:1]];
                        id value = info[infoKey];
                        // Live streams report an infinite or NaN duration, which JSON cannot encode.
                        if ([value isKindOfClass:NSNumber.class] && !isfinite([value doubleValue])) continue;
                        if (value) line[key] = value;
                    }
                    NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                    if (timestamp) line[@"timestamp"] = @(timestamp.timeIntervalSince1970);
                    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    if (artwork) line[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                }
                NSData *json = [NSJSONSerialization dataWithJSONObject:line options:0 error:nil];
                if (!json) return;
                fwrite(json.bytes, 1, json.length, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            });
        });
    });
}

static void ScheduleEmit(void) {
    if (emitPending) return;
    emitPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), queue, ^{
        emitPending = NO;
        EmitNowPlaying();
    });
}

void glassdock_stream(void *interpreter, void *cv) {
    queue = dispatch_queue_create("GlassDock.MediaRemote", DISPATCH_QUEUE_SERIAL);

    parentWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, getppid(), DISPATCH_PROC_EXIT, queue);
    dispatch_source_set_event_handler(parentWatch, ^{ exit(0); });
    dispatch_resume(parentWatch);

    void (*registerForNotifications)(dispatch_queue_t) = MediaRemoteSymbol("MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!registerForNotifications) exit(1);
    registerForNotifications(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                      usingBlock:^(NSNotification *note) { ScheduleEmit(); }];
    }
    ScheduleEmit();
    dispatch_main();
}

void glassdock_send(void *interpreter, void *cv) {
    Boolean (*sendCommand)(int, NSDictionary *) = MediaRemoteSymbol("MRMediaRemoteSendCommand");
    const char *command = getenv("GLASSDOCK_MR_COMMAND");
    if (!sendCommand || !command) exit(1);
    sendCommand(atoi(command), nil);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}

void glassdock_seek(void *interpreter, void *cv) {
    void (*setElapsedTime)(double) = MediaRemoteSymbol("MRMediaRemoteSetElapsedTime");
    const char *seconds = getenv("GLASSDOCK_MR_SECONDS");
    if (!setElapsedTime || !seconds) exit(1);
    setElapsedTime(atof(seconds));
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}
