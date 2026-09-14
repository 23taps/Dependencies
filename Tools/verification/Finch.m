// Exercises the static library the way the Games target does: decode a sample,
// build a sound, and play it through OpenAL. The sample is synthesised here
// rather than shipped as a fixture, so the expected sample rate, frame count
// and duration are known exactly.
@import Foundation;
@import AVFoundation;

#import "FISoundEngine.h"
#import "FISound.h"
#import "FISampleDecoder.h"
#import "FISampleBuffer.h"

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

// OpenAL takes a moment to report a freshly started source as playing, and the
// first start on a cold context is the slowest. Poll rather than guess a sleep.
static BOOL waitFor(FISound *sound, BOOL playing, NSTimeInterval limit) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:limit];
    while (sound.isPlaying != playing && deadline.timeIntervalSinceNow > 0) {
        [NSThread sleepForTimeInterval:0.01];
    }
    return sound.isPlaying == playing;
}

static const uint32_t kSampleRate = 44100;
static const uint32_t kFrames = 11025;          // 0.25 s

// A 16-bit mono PCM WAV of a 440 Hz tone.
static NSString *writeTestWAV(void) {
    uint32_t dataBytes = kFrames * 2;
    NSMutableData *wav = [NSMutableData data];
    void (^u32)(uint32_t) = ^(uint32_t v) { [wav appendBytes:&v length:4]; };
    void (^u16)(uint16_t) = ^(uint16_t v) { [wav appendBytes:&v length:2]; };

    [wav appendBytes:"RIFF" length:4];  u32(36 + dataBytes);
    [wav appendBytes:"WAVE" length:4];
    [wav appendBytes:"fmt " length:4];  u32(16); u16(1); u16(1);
    u32(kSampleRate); u32(kSampleRate * 2); u16(2); u16(16);
    [wav appendBytes:"data" length:4];  u32(dataBytes);

    for (uint32_t i = 0; i < kFrames; i++) {
        int16_t s = (int16_t)(12000.0 * sin(2.0 * M_PI * 440.0 * i / kSampleRate));
        [wav appendBytes:&s length:2];
    }

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"finch-tone.wav"];
    [wav writeToFile:path atomically:YES];
    return path;
}

int main(void) {
    @autoreleasepool {
        NSString *path = writeTestWAV();

        // --- the engine ---------------------------------------------------
        // The engine must come first: it opens the OpenAL device and makes a
        // context current, and sample decoding fails with "No OpenAL context"
        // without one. Ambient category, matching how the application
        // configures audio.
        [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryAmbient error:nil];
        [AVAudioSession.sharedInstance setActive:YES error:nil];

        FISoundEngine *engine = [FISoundEngine sharedEngine];
        check(@"shared engine created", engine != nil ? @"created" : @"nil", @"created");
        check(@"shared engine is a singleton",
              engine == [FISoundEngine sharedEngine] ? @"same" : @"different", @"same");
        check(@"engine starts unsuspended", engine.isSuspended ? @"suspended" : @"running", @"running");

        // --- decoding -----------------------------------------------------
        NSError *error = nil;
        FISampleBuffer *buffer = [FISampleDecoder decodeSampleAtPath:path error:&error];
        check(@"sample decoded", buffer != nil ? @"decoded" : [NSString stringWithFormat:@"nil (%@)", error],
              @"decoded");
        if (!buffer) { return 1; }

        check(@"sample rate", [NSString stringWithFormat:@"%lu", (unsigned long)buffer.sampleRate],
              [NSString stringWithFormat:@"%u", kSampleRate]);
        check(@"frame count", [NSString stringWithFormat:@"%lu", (unsigned long)buffer.numberOfSamples],
              [NSString stringWithFormat:@"%u", kFrames]);
        check(@"bytes per sample", [NSString stringWithFormat:@"%lu", (unsigned long)buffer.bytesPerSample], @"2");
        check(@"duration", [NSString stringWithFormat:@"%.3f", buffer.duration], @"0.250");

        // --- playback -----------------------------------------------------
        FISound *sound = [[FISound alloc] initWithPath:path maxPolyphony:4 error:&error];
        check(@"sound created with four voices",
              sound != nil ? @"created" : [NSString stringWithFormat:@"nil (%@)", error], @"created");
        if (!sound) { return 1; }

        check(@"sound duration", [NSString stringWithFormat:@"%.3f", sound.duration], @"0.250");
        check(@"idle before playing", sound.isPlaying ? @"playing" : @"idle", @"idle");

        sound.gain = 0.5f;
        sound.pitch = 1.0f;
        check(@"gain round-trips", [NSString stringWithFormat:@"%.2f", sound.gain], @"0.50");
        check(@"pitch round-trips", [NSString stringWithFormat:@"%.2f", sound.pitch], @"1.00");

        // Finch forwards `isPlaying` to every voice via -forwardInvocation:, so
        // the value that survives is the LAST voice's. `play` also
        // pre-increments the voice index, so the first play on a four-voice
        // sound starts voice 1 and the last voice only sounds on the fourth
        // play. Both are upstream 1.0.3 behaviour. A single-voice sound has
        // unambiguous semantics, so assert playback there.
        FISound *single = [[FISound alloc] initWithPath:path error:&error];
        check(@"single-voice sound created", single != nil ? @"created" : @"nil", @"created");
        [single play];
        check(@"single voice plays", waitFor(single, YES, 1.0) ? @"playing" : @"idle", @"playing");
        [single stop];
        check(@"single voice stops", waitFor(single, NO, 1.0) ? @"idle" : @"playing", @"idle");

        // Four-voice polyphony: overlapping retriggers, which is what the
        // application relies on. Each play claims the next voice round-robin.
        for (int i = 0; i < 4; i++) { [sound play]; }
        check(@"four overlapping voices playing",
              waitFor(sound, YES, 1.0) ? @"playing" : @"idle", @"playing");
        [sound stop];
        check(@"all voices stop on demand",
              waitFor(sound, NO, 1.0) ? @"idle" : @"playing", @"idle");

        // --- suspend / resume ---------------------------------------------
        engine.suspended = YES;
        check(@"engine suspends", engine.isSuspended ? @"suspended" : @"running", @"suspended");
        engine.suspended = NO;
        check(@"engine resumes", engine.isSuspended ? @"suspended" : @"running", @"running");

        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        printf("    Finch 1.0.3 on %s\n",
               NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
    }
    return failures == 0 ? 0 : 1;
}
