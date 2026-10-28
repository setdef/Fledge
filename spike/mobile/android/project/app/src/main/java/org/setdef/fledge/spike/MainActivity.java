// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Spike (throwaway): the Java half of the smallest Android host. Ruby
// reads its standard library and the app's files from ordinary paths,
// and an APK's assets are not files, so on the first launch of each
// installed version the stored zip asset fledge.zip (lib/ruby/... and
// app/main.rb) is extracted into the app's files folder. Then Ruby runs
// on a thread of its own with a large stack: not the UI thread, which
// Android kills an app for blocking (ANR). CRuby can boot only once per
// process, so a recreated Activity does not start it again.
package org.setdef.fledge.spike;

import android.app.Activity;
import android.content.pm.PackageInfo;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class MainActivity extends Activity {
    private static final String TAG = "FledgeRuby";
    private static boolean started;

    static {
        System.loadLibrary("fledgeapp");
    }

    private static native int runRuby(String root);

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
        new Thread(null, () -> {
            File root = new File(getFilesDir(), "fledge");
            try {
                long begin = SystemClock.elapsedRealtime();
                boolean extracted = extract(root);
                Log.i(TAG, "FLEDGE-SPIKE-EXTRACT extracted=" + extracted + " ms=" + (SystemClock.elapsedRealtime() - begin));
            } catch (IOException e) {
                Log.e(TAG, "FLEDGE-SPIKE-EXTRACT failed", e);
                return;
            }
            long begin = SystemClock.elapsedRealtime();
            int status = runRuby(root.getAbsolutePath());
            Log.i(TAG, "FLEDGE-SPIKE-RUBY ms=" + (SystemClock.elapsedRealtime() - begin));
            runOnUiThread(() -> text.setText("Ruby exited with status " + status));
        }, "ruby", 64L * 1024 * 1024).start();
    }

    private boolean extract(File root) throws IOException {
        String stamp;
        try {
            PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            stamp = info.getLongVersionCode() + "-" + info.lastUpdateTime;
        } catch (Exception e) {
            throw new IOException(e);
        }
        File stampFile = new File(root, ".stamp");
        if (stampFile.exists() && new String(Files.readAllBytes(stampFile.toPath()), StandardCharsets.UTF_8).equals(stamp)) {
            return false;
        }
        deleteTree(root);
        byte[] buffer = new byte[1 << 16];
        try (InputStream raw = getAssets().open("fledge.zip"); ZipInputStream zip = new ZipInputStream(raw)) {
            ZipEntry entry;
            String base = root.getCanonicalPath() + File.separator;
            while ((entry = zip.getNextEntry()) != null) {
                File out = new File(root, entry.getName());
                if (!out.getCanonicalPath().startsWith(base)) throw new IOException("bad entry " + entry.getName());
                if (entry.isDirectory()) {
                    out.mkdirs();
                    continue;
                }
                out.getParentFile().mkdirs();
                try (OutputStream os = new FileOutputStream(out)) {
                    int n;
                    while ((n = zip.read(buffer)) > 0) os.write(buffer, 0, n);
                }
            }
        }
        Files.write(stampFile.toPath(), stamp.getBytes(StandardCharsets.UTF_8));
        return true;
    }

    private static void deleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) deleteTree(child);
        file.delete();
    }
}
