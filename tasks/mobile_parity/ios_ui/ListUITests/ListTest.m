// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT
//
// What a person does with a list app the mobile parity check runs in
// the iOS Simulator (tasks/mobile_parity/ios.rb): XCTest, Apple's own
// UI testing, types the item FLEDGE_ITEM into the app's text field and
// taps the on-screen keyboard's Return key, waits for a row of that
// text, then
// swipes the row left and taps Delete, as a person removes a row from
// one of Apple's own lists, and waits for the row to go. The app is
// FLEDGE_APP, by its bundle identifier, already running: the check
// launched it, and reads its log by its process.
@import XCTest;

@interface ListTest : XCTestCase
@end

@implementation ListTest
- (void)testReturnAddsAnItemAndASwipeDeletesIt {
    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    NSString *item = environment[@"FLEDGE_ITEM"];
    XCTAssertNotNil(item, @"FLEDGE_ITEM names no item");
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:environment[@"FLEDGE_APP"]];
    [app activate];

    XCUIElement *field = app.textFields.firstMatch;
    XCTAssertTrue([field waitForExistenceWithTimeout:60], @"the app shows no text field:\n%@", app.debugDescription);
    [field tap];
    [field typeText:item];
    // A person taps the on-screen keyboard's Return key, whatever its
    // label (return, done, go...): the keyboard's last key of that row.
    XCUIElement *keyboard = app.keyboards.firstMatch;
    XCUIElement *returnKey = nil;
    if ([keyboard waitForExistenceWithTimeout:10]) {
        NSPredicate *named = [NSPredicate predicateWithFormat:@"label IN[c] {'return', 'done', 'go', 'next', 'search', 'send', 'join', 'route', 'continue'}"];
        returnKey = [keyboard.buttons matchingPredicate:named].firstMatch;
    }
    if (returnKey.exists) {
        NSLog(@"Tapped the keyboard's %@ key", returnKey.label);
        [returnKey tap];
    } else {
        NSLog(@"Typed Return: no on-screen keyboard shows a Return key:\n%@", keyboard.debugDescription);
        [field typeText:@"\n"];
    }
    NSPredicate *labelled = [NSPredicate predicateWithFormat:@"label == %@", item];
    XCUIElement *row = [app.cells containingPredicate:labelled].firstMatch;
    XCTAssertTrue([row waitForExistenceWithTimeout:30], @"Return added no row %@, and the field holds %@:\n%@", item, field.value,
        app.debugDescription);
    NSLog(@"Typed %@ and Return: a row shows it", item);

    [row swipeLeft];
    XCUIElement *delete = app.buttons[@"Delete"];
    if ([delete waitForExistenceWithTimeout:10]) {
        [delete tap];
    }
    XCTNSPredicateExpectation *gone = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"exists == NO"] object:row];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[gone] timeout:30], XCTWaiterResultCompleted,
        @"swiping %@ left and tapping Delete left its row:\n%@", item, app.debugDescription);
    NSLog(@"Swiped %@ left and tapped Delete: its row went", item);
}
@end
