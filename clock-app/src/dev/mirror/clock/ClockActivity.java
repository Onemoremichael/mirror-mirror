package dev.mirror.clock;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.view.Gravity;

public class ClockActivity extends Activity {
    private static final String OFFLINE = "file:///android_asset/clock/index.html";
    private final Handler handler = new Handler();
    private WebView web;
    private String liveUrl = "";
    private boolean showingOffline;
    private MirrorAudio audioBridge;
    private boolean audioEnabled;
    private ConversationIndicator micIndicator;
    private final Runnable retry = new Runnable() { public void run() { if (!liveUrl.isEmpty()) loadLive(); } };
    private final Runnable loadDeadline = new Runnable() { public void run() { fallback(); } };

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        web = new WebView(this);
        web.setBackgroundColor(Color.BLACK);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(true);
        web.getSettings().setAllowContentAccess(false);
        web.getSettings().setAllowFileAccessFromFileURLs(true);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {
                // Keep the wrapper scoped to its configured site and bundled assets.
                return !isAllowed(url);
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (!showingOffline && url.equals(liveUrl)) handler.removeCallbacks(loadDeadline);
                immersive();
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame() && !showingOffline) fallback();
            }
            @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse error) {
                if (request.isForMainFrame() && !showingOffline) fallback();
            }
        });
        FrameLayout frame=new FrameLayout(this);frame.addView(web);
        micIndicator=new ConversationIndicator(this);
        float density=getResources().getDisplayMetrics().density;
        FrameLayout.LayoutParams badge=new FrameLayout.LayoutParams((int)(112*density),(int)(60*density),Gravity.TOP|Gravity.RIGHT);
        badge.topMargin=(int)(24*density);badge.rightMargin=(int)(24*density);
        frame.addView(micIndicator,badge);setContentView(frame);
        liveUrl = getPreferences(MODE_PRIVATE).getString("liveUrl", "");
        configure(getIntent());
    }
    private boolean isAllowed(String url) {
        if (url.equals(OFFLINE)) return true;
        if (liveUrl.isEmpty()) return false;
        Uri target = Uri.parse(url), configured = Uri.parse(liveUrl);
        return configured.getScheme().equals(target.getScheme()) && configured.getHost().equals(target.getHost()) && configured.getPort() == target.getPort();
    }
    private boolean validUrl(String url) {
        Uri uri = Uri.parse(url);
        return ("http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) && uri.getHost() != null && uri.getUserInfo() == null;
    }
    private void configure(Intent intent) {
        audioEnabled=intent.getBooleanExtra("audioBridge",false);
        if(!audioEnabled&&audioBridge!=null){audioBridge.close();audioBridge=null;}
        if(audioEnabled&&checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)!=android.content.pm.PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO},42);
        String orientation = intent.getStringExtra("orientation");
        if (orientation == null) orientation = getPreferences(MODE_PRIVATE).getString("orientation", "portrait");
        orient(orientation);
        String requested = intent.getStringExtra("url");
        if (requested != null && validUrl(requested)) liveUrl = requested;
        if (intent.getBooleanExtra("offline", false)) liveUrl = "";
        getPreferences(MODE_PRIVATE).edit().putString("liveUrl", liveUrl).apply();
        if (liveUrl.isEmpty()) fallback(); else loadLive();
    }
    private void loadLive() {
        handler.removeCallbacks(retry); handler.removeCallbacks(loadDeadline);
        showingOffline = false; web.loadUrl(liveUrl);
        handler.postDelayed(loadDeadline, 12000);
    }
    private void fallback() {
        handler.removeCallbacks(loadDeadline); handler.removeCallbacks(retry);
        showingOffline = true; web.stopLoading(); web.loadUrl(OFFLINE);
        if (!liveUrl.isEmpty()) handler.postDelayed(retry, 60000);
    }
    private void immersive() {
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }
    private void orient(String orientation) {
        boolean landscape = "landscape".equals(orientation);
        getPreferences(MODE_PRIVATE).edit().putString("orientation", landscape ? "landscape" : "portrait").apply();
        setRequestedOrientation(landscape ? ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE : ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
    }
    @Override public void onWindowFocusChanged(boolean focused) { super.onWindowFocusChanged(focused); if (focused) immersive(); }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); configure(intent); }
    @Override public void onBackPressed() { finish(); }
    @Override protected void onResume(){super.onResume();startAudioBridge();}
    private void startAudioBridge(){if(audioEnabled&&audioBridge==null&&checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)==android.content.pm.PackageManager.PERMISSION_GRANTED)audioBridge=new MirrorAudio((phase,level)->runOnUiThread(()->micIndicator.update(phase,level)));}
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==42)startAudioBridge();}
    @Override protected void onPause(){if(audioBridge!=null){audioBridge.close();audioBridge=null;}super.onPause();}
    @Override public boolean onKeyDown(int key, KeyEvent event) {
        if (key == KeyEvent.KEYCODE_MENU) { menu(); return true; }
        return super.onKeyDown(key, event);
    }
    private void menu() {
        new AlertDialog.Builder(this).setTitle("Afterglow").setItems(new String[]{"Reload live clock", "Use bundled clock", "Set live page address", "Portrait", "Landscape", "Exit to Android"}, (dialog, which) -> {
            if (which == 0) { if (liveUrl.isEmpty()) fallback(); else loadLive(); }
            if (which == 1) { liveUrl = ""; getPreferences(MODE_PRIVATE).edit().putString("liveUrl", "").apply(); fallback(); }
            if (which == 2) {
                final EditText field = new EditText(this); field.setSingleLine(true); field.setText(liveUrl); field.setHint("http://your-mac:8766/");
                new AlertDialog.Builder(this).setTitle("Live page address").setView(field).setNegativeButton("Cancel", null).setPositiveButton("Open", (d, w) -> {
                    String url = field.getText().toString().trim();
                    if (validUrl(url)) { liveUrl = url; getPreferences(MODE_PRIVATE).edit().putString("liveUrl", url).apply(); loadLive(); }
                }).show();
            }
            if (which == 3) orient("portrait");
            if (which == 4) orient("landscape");
            if (which == 5) finish();
        }).show();
    }
    @Override protected void onDestroy() {
        handler.removeCallbacksAndMessages(null); web.destroy(); super.onDestroy();
    }
}
