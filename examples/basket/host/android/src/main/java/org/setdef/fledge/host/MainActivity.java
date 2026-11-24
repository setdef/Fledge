// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT-0

package org.setdef.fledge.host;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.text.InputType;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.view.inputmethod.EditorInfo;
import android.widget.AbsListView;
import android.widget.ArrayAdapter;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.setdef.fledge.FledgeRuby;

/**
 * Basket's screen on Android, in Android's own views, in place of the one
 * fledge build writes (fledge.yml names this folder as the Android host).
 * Ruby keeps the list, and this class shows it: a field to add an item, a
 * list with a check box for each, and a Clear action in the app bar that
 * removes the ticked ones.
 *
 * <p>It starts main.rb with FledgeRuby, as Fledge's host does, and gives
 * it two pipes in its arguments (--in FD --out FD): this class writes a
 * command a line down the first, and a thread of its own reads each list
 * main.rb answers with from the second, one line of JSON, and shows it on
 * the main thread. Ruby runs once per process, so the pipes and the last
 * list outlive an Activity Android creates again.
 */
public class MainActivity extends Activity {
    private static Writer commands;
    private static JSONArray latest;
    private static MainActivity shown;
    private static boolean logged;

    private final List<String> names = new ArrayList<>();
    private final List<String> ids = new ArrayList<>();
    private ArrayAdapter<String> adapter;
    private ListView list;
    private MenuItem clear;
    private boolean ticked;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        EditText field = new EditText(this);
        field.setHint("Add an item");
        field.setSingleLine();
        field.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        field.setImeOptions(EditorInfo.IME_ACTION_DONE);
        // Adds what the field holds, and keeps the keyboard up for the
        // next item.
        field.setOnEditorActionListener((view, action, event) -> {
            String name = field.getText().toString().trim();
            if (!name.isEmpty()) send("add " + name);
            field.setText("");
            return true;
        });

        adapter = new ArrayAdapter<>(this, android.R.layout.simple_list_item_multiple_choice, names);
        list = new ListView(this);
        list.setChoiceMode(AbsListView.CHOICE_MODE_MULTIPLE);
        list.setAdapter(adapter);
        list.setOnItemClickListener((parent, view, position, id) -> send("tick " + ids.get(position)));

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        // Clear of the system's bars, which an app that targets API 35
        // or later draws under, with Material's 16 dp at the sides.
        layout.setFitsSystemWindows(true);
        int margin = Math.round(16 * getResources().getDisplayMetrics().density);
        LinearLayout.LayoutParams top = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        top.setMargins(margin, 0, margin, 0);
        LinearLayout.LayoutParams rest = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1);
        rest.setMargins(margin, 0, margin, 0);
        layout.addView(field, top);
        layout.addView(list, rest);
        setContentView(layout);

        shown = this;
        synchronized (MainActivity.class) {
            if (commands == null) start();
        }
        if (latest != null) show(latest);
    }

    @Override
    protected void onDestroy() {
        if (shown == this) shown = null;
        super.onDestroy();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        clear = menu.add("Clear");
        clear.setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM);
        clear.setEnabled(ticked);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item != clear) return super.onOptionsItemSelected(item);
        send("clear");
        return true;
    }

    /** Shows the list main.rb sent, and logs the first it shows. */
    private void show(JSONArray items) {
        names.clear();
        ids.clear();
        ticked = false;
        for (int index = 0; index < items.length(); index++) {
            JSONObject item = items.optJSONObject(index);
            names.add(item.optString("name"));
            ids.add(item.optString("id"));
            ticked |= item.optBoolean("done");
        }
        adapter.notifyDataSetChanged();
        for (int index = 0; index < items.length(); index++) {
            list.setItemChecked(index, items.optJSONObject(index).optBoolean("done"));
        }
        if (clear != null) clear.setEnabled(ticked);
        if (!logged) {
            logged = true;
            int count = items.length();
            Log.i(getPackageName(), getTitle() + " shows " + count + (count == 1 ? " item" : " items"));
        }
    }

    /** Sends main.rb one command, on one line. */
    private void send(String command) {
        try {
            commands.write(command.replaceAll("[\r\n]+", " ") + "\n");
            commands.flush();
        } catch (IOException e) {
            Log.e(getPackageName(), "could not send Ruby " + command + ": " + e);
        }
    }

    /** Starts main.rb with the two pipes, and the thread that reads its lists. */
    private void start() {
        String tag = getPackageName();
        CharSequence name = getTitle();
        ParcelFileDescriptor[] toRuby;
        ParcelFileDescriptor[] fromRuby;
        try {
            toRuby = ParcelFileDescriptor.createPipe();
            fromRuby = ParcelFileDescriptor.createPipe();
        } catch (IOException e) {
            Log.e(tag, "could not make the pipes to Ruby: " + e);
            return;
        }
        commands = new OutputStreamWriter(new ParcelFileDescriptor.AutoCloseOutputStream(toRuby[1]), StandardCharsets.UTF_8);
        String in = Integer.toString(toRuby[0].detachFd());
        String out = Integer.toString(fromRuby[1].detachFd());

        Handler main = new Handler(Looper.getMainLooper());
        Thread reader = new Thread(() -> {
            try (BufferedReader lists = new BufferedReader(
                    new InputStreamReader(new ParcelFileDescriptor.AutoCloseInputStream(fromRuby[0]), StandardCharsets.UTF_8))) {
                for (String line; (line = lists.readLine()) != null; ) {
                    JSONArray items;
                    try {
                        items = new JSONArray(line);
                    } catch (JSONException e) {
                        Log.e(tag, "Ruby sent a line that is no list: " + line);
                        continue;
                    }
                    main.post(() -> {
                        latest = items;
                        if (shown != null) shown.show(items);
                    });
                }
            } catch (IOException e) {
                Log.e(tag, "could not read Ruby's lists: " + e);
            }
        }, "lists");
        reader.start();

        FledgeRuby.startApp(this, "fledge.zip", new String[] {"--in", in, "--out", out},
                status -> Log.i(tag, name + " exited with status " + status));
    }
}
