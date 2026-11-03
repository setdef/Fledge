// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: MIT-0
//
// The app's entry point when SDL3 owns the screen (ADR 025), in place of
// the Host/main.m fledge build writes. SDL_RunApp starts UIKit with SDL's
// own delegates (src/video/uikit/SDL_uikitappdelegate.m at release-3.4.18,
// lines 43 to 64), and once the scene connects calls run_ruby on the main
// thread, inside the run loop (lines 354 to 420 and 481 to 489), where
// SDL's video must run. run_ruby runs the app's Ruby program there, with
// FledgeRuby's fledge_ruby_run_app, as Fledge's host does on a thread of
// its own, so Ruby can call SDL directly. The main thread's stack is the
// one the executable asks for, with -Wl,-stack_size in OTHER_LDFLAGS.
// Info.plist names SDLUIKitSceneDelegate as the scene's delegate.
@import FledgeRuby;
@import Foundation;

#include <errno.h>
#include <os/log.h>
#include <string.h>

// SDL_main.h's SDL_main_func and SDL_RunApp, from SDL3, which the app's
// gem links in; declared here so the host needs no SDL headers.
typedef int (*SDL_main_func)(int argc, char *argv[]);
extern int SDL_RunApp(int argc, char *argv[], SDL_main_func main_function, void *reserved);

static os_log_t app_log;

static NSString *AppName(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
}

// SDL's main function: runs the app's Ruby program on the calling thread,
// the main thread, and logs its exit status.
static int run_ruby(int argc, char *argv[]) {
    NSString *root = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"fledge"];
    int status = fledge_ruby_run_app(root.fileSystemRepresentation, 0, NULL);
    os_log(app_log, "%{public}@ exited with status %d", AppName(), status);
    return status;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        app_log = os_log_create(identifier.UTF8String, "app");
        if (fledge_ruby_forward_output(identifier.UTF8String) != 0) {
            os_log_error(app_log, "could not send the app's output to the log: %{public}s", strerror(errno));
        }
    }
    return SDL_RunApp(argc, argv, run_ruby, NULL);
}
