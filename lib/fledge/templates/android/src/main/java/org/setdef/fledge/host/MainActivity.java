// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT

package org.setdef.fledge.host;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;
import java.util.function.IntConsumer;
import org.setdef.fledge.FledgeRuby;

/**
 * The app's one screen, written by fledge build (doc/contributors/design/phone-projects.md): it shows the
 * app's name and runs the app's Ruby program, as fledge.cfg in the asset
 * fledge.zip names it, with FledgeRuby, on Ruby's own thread, with no
 * arguments, since a phone has no command line. What the program prints
 * goes to logcat under the app's identifier, and its exit status under the
 * identifier and ".host".
 * Ruby runs once per process, so an Activity Android creates again does
 * not start it again. Change this screen as your app needs; FledgeRuby's
 * calls are what it must keep.
 *
 * <p>An app whose Ruby draws its own screen with Android's views
 * (kind: windowed in fledge.yml) runs that Ruby on the main thread, the
 * one Android's views belong to, and its program replaces this screen's
 * content with its own, on the activity Android made
 * (doc/contributors/design/phone-widgets.md).
 */
public class MainActivity extends Activity {
    private static boolean started;

    // Whether the app's Ruby draws its own screen (kind: windowed).
    private static final boolean WINDOWED = @@WINDOWED@@;

    // Nothing to load: FledgeRuby loads Ruby's library, and the runtime
    // loads the app's gems' extensions before Ruby boots. A host that
    // replaces this file may still load "fledgeruby" and "fledgeext" by
    // name, as SDL's SDLActivity loads its list.
    @@LOAD_EXTENSIONS@@

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        CharSequence name = getApplicationInfo().loadLabel(getPackageManager());
        TextView text = new TextView(this);
        text.setText(name);
        text.setGravity(Gravity.CENTER);
        setContentView(text);
        synchronized (MainActivity.class) {
            if (started) return;
            started = true;
        }
        String tag = getPackageName();
        // The status goes under a tag of its own, which fledge test reads, so that
        // nothing the program prints, under the app's identifier, can pass for it.
        IntConsumer exited = status -> Log.i(tag + ".host", name + " exited with status " + status);
        if (WINDOWED) {
            FledgeRuby.startAppOnMainThread(this, "fledge.zip", new String[0], exited);
        } else {
            FledgeRuby.startApp(this, "fledge.zip", new String[0], exited);
        }
    }
}
