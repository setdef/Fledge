// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Spike (throwaway): the JNI half of the smallest Android host for an
// embedded CRuby. MainActivity extracts the Ruby tree and app/ from the
// APK's assets into its files folder, then calls runRuby(root) on a
// thread of its own. This starts Ruby as Fledge's desktop launcher does
// (runtime/launcher/unix.c, after Ruby's main.c at 4.0.9): ruby_sysinit,
// RUBY_INIT_STACK, ruby_init, ruby_options with
// "--disable=rubyopt -- ROOT/app/main.rb", ruby_run_node. Android
// discards a process's stdout and stderr, so a thread copies both, line
// by line, to logcat under the tag FledgeRuby.
#include <android/log.h>
#include <jni.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ruby.h>

extern const char *ruby_embed_libruby_path; // the spike's patch to ruby.c

static void *forward_output(void *arg) {
    FILE *in = fdopen((int)(intptr_t)arg, "r");
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    while ((len = getline(&line, &cap, in)) > 0) {
        if (line[len - 1] == '\n') line[len - 1] = '\0';
        __android_log_write(ANDROID_LOG_INFO, "FledgeRuby", line);
    }
    return NULL;
}

static void redirect_output_to_logcat(void) {
    int fds[2];
    if (pipe(fds) != 0) return;
    dup2(fds[1], STDOUT_FILENO);
    dup2(fds[1], STDERR_FILENO);
    close(fds[1]);
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    pthread_t thread;
    pthread_create(&thread, NULL, forward_output, (void *)(intptr_t)fds[0]);
    pthread_detach(thread);
}

static int run(const char *root) {
    static char libruby[4096], program[4096];
    // Ruby strips the file name and a trailing /lib from this path to
    // get its prefix (ruby.c, ruby_init_loadpath), so ROOT/lib/x makes
    // ROOT the prefix and ROOT/lib/ruby/4.0.0 the standard library.
    snprintf(libruby, sizeof libruby, "%s/lib/libruby.so", root);
    snprintf(program, sizeof program, "%s/app/main.rb", root);
    ruby_embed_libruby_path = libruby;
    char *argv[] = {"ruby", "--disable=rubyopt", "--", program, NULL};
    int argc = 4;
    char **sysinit_argv = argv;
    ruby_sysinit(&argc, &sysinit_argv);
    {
        RUBY_INIT_STACK;
        ruby_init();
        return ruby_run_node(ruby_options(argc, argv));
    }
}

JNIEXPORT jint JNICALL
Java_org_setdef_fledge_spike_MainActivity_runRuby(JNIEnv *env, jclass cls, jstring jroot) {
    (void)cls;
    redirect_output_to_logcat();
    const char *root = (*env)->GetStringUTFChars(env, jroot, NULL);
    int status = run(root);
    (*env)->ReleaseStringUTFChars(env, jroot, root);
    fflush(stdout);
    fflush(stderr);
    __android_log_print(ANDROID_LOG_INFO, "FledgeRuby", "FLEDGE-SPIKE-STATUS %d", status);
    return status;
}
