package com.weiyalong.naidianji;

import android.app.Instrumentation;
import android.content.Context;
import android.content.res.Configuration;
import android.os.Bundle;
import android.text.Layout;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.RemoteViews;
import android.widget.TextView;

import java.lang.reflect.Method;

/**
 * Runs real RemoteViews layout checks without an external test-runner dependency.
 * From android/: gradlew :app:assembleDebug :app:assembleDebugAndroidTest
 * Install both build/app/outputs/apk/debug/app-debug.apk and
 * build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk, then run:
 * adb shell am instrument -w -r
 * com.weiyalong.naidianji.test/com.weiyalong.naidianji.WidgetLayoutTestRunner
 */
public final class WidgetLayoutTestRunner extends Instrumentation {
    private static final String CLASS_NAME = WidgetLayoutTestRunner.class.getName();
    private int finished;
    private int failed;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override
    public void onStart() {
        // Declared minimum sizes, plus Android's documented Pixel 4 cell estimates.
        check("wideMinimum", 3, 250, 110);
        check("wideLandscape", 3, 554, 117);
        check("squareMinimum", 2, 180, 180);
        check("squarePortrait", 2, 130, 220);
        check("squareLandscape", 2, 269, 117);
        check("compactMinimum", 1, 110, 50);
        check("compactLandscape", 1, 269, 51);
        check("wideUninitialized", 3, 250, 110, 0);
        check("wideNoRecords", 3, 250, 110, 1);
        check("squareUninitialized", 2, 180, 180, 0);
        check("squareNoRecords", 2, 180, 180, 1);
        check("compactUninitialized", 1, 110, 50, 0);
        check("compactNoRecords", 1, 110, 50, 1);
        check("squareZeroMilk", 2, 130, 220, 4);
        check("squareMaximumMilk", 2, 130, 220, 3);
        check("wideZeroMilk", 3, 250, 110, 4);
        check("wideMaximumMilk", 3, 250, 110, 3);
        check("compactGrow", 1, 250, 100, 12);
        check("squareGrow", 2, 270, 220, 12);
        check("wideGrow", 3, 350, 220, 12);
        Bundle results = new Bundle();
        results.putString("stream", "\nWidget layout checks: " + finished + ", failures: " + failed + "\n");
        finish(failed == 0 ? -1 : 0, results);
    }

    private void check(String name, int kind, int widthDp, int heightDp) {
        check(name, kind, widthDp, heightDp, 2);
    }

    private void check(String name, int kind, int widthDp, int heightDp, int state) {
        Bundle status = new Bundle();
        status.putString("class", CLASS_NAME);
        status.putString("test", name);
        status.putInt("numtests", 20);
        status.putInt("current", ++finished);
        status.putString("id", "WidgetLayoutTestRunner");
        sendStatus(1, status);
        final Throwable[] error = {null};
        runOnMainSync(() -> {
            try {
                inspect(kind, widthDp, heightDp, state);
            } catch (Throwable failure) {
                error[0] = failure;
            }
        });
        if (error[0] == null) {
            status.putString("stream", ".");
            sendStatus(0, status);
        } else {
            failed++;
            status.putString("stack", error[0].toString());
            status.putString("stream", "\n" + name + ": " + error[0] + "\n");
            sendStatus(-2, status);
        }
    }

    private void inspect(int kind, int widthDp, int heightDp, int state) throws Exception {
        Configuration config = new Configuration(getTargetContext().getResources().getConfiguration());
        config.fontScale = 1.0f;
        Context context = getTargetContext().createConfigurationContext(config);
        float density = context.getResources().getDisplayMetrics().density;
        String name = kind == 1 ? "compact" : kind == 2 ? "square" : "wide";
        FeedWidgetProvider provider = kind == 1 ? new FeedCompactWidgetProvider()
                : kind == 2 ? new FeedSquareWidgetProvider() : new FeedWideWidgetProvider();
        long instant = 1791705900000L;
        FeedWidgetStore.Snapshot data = new FeedWidgetStore.Snapshot(
                instant, "2026-10-11", 480, state == 1 ? null : instant, 480,
                state == 3 ? 2000 : state == 4 ? 0 : 120, 360, 3,
                state == 1 ? null : instant + 10800000L, 480, false);
        if (state == 0) data = null;
        Method createViews = FeedWidgetProvider.class.getDeclaredMethod(
                "viewsForSize", Context.class, FeedWidgetStore.Snapshot.class, float.class, float.class);
        createViews.setAccessible(true);
        RemoteViews views = (RemoteViews) createViews.invoke(provider, context, data, (float) widthDp, (float) heightDp);
        View root;
        if (state == 12) {
            float smallWidth = kind == 1 ? 110 : kind == 2 ? 269 : 250;
            float smallHeight = kind == 1 ? 50 : kind == 2 ? 117 : 110;
            RemoteViews small = (RemoteViews) createViews.invoke(provider, context, data, smallWidth, smallHeight);
            root = small.apply(context, new FrameLayout(context));
            views.reapply(context, root);
        } else {
            root = views.apply(context, new FrameLayout(context));
        }
        int width = Math.round(widthDp * density);
        int height = Math.round(heightDp * density);
        root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
        root.layout(0, 0, width, height);
        String[] fields = kind == 1 ? new String[]{"value"}
                : kind == 2 ? state <= 1 ? new String[]{"state", "empty_subtitle", "action"}
                    : new String[]{"time", "amount", "action"}
                : state == 0 ? new String[]{"date", "empty_message", "empty_action"}
                : new String[]{"latest", "amount", "total", "count", "action"};
        for (String field : fields) {
            int id = context.getResources().getIdentifier("widget_" + name + "_" + field,
                    "id", context.getPackageName());
            assertReadable((TextView) root.findViewById(id), name + "/" + field);
        }
        if (state == 12) {
            int expectedPadding = (int) (12 * density);
            if (root.getPaddingTop() != expectedPadding || root.getPaddingLeft() != expectedPadding) {
                throw new AssertionError(name + " kept its small padding after growing");
            }
            String[] resetFields = kind == 1 ? new String[]{"label", "value"}
                    : kind == 2 ? new String[]{"title", "time", "next"}
                    : new String[]{"title", "date", "latest", "amount", "updated"};
            float[] resetSizes = kind == 1 ? new float[]{11, 26}
                    : kind == 2 ? new float[]{14, 28, 11}
                    : new float[]{14, 11, 20, 13, 10};
            for (int index = 0; index < resetFields.length; index++) {
                int id = context.getResources().getIdentifier("widget_" + name + "_" + resetFields[index],
                        "id", context.getPackageName());
                TextView text = root.findViewById(id);
                assertReadable(text, name + "/" + resetFields[index]);
                if (Math.abs(text.getTextSize() - resetSizes[index] * density) > 1) {
                    throw new AssertionError(name + "/" + resetFields[index] + " kept its small text size");
                }
            }
        }
    }

    private static void assertReadable(TextView view, String name) {
        if (view == null || view.getVisibility() != View.VISIBLE) {
            throw new AssertionError(name + " is missing");
        }
        Layout text = view.getLayout();
        int available = view.getHeight() - view.getCompoundPaddingTop() - view.getCompoundPaddingBottom();
        if (text == null || text.getHeight() > available) {
            throw new AssertionError(name + " text height " + (text == null ? "null" : text.getHeight())
                    + " exceeds available " + available);
        }
        for (int line = 0; line < text.getLineCount(); line++) {
            if (text.getEllipsisCount(line) != 0) {
                throw new AssertionError(name + " is ellipsized: " + view.getText());
            }
        }
        View child = view;
        int top = 0;
        int bottom = view.getHeight();
        while (child.getParent() instanceof ViewGroup) {
            ViewGroup parent = (ViewGroup) child.getParent();
            top += child.getTop();
            bottom += child.getTop();
            if (parent.getClipChildren() && (top < 0 || bottom > parent.getHeight())) {
                throw new AssertionError(name + " bounds " + top + ".." + bottom
                        + " exceed ancestor height " + parent.getHeight());
            }
            child = parent;
        }
    }
}
