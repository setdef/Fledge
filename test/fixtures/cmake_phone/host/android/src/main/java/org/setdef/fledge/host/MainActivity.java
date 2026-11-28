// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0

package org.setdef.fledge.host;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import org.setdef.fledge.FledgeRuby;

/**
 * A host of the kind a framework that owns startup ships
 * (fledge.yml's android: host:): Fledge's own MainActivity,
 * but loading the native libraries a host may name, fledgeruby
 * and fledgeext, in a fixed list, as SDL's SDLActivity loads
 * the ones getLibraries() returns, whatever Fledge put inside
 * them. It shows that such a host starts the app.
 */
public class MainActivity extends Activity {
    private static final String[] LIBRARIES = {"fledgeruby", "fledgeext"};
    private static boolean started;

    static {
        for (String library : LIBRARIES) System.loadLibrary(library);
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        synchronized (MainActivity.class) {
            if (started) return;
            started = true;
        }
        CharSequence name = getApplicationInfo().loadLabel(getPackageManager());
        String tag = getPackageName();
        FledgeRuby.startAppOnMainThread(this, "fledge.zip", new String[0], status -> Log.i(tag + ".host", name + " exited with status " + status));
    }
}
