// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

package org.setdef.fledge;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.system.ErrnoException;
import android.system.Os;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.function.IntConsumer;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Fledge's embedding API for Ruby on Android (ADR 011, section 5): the
 * Java half of runtime/mobile/fledge_ruby.h, as thin as Android needs.
 *
 * <p>Ruby reads its standard library and the app's code from files, and
 * an APK's assets are not files, so the app carries the runtime's lib/
 * and libexec/ and its own code, under app/, as one stored zip asset,
 * which {@link #unpack} writes into the app's files folder on the first
 * launch of each installed version, as the mobile spike's host did. Then
 * {@link #run} starts Ruby on the calling thread, with standard output
 * and standard error sent to logcat under the app's package name, and
 * {@link #start} does so on a thread of its own with the deep stack Ruby
 * needs, never the UI thread, which Android stops an app for blocking.
 * {@link #runApp} and {@link #startApp} run the app fledge build put in
 * the asset instead, as its fledge.cfg says, with Bundler set up for an
 * app with a Gemfile. Ruby boots once per process.
 */
public final class FledgeRuby {
    /** The stack of the thread {@link #start} runs Ruby on, as the spike's host gave it. */
    public static final long STACK_SIZE = 64L * 1024 * 1024;

    static {
        System.loadLibrary("fledgeruby");
    }

    private FledgeRuby() {}

    private static native int nativeForwardOutput(byte[] tag);

    private static native int nativeRun(byte[] strings, int argc);

    private static native int nativeRunApp(byte[] strings, int argc);

    /**
     * Unpacks the zip asset named {@code asset} into the app's files
     * folder, unless this installed version of the app unpacked it
     * already, and returns the folder: Ruby's prefix, with the app's code
     * in its app/ folder.
     */
    public static File unpack(Context context, String asset) throws IOException {
        File root = new File(context.getFilesDir(), "fledge");
        File stamp = new File(root, ".fledge-unpacked");
        String version = installedVersion(context);
        if (stamp.isFile() && new String(Files.readAllBytes(stamp.toPath()), StandardCharsets.UTF_8).equals(version)) {
            return root;
        }
        delete(root);
        String base = root.getCanonicalPath() + File.separator;
        byte[] buffer = new byte[1 << 16];
        try (InputStream raw = context.getAssets().open(asset); ZipInputStream zip = new ZipInputStream(raw)) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                File file = new File(root, entry.getName());
                if (!file.getCanonicalPath().startsWith(base)) {
                    throw new IOException(asset + " holds " + entry.getName() + ", outside the folder it unpacks into");
                }
                if (entry.isDirectory()) {
                    file.mkdirs();
                    continue;
                }
                file.getParentFile().mkdirs();
                try (OutputStream out = new FileOutputStream(file)) {
                    int count;
                    while ((count = zip.read(buffer)) > 0) out.write(buffer, 0, count);
                }
            }
        }
        Files.write(stamp.toPath(), version.getBytes(StandardCharsets.UTF_8));
        return root;
    }

    /**
     * Unpacks {@code asset} (see {@link #unpack}), sends standard output
     * and standard error to logcat, and runs the Ruby program
     * {@code script}, a path in the asset's app/ folder, with
     * {@code arguments} as its ARGV, on the calling thread. Returns its
     * exit status. HOME is the app's files folder when Android sets none,
     * as iOS sets HOME to an app's own folder, so Dir.home is writable.
     */
    public static int run(Context context, String asset, String script, String... arguments) throws IOException {
        File root = prepare(context, asset);
        ByteArrayOutputStream strings = new ByteArrayOutputStream();
        append(strings, root.getPath());
        append(strings, new File(new File(root, "app"), script).getPath());
        for (String argument : arguments) append(strings, argument);
        return nativeRun(strings.toByteArray(), arguments.length);
    }

    /**
     * Unpacks {@code asset} (see {@link #unpack}), sends standard output
     * and standard error to logcat, and runs the app fledge build put in
     * it, with {@code arguments} as its ARGV, on the calling thread, as
     * fledge_ruby_run_app does: the program its fledge.cfg names, after
     * Bundler sets up the gems of the Gemfile it names. Returns its exit
     * status.
     */
    public static int runApp(Context context, String asset, String... arguments) throws IOException {
        File root = prepare(context, asset);
        ByteArrayOutputStream strings = new ByteArrayOutputStream();
        append(strings, root.getPath());
        for (String argument : arguments) append(strings, argument);
        return nativeRunApp(strings.toByteArray(), arguments.length);
    }

    /**
     * Calls {@link #run} on a new thread with a stack of
     * {@link #STACK_SIZE} bytes, then {@code exited} with Ruby's exit
     * status, or with 70 (EX_SOFTWARE) when the asset could not be
     * unpacked. Returns the started thread.
     */
    public static Thread start(Context context, String asset, String script, String[] arguments, IntConsumer exited) {
        Context app = context.getApplicationContext();
        return onRubyThread(app, exited, () -> run(app, asset, script, arguments));
    }

    /**
     * Calls {@link #runApp} on a new thread with a stack of
     * {@link #STACK_SIZE} bytes, then {@code exited} with the app's exit
     * status, or with 70 (EX_SOFTWARE) when the asset could not be
     * unpacked. Returns the started thread.
     */
    public static Thread startApp(Context context, String asset, String[] arguments, IntConsumer exited) {
        Context app = context.getApplicationContext();
        return onRubyThread(app, exited, () -> runApp(app, asset, arguments));
    }

    /** What {@link #onRubyThread} runs: Ruby, returning its exit status. */
    private interface Runner {
        int run() throws IOException;
    }

    private static Thread onRubyThread(Context app, IntConsumer exited, Runner runner) {
        Thread thread = new Thread(null, () -> {
            int status;
            try {
                status = runner.run();
            } catch (IOException e) {
                android.util.Log.e(app.getPackageName(), "could not start Ruby", e);
                status = 70;
            }
            exited.accept(status);
        }, "ruby", STACK_SIZE);
        thread.start();
        return thread;
    }

    /**
     * Unpacks {@code asset}, sets HOME to the app's files folder when
     * Android sets none, as iOS sets HOME to an app's own folder, so
     * Dir.home is writable, and sends standard output and standard error
     * to logcat. Returns Ruby's root.
     */
    private static File prepare(Context context, String asset) throws IOException {
        // Canonical, as the desktop launcher resolves its own folder: an
        // app's files folder is /data/user/0/PACKAGE/files, through a
        // link to /data/data, and Ruby resolves __dir__ through it.
        File root = unpack(context, asset).getCanonicalFile();
        try {
            Os.setenv("HOME", context.getFilesDir().getCanonicalPath(), false);
        } catch (ErrnoException e) {
            throw new IOException("could not set HOME", e);
        }
        if (nativeForwardOutput(nul(context.getPackageName())) != 0) {
            throw new IOException("could not send Ruby's output to logcat");
        }
        return root;
    }

    private static byte[] nul(String string) {
        return (string + "\0").getBytes(StandardCharsets.UTF_8);
    }

    private static void append(ByteArrayOutputStream strings, String string) {
        byte[] bytes = nul(string);
        strings.write(bytes, 0, bytes.length);
    }

    /** When this version of the app was installed, which changes with every install or update. */
    private static String installedVersion(Context context) throws IOException {
        try {
            PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            return Long.toString(info.lastUpdateTime);
        } catch (PackageManager.NameNotFoundException e) {
            throw new IOException(e);
        }
    }

    private static void delete(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) delete(child);
        file.delete();
    }
}
