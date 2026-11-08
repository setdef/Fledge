// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0

package org.setdef.fledge.host;

import android.util.Log;
import org.libsdl.app.SDLActivity;
import org.setdef.fledge.FledgeRuby;

/**
 * The app's screen when SDL3 owns it (ADR 025), in place of the
 * MainActivity fledge build writes, under the same name, so the manifest
 * stays as it is. SDL's Java side needs an Activity, which makes the
 * surface SDL draws on and passes it touches, and it starts the game's
 * main function on a thread it names SDLThread (SDLActivity.java at
 * release-3.4.18, lines 254 to 262 and 2169 to 2190). This class loads
 * libSDL3.so first, whose JNI_OnLoad registers SDL's Java methods, then
 * Ruby and the app's extensions, and runs the app's Ruby program from
 * SDL's main: on a separate thread with FledgeRuby's 64 MB stack,
 * which SDLThread waits for, so the game ends when Ruby does. Launched
 * with the extra fledge.sdlthread set to true, it runs Ruby on SDLThread
 * itself instead, whose stack is the system's default for a thread, to
 * measure it.
 */
public class MainActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] {"SDL3", "fledgeruby", "fledgeext"};
    }

    @Override
    protected void main() {
        String tag = getPackageName();
        CharSequence name = getApplicationInfo().loadLabel(getPackageManager());
        if (getIntent().getBooleanExtra("fledge.sdlthread", false)) {
            int status;
            try {
                status = FledgeRuby.runApp(this, "fledge.zip");
            } catch (java.io.IOException e) {
                Log.e(tag, "could not start Ruby", e);
                status = 70;
            }
            Log.i(tag, name + " exited with status " + status);
            return;
        }
        Thread ruby = FledgeRuby.startApp(this, "fledge.zip", new String[0], status -> Log.i(tag, name + " exited with status " + status));
        try {
            ruby.join();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
