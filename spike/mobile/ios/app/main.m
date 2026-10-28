// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Spike (throwaway): the smallest iOS host for an embedded CRuby. main()
// starts Ruby as Fledge's desktop launcher does (runtime/launcher/unix.c,
// after Ruby's main.c at 4.0.9: ruby_sysinit, then RUBY_INIT_STACK,
// ruby_init, ruby_options, ruby_run_node) with the bundled app/main.rb,
// on the main thread, before UIKit starts. Ruby finds its library in
// the app bundle itself: built with --enable-load-relative, it takes the
// folder holding the executable (Foo.app) as its prefix, so
// Foo.app/lib/ruby/4.0.0 is its standard library (ruby.c,
// ruby_init_loadpath). An iOS app's stdout goes nowhere unless a
// debugger or simctl captures it, so a thread copies stdout and stderr,
// line by line, to the unified log (os_log) as well as to the original
// stdout. Then a one-label UIKit scene shows Ruby's exit status. Passing
// -FledgeExitAfterRuby YES (simctl launch arguments) exits instead.
#import <UIKit/UIKit.h>
#include <os/log.h>
#include <pthread.h>
#include <unistd.h>
#include <ruby.h>

static int ruby_status = -1;
static os_log_t ruby_log;

static void *forward_output(void *arg) {
    int fds[2];
    memcpy(fds, arg, sizeof fds);
    FILE *in = fdopen(fds[0], "r");
    FILE *out = fdopen(fds[1], "w");
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    while ((len = getline(&line, &cap, in)) > 0) {
        os_log(ruby_log, "%{public}.*s", (int)(line[len - 1] == '\n' ? len - 1 : len), line);
        fwrite(line, 1, (size_t)len, out);
        fflush(out);
    }
    return NULL;
}

static void redirect_output_to_log(void) {
    static int fds[2];
    int pipefd[2];
    if (pipe(pipefd) != 0) return;
    fds[0] = pipefd[0];
    fds[1] = dup(STDOUT_FILENO);
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);
    setvbuf(stdout, NULL, _IOLBF, 0);
    pthread_t thread;
    pthread_create(&thread, NULL, forward_output, fds);
    pthread_detach(thread);
}

static int run_ruby(int argc, char **argv) {
    NSString *program = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"app/main.rb"];
    char *ruby_argv[] = {argv[0], "--disable=rubyopt", "--", (char *)program.fileSystemRepresentation, NULL};
    int ruby_argc = 4;
    char **sysinit_argv = ruby_argv;
    ruby_sysinit(&ruby_argc, &sysinit_argv);
    {
        RUBY_INIT_STACK;
        ruby_init();
        return ruby_run_node(ruby_options(ruby_argc, ruby_argv));
    }
}

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
    ruby_log = os_log_create("org.setdef.fledge.spike", "ruby");
    redirect_output_to_log();
    ruby_status = run_ruby(argc, argv);
    fflush(stdout);
    fflush(stderr);
    os_log(ruby_log, "FLEDGE-SPIKE-STATUS %d", ruby_status);
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FledgeExitAfterRuby"]) {
        usleep(300000); // let the forwarding thread drain
        exit(ruby_status);
    }
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
