// Exercises the Objective-C logging core the way the application does: through
// the DDLog* macros, dispatched to a registered logger. Loading is not the same
// as working, so this asserts the message text, flag, and call-site metadata
// that actually arrive at the logger.
@import Foundation;
@import CocoaLumberjack;

static DDLogLevel ddLogLevel = DDLogLevelAll;

static int failures = 0;

static void check(NSString *label, NSString *actual, NSString *expected) {
    BOOL ok = [actual isEqualToString:expected];
    printf("    %s  %s\n", ok ? "PASS" : "FAIL", label.UTF8String);
    if (!ok) {
        printf("            expected: %s\n", expected.UTF8String);
        printf("            actual:   %s\n", actual.UTF8String);
        failures++;
    }
}

@interface CaptureLogger : DDAbstractLogger
@property (nonatomic, strong) NSMutableArray<DDLogMessage *> *messages;
@end

@implementation CaptureLogger
- (instancetype)init {
    if ((self = [super init])) { _messages = [NSMutableArray array]; }
    return self;
}
- (void)logMessage:(DDLogMessage *)logMessage {
    @synchronized (self) { [self.messages addObject:logMessage]; }
}
- (DDLoggerName)loggerName { return @"capture"; }
@end

int main(void) {
    @autoreleasepool {
        CaptureLogger *logger = [CaptureLogger new];
        [DDLog addLogger:logger];

        DDLogError(@"error %d", 42);
        DDLogWarn(@"warn");
        DDLogInfo(@"info");
        DDLogDebug(@"debug");
        DDLogVerbose(@"verbose");
        [DDLog flushLog];

        NSArray<DDLogMessage *> *m = logger.messages;
        check(@"five messages reached the logger",
              [NSString stringWithFormat:@"%lu", (unsigned long)m.count], @"5");
        if (m.count < 5) { return 1; }

        check(@"format arguments interpolated", m[0].message, @"error 42");
        check(@"error flag", [NSString stringWithFormat:@"%lu", (unsigned long)m[0].flag],
              [NSString stringWithFormat:@"%lu", (unsigned long)DDLogFlagError]);
        check(@"warning flag", [NSString stringWithFormat:@"%lu", (unsigned long)m[1].flag],
              [NSString stringWithFormat:@"%lu", (unsigned long)DDLogFlagWarning]);
        check(@"verbose flag", [NSString stringWithFormat:@"%lu", (unsigned long)m[4].flag],
              [NSString stringWithFormat:@"%lu", (unsigned long)DDLogFlagVerbose]);
        check(@"call-site file captured", m[0].fileName, @"CocoaLumberjack");
        check(@"call-site function captured", m[0].function, @"int main(void)");

        // A formatter is the extension point the application relies on.
        check(@"logger registered", [NSString stringWithFormat:@"%lu",
              (unsigned long)DDLog.allLoggers.count], @"1");

        [DDLog removeLogger:logger];
        [DDLog flushLog];
        DDLogError(@"after removal");
        [DDLog flushLog];
        check(@"removed logger receives nothing further",
              [NSString stringWithFormat:@"%lu", (unsigned long)logger.messages.count], @"5");

        NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.emoji.CocoaLumberjack"];
        NSString *version = bundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"?";
        printf("    CocoaLumberjack %s on %s\n", version.UTF8String,
               NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
        // The privacy manifest ships inside the framework, not a nested bundle.
        check(@"privacy manifest present in framework",
              [bundle URLForResource:@"PrivacyInfo" withExtension:@"xcprivacy"] != nil ? @"true" : @"false",
              @"true");
    }
    return failures == 0 ? 0 : 1;
}
