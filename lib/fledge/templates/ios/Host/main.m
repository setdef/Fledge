// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT
//
// The app's one screen, written by fledge build (doc/contributors/design/phone-projects.md). Before UIKit
// starts, it sends standard output and standard error to os_log, with the
// app's bundle identifier as subsystem, and starts the app's Ruby
// program, as fledge.cfg in the bundle's fledge/ folder names it, through
// FledgeRuby's fledge_ruby_run_app, on a thread of its own with the deep
// stack Ruby needs, as Android's FledgeRuby.startApp does, so that the
// interface never waits for Ruby. It passes no arguments, since a phone
// has no command line, and logs the program's exit status when it ends.
// The screen shows the app's name, in the one UIKit scene that apps built
// with the iOS 26 SDK and later must use. Change it as your app needs;
// the two FledgeRuby calls are what it must keep.
//
// An app whose Ruby draws its own screen with UIKit (kind: windowed in
// fledge.yml, which compiles this with FLEDGE_WINDOWED=1) is the other
// way round: UIKit's objects are the main thread's alone, so its Ruby
// runs there, and its program hands that thread to UIKit itself, by
// calling UIApplicationMain as an Objective-C app's main function does,
// with the delegates it defines in Ruby, SceneDelegate among them, as
// Info.plist lists it
// (doc/contributors/design/phone-widgets.md).
@import FledgeRuby;
@import UIKit;

#include <errno.h>
#include <os/log.h>
#include <string.h>

static NSString *AppName(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
}

// The app's log, with its bundle identifier as subsystem, where the
// app's standard output and standard error go from here on.
static os_log_t ForwardOutput(void) {
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    os_log_t log = os_log_create(identifier.UTF8String, "app");
    if (fledge_ruby_forward_output(identifier.UTF8String) != 0) {
        os_log_error(log, "could not send the app's output to the log: %{public}s", strerror(errno));
    }
    return log;
}

// The folder of the app's Ruby, its program, and its gems.
static NSString *RubyRoot(void) {
    return [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"fledge"];
}

#if FLEDGE_WINDOWED
int main(void) {
    @autoreleasepool {
        os_log_t log = ForwardOutput();
        // Returns only when the program ends without giving UIKit the
        // thread, as when it raises before it does.
        int status = fledge_ruby_run_app(RubyRoot().fileSystemRepresentation, 0, NULL);
        os_log(log, "%{public}@ exited with status %d", AppName(), status);
        return status;
    }
}
#else
// The stack of Ruby's thread, as Android's FledgeRuby.STACK_SIZE.
static const NSUInteger RubyStackSize = 64 * 1024 * 1024;

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *controller = [UIViewController new];
    UILabel *label = [UILabel new];
    label.text = AppName();
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
        os_log_t log = ForwardOutput();
        NSString *root = RubyRoot();
        NSThread *ruby = [[NSThread alloc] initWithBlock:^{
            int status = fledge_ruby_run_app(root.fileSystemRepresentation, 0, NULL);
            os_log(log, "%{public}@ exited with status %d", AppName(), status);
        }];
        ruby.name = @"ruby";
        ruby.stackSize = RubyStackSize;
        [ruby start];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
#endif
