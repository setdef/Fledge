// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0
//
// The touch the Mobile apps job gives the game (ADR 025): XCTest, Apple's
// own UI testing, launches the app, waits while it draws, and taps the
// screen a third of the way across and down, where the game's white
// square should move to; the job reads the touch from the app's log.
@import XCTest;

@interface TapTest : XCTestCase
@end

@implementation TapTest
- (void)testTheGameTakesATouch {
    XCUIApplication *app = [XCUIApplication new];
    // Xcode copies os_log to standard error under a test, which the app
    // sends to os_log, which would copy it back: the log would feed itself.
    app.launchEnvironment = @{@"OS_ACTIVITY_DT_MODE": @"NO"};
    [app launch];
    [NSThread sleepForTimeInterval:8];
    [[app coordinateWithNormalizedOffset:CGVectorMake(0.33, 0.33)] tap];
    [NSThread sleepForTimeInterval:6];
}
@end
