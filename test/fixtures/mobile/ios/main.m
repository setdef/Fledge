// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The iOS and iPadOS host app of CI's mobile parity check
// (tasks/mobile_parity/ios.rb), as small as the embedding API allows,
// and no part of a runtime. Before UIKit starts, on the main thread, it
// sends standard output and standard error to os_log, and runs the
// Ruby script its launch names (-FledgeScript NAME; main.rb, the parity
// probe, by default) from the app/ folder of its bundle with the Ruby in
// its ruby/ folder, which the check copies from the runtime's
// XCFramework slice for the SDK it builds. It imports the embedding API
// as the module FledgeRuby, which also links what Ruby needs of iOS.
// Then it writes Ruby's exit status, through the same standard output,
// and shows it in one UIKit scene, which apps built with the iOS 26 SDK
// and later must use.
@import FledgeRuby;
@import UIKit;

#include <stdio.h>

static int ruby_status = -1;

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *controller = [UIViewController new];
    UILabel *label = [UILabel new];
    label.text = [NSString stringWithFormat:@"Ruby exited with status %d", ruby_status];
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = UIColor.systemBackgroundColor;
    controller.view = label;
    window.rootViewController = controller;
    [window makeKeyAndVisible];
    self.window = window;
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundlePath;
        NSString *script = [NSUserDefaults.standardUserDefaults stringForKey:@"FledgeScript"] ?: @"main.rb";
        NSString *root = [bundle stringByAppendingPathComponent:@"ruby"];
        NSString *path = [[bundle stringByAppendingPathComponent:@"app"] stringByAppendingPathComponent:script];
        if (fledge_ruby_forward_output("org.setdef.fledge.parity") != 0) perror("fledge_ruby_forward_output");
        ruby_status = fledge_ruby_run(root.fileSystemRepresentation, path.fileSystemRepresentation, 0, NULL);
        printf("FLEDGE-MOBILE-STATUS %d\n", ruby_status);
        fflush(stdout);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
