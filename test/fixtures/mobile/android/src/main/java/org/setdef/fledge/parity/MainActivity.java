// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

package org.setdef.fledge.parity;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;
import org.setdef.fledge.FledgeRuby;

/**
 * The mobile parity check's Android host: it runs the script its intent
 * names (the extra "script"; main.rb, the parity probe, by default) with
 * FledgeRuby, on Ruby's own thread, and logs Ruby's exit status, which
 * tasks/mobile_parity/android.rb waits for in logcat. Ruby boots once per
 * process, so a recreated Activity does not start it again.
 */
public class MainActivity extends Activity {
    private static boolean started;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView text = new TextView(this);
        text.setText("Running Ruby...");
        setContentView(text);
        synchronized (MainActivity.class) {
            if (started) return;
            started = true;
        }
        String script = getIntent().getStringExtra("script");
        FledgeRuby.start(this, "fledge.zip", script != null ? script : "main.rb", new String[0], status -> {
            Log.i(getPackageName(), "FLEDGE-MOBILE-STATUS " + status);
            runOnUiThread(() -> text.setText("Ruby exited with status " + status));
        });
    }
}
