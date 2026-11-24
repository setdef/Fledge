// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0
//
// Basket's screen on iOS, in UIKit, in place of the one fledge build
// writes (fledge.yml names this folder as the iOS host). Ruby keeps the
// list, and this file shows it: a table in a navigation controller, with
// a field to add an item, a tap to tick one, and a button that clears
// the ticked ones, as the system's own apps draw a list.
//
// It starts main.rb as Fledge's host does, with fledge_ruby_run_app on a
// thread with a deep stack, and gives it two pipes in its arguments
// (--in FD --out FD): this file writes a command a line down the first,
// and a thread of its own reads each list main.rb answers with from the
// second, one line of JSON, and shows it on the main thread.
@import FledgeRuby;
@import UIKit;

#include <errno.h>
#include <os/log.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// The stack of Ruby's thread, as Android's FledgeRuby.STACK_SIZE.
static const NSUInteger RubyStackSize = 64 * 1024 * 1024;

static os_log_t Log;

// The pipe's end the commands go down.
static FILE *Commands;

static NSString *AppName(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
}

// Sends main.rb one command, on one line.
static void Send(NSString *command) {
    NSArray *parts = [command componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    fprintf(Commands, "%s\n", [parts componentsJoinedByString:@" "].UTF8String);
    fflush(Commands);
}

@interface ListController : UITableViewController <UITextFieldDelegate>
- (void)show:(NSArray<NSDictionary *> *)items;
@end

// The list's screen, once the scene has made it, and the last list
// main.rb sent, for a screen made after it came.
static ListController *Screen;
static NSArray<NSDictionary *> *Latest;

@implementation ListController {
    NSArray<NSDictionary *> *_items;
    UITableViewCell *_adding;
    UITextField *_field;
    BOOL _shown;
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = AppName();
        _items = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(clear)];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"item"];

    _field = [UITextField new];
    _field.placeholder = @"Add an item";
    _field.returnKeyType = UIReturnKeyDone;
    _field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.delegate = self;
    _field.translatesAutoresizingMaskIntoConstraints = NO;
    _adding = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    _adding.selectionStyle = UITableViewCellSelectionStyleNone;
    [_adding.contentView addSubview:_field];
    UILayoutGuide *margins = _adding.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_field.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_field.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_field.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [_field.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
    ]];

    if (Latest) [self show:Latest];
}

- (void)show:(NSArray<NSDictionary *> *)items {
    _items = items;
    BOOL ticked = NO;
    for (NSDictionary *item in items) ticked = ticked || [item[@"done"] boolValue];
    self.navigationItem.rightBarButtonItem.enabled = ticked;
    [self.tableView reloadData];
    if (!_shown) {
        _shown = YES;
        os_log(Log, "%{public}@ shows %lu %{public}s", AppName(), (unsigned long)items.count, items.count == 1 ? "item" : "items");
    }
}

- (void)clear {
    Send(@"clear");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (NSInteger)_items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 1 && _items.count == 0 ? @"Nothing to buy." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return _adding;

    NSDictionary *item = _items[(NSUInteger)indexPath.row];
    BOOL done = [item[@"done"] boolValue];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item" forIndexPath:indexPath];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = item[@"name"];
    content.textProperties.color = done ? UIColor.secondaryLabelColor : UIColor.labelColor;
    cell.contentConfiguration = content;
    cell.accessoryType = done ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [_field becomeFirstResponder];
    } else {
        Send([@"tick " stringByAppendingString:_items[(NSUInteger)indexPath.row][@"id"]]);
    }
}

// Adds what the field holds, and keeps the keyboard up for the next item.
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSString *name = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length > 0) Send([@"add " stringByAppendingString:name]);
    field.text = @"";
    return NO;
}
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    Screen = [ListController new];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:Screen];
    [window makeKeyAndVisible];
    self.window = window;
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
@end

// Reads each list main.rb sends from the pipe +fd+, and shows it.
static void ReadLists(int fd) {
    FILE *lists = fdopen(fd, "r");
    char *line = NULL;
    size_t size = 0;
    ssize_t length;
    while ((length = getline(&line, &size, lists)) > 0) {
        NSData *data = [NSData dataWithBytes:line length:(NSUInteger)length];
        NSArray *items = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![items isKindOfClass:NSArray.class]) continue;
        dispatch_async(dispatch_get_main_queue(), ^{
            Latest = items;
            [Screen show:items];
        });
    }
    free(line);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        NSString *root = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"fledge"];
        Log = os_log_create(identifier.UTF8String, "app");
        if (fledge_ruby_forward_output(identifier.UTF8String) != 0) {
            os_log_error(Log, "could not send the app's output to the log: %{public}s", strerror(errno));
        }

        // A command written after Ruby has ended fails, rather than
        // ending the app with SIGPIPE.
        signal(SIGPIPE, SIG_IGN);
        int commands[2], lists[2];
        if (pipe(commands) != 0 || pipe(lists) != 0) {
            os_log_error(Log, "could not make the pipes to Ruby: %{public}s", strerror(errno));
            return 1;
        }
        Commands = fdopen(commands[1], "w");
        int answers = lists[0];
        static char in[16], out[16], inFlag[] = "--in", outFlag[] = "--out";
        snprintf(in, sizeof in, "%d", commands[0]);
        snprintf(out, sizeof out, "%d", lists[1]);
        static char *const arguments[] = {inFlag, in, outFlag, out};

        NSThread *ruby = [[NSThread alloc] initWithBlock:^{
            int status = fledge_ruby_run_app(root.fileSystemRepresentation, 4, arguments);
            os_log(Log, "%{public}@ exited with status %d", AppName(), status);
        }];
        ruby.name = @"ruby";
        ruby.stackSize = RubyStackSize;
        [ruby start];
        NSThread *reader = [[NSThread alloc] initWithBlock:^{
            ReadLists(answers);
        }];
        reader.name = @"lists";
        [reader start];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
