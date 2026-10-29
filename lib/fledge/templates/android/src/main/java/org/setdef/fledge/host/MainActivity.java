// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

package org.setdef.fledge.host;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;
import org.setdef.fledge.FledgeRuby;

/**
 * The app's one screen, written by fledge build (ADR 012): it shows the
 * app's name and runs the app's Ruby program, as fledge.cfg in the asset
 * fledge.zip names it, with FledgeRuby, on Ruby's own thread, with no
 * arguments, since a phone has no command line. What the program prints
 * goes to logcat under the app's identifier, and so does its exit status.
 * Ruby runs once per process, so an Activity Android creates again does
 * not start it again. Change this screen as your app needs; FledgeRuby's
 * calls are what it must keep.
 */
public class MainActivity extends Activity {
    private static boolean started;

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
        FledgeRuby.startApp(this, "fledge.zip", new String[0], status -> Log.i(tag, name + " exited with status " + status));
    }
}
