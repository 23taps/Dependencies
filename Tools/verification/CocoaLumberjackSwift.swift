import Foundation
import CocoaLumberjack
import CocoaLumberjackSwift

// Exercises the Swift logging API and, just as importantly, that it routes into
// the same core implementation rather than a second copy linked in alongside it.

var failures = 0
func check(_ label: String, _ actual: String, _ expected: String) {
    let ok = actual == expected
    print("    \(ok ? "PASS" : "FAIL")  \(label)")
    if !ok {
        print("            expected: \(expected)")
        print("            actual:   \(actual)")
        failures += 1
    }
}

final class CaptureLogger: DDAbstractLogger {
    let lock = NSLock()
    var messages: [DDLogMessage] = []
    override func log(message: DDLogMessage) {
        lock.lock(); messages.append(message); lock.unlock()
    }
    override var loggerName: DDLoggerName { DDLoggerName("capture") }
}

let logger = CaptureLogger()
DDLog.add(logger)
dynamicLogLevel = .all

// Logged from inside a named function: at Swift top level `#function` is the
// module name, which would make the call-site assertion depend on what the
// verifier happens to name the executable.
func emitLogs() {
    DDLogError("error \(42)")
    DDLogWarn("warn")
    DDLogInfo("info")
    DDLogDebug("debug")
    DDLogVerbose("verbose")
}
emitLogs()
DDLog.flushLog()

let messages = logger.messages
check("five messages reached the logger", "\(messages.count)", "5")
if messages.count >= 5 {
    check("string interpolation", messages[0].message, "error 42")
    check("error flag", "\(messages[0].flag.rawValue)", "\(DDLogFlag.error.rawValue)")
    check("warning flag", "\(messages[1].flag.rawValue)", "\(DDLogFlag.warning.rawValue)")
    check("verbose flag", "\(messages[4].flag.rawValue)", "\(DDLogFlag.verbose.rawValue)")
    check("call-site file captured", messages[0].fileName, "main")
    check("call-site function captured", messages[0].function ?? "<nil>", "emitLogs()")
}

// The Swift wrapper must drive the same DDLog the Objective-C core exposes; if
// it had absorbed its own copy of the implementation these would disagree.
check("wrapper and core share one DDLog", "\(DDLog.allLoggers.count)", "1")
check("shared instance is the core's", "\(DDLog.sharedInstance === DDLog.sharedInstance)", "true")

// Level filtering is the behaviour the application depends on most.
logger.messages.removeAll()
dynamicLogLevel = .error
DDLogInfo("filtered out")
DDLogError("kept")
DDLog.flushLog()
check("dynamicLogLevel filters below-threshold messages", "\(logger.messages.count)", "1")
check("surviving message is the error", logger.messages.first?.message ?? "<none>", "kept")
dynamicLogLevel = .all

let version = Bundle(identifier: "com.emoji.CocoaLumberjackSwift")?
    .infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
print("    CocoaLumberjackSwift \(version) on \(ProcessInfo.processInfo.operatingSystemVersionString)")
exit(failures == 0 ? 0 : 1)
