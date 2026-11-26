// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT
//
// The app's main function, written by fledge build
// (doc/contributors/design/phone-projects.md). It sends standard output
// and standard error to os_log, with the app's bundle identifier as
// subsystem, and runs the app's Ruby program, as fledge.cfg in the
// bundle's fledge/ folder names it, through FledgeRuby's
// fledge_ruby_run_app, on the main thread, the thread the process
// started on, as ruby main.rb runs a program on a computer. The linker
// gives that thread a 64 MB stack (-stack_size in project.yml). It
// passes no arguments, since a phone has no command line, and logs the
// program's exit status when it ends, which ends the app.
//
// A program that shows a screen hands the main thread to UIKit itself,
// by calling UIApplicationMain as an Objective-C app's main function
// does, with the delegates it defines in Ruby, SceneDelegate among them,
// which Info.plist lists. iOS ends a program that has not called it
// within 20 seconds of its launch on a device
// (doc/contributors/design/phone-widgets.md, "Threads"). Change this
// file as your app needs; the two FledgeRuby calls are what it must keep.
@import FledgeRuby;
@import UIKit;

#include <errno.h>
#include <os/log.h>
#include <string.h>

int main(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSString *identifier = bundle.bundleIdentifier;
        NSString *name = bundle.infoDictionary[@"CFBundleDisplayName"] ?: bundle.infoDictionary[@"CFBundleName"];
        os_log_t log = os_log_create(identifier.UTF8String, "app");
        if (fledge_ruby_forward_output(identifier.UTF8String) != 0) {
            os_log_error(log, "could not send the app's output to the log: %{public}s", strerror(errno));
        }
        NSString *root = [bundle.resourcePath stringByAppendingPathComponent:@"fledge"];
        // Returns when the program ends without giving UIKit the thread,
        // as a program that shows no screen does.
        int status = fledge_ruby_run_app(root.fileSystemRepresentation, 0, NULL);
        os_log(log, "%{public}@ exited with status %d", name, status);
        return status;
    }
}
