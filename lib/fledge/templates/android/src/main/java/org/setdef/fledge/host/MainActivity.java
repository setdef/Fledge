// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT

package org.setdef.fledge.host;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import java.util.function.IntConsumer;
import org.setdef.fledge.FledgeRuby;

/**
 * The app's activity, written by fledge build: it runs the app's
 * Ruby program, as fledge.cfg in the asset fledge.zip names it,
 * with FledgeRuby, on the main thread, the thread the process
 * started on, as ruby main.rb runs a program on a computer, with
 * no arguments, since a phone has no command line. What the
 * program prints goes to logcat under the app's identifier, and
 * its exit status under the identifier and ".host". Ruby runs
 * once per process, so an Activity Android creates again does
 * not start it again. The activity shows nothing of its own: a
 * program that shows a screen draws it with Android's views on
 * this activity, and hands the main thread back to Android by
 * running its loop of messages. Change this file as your app
 * needs; FledgeRuby's call is what it must keep.
 */
public class MainActivity extends Activity {
    private static boolean started;

    // Nothing to load: FledgeRuby loads Ruby's library, and the runtime
    // loads the app's gems' extensions before Ruby boots. A host that
    // replaces this file may still load "fledgeruby" and "fledgeext" by
    // name, as SDL's SDLActivity loads its list.
    @@LOAD_EXTENSIONS@@

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        synchronized (MainActivity.class) {
            if (started) return;
            started = true;
        }
        CharSequence name = getApplicationInfo().loadLabel(getPackageManager());
        String tag = getPackageName();
        // The status goes under a tag of its own, which fledge test reads, so that
        // nothing the program prints, under the app's identifier, can pass for it.
        IntConsumer exited = status -> Log.i(tag + ".host", name + " exited with status " + status);
        FledgeRuby.startAppOnMainThread(this, "fledge.zip", new String[0], exited);
    }
}
