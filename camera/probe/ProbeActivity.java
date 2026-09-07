package dev.mirror.cameraprobe;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.hardware.Camera;
import android.graphics.ImageFormat;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.util.Log;
import java.io.FileOutputStream;

public class ProbeActivity extends Activity implements SurfaceHolder.Callback {
    Camera camera;
    TextView status;
    int frames, width, height;
    long started;
    final Handler handler = new Handler();
    String report = "";
    void note(String text) {
        report += text + "\n";
        Log.i("MirrorCameraProbe", text);
        status.setText(text);
        try (FileOutputStream out = openFileOutput("report.txt", MODE_PRIVATE)) { out.write(report.getBytes("UTF-8")); } catch (Exception e) { Log.e("MirrorCameraProbe", "Report write", e); }
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        FrameLayout layout = new FrameLayout(this);
        SurfaceView surface = new SurfaceView(this);
        layout.addView(surface);
        status = new TextView(this); status.setTextColor(0xffffffff); status.setBackgroundColor(0xcc000000); status.setTextSize(16);
        layout.addView(status); setContentView(layout);
        surface.getHolder().addCallback(this);
        note("Camera probe ready");
    }
    @Override public void surfaceCreated(SurfaceHolder holder) {
        try {
            camera = Camera.open(0);
            camera.setErrorCallback((error, c) -> note("CAMERA_ERROR " + error + " frames=" + frames));
            Camera.Parameters params = camera.getParameters();
            note("DEFAULT " + params.flatten());
            width = getIntent().getIntExtra("width", 640); height = getIntent().getIntExtra("height", 480);
            params.setPreviewSize(width, height); params.setPreviewFormat(ImageFormat.NV21);
            params.setPictureSize(getIntent().getIntExtra("pictureWidth", 2592), getIntent().getIntExtra("pictureHeight", 1944));
            params.set("zsl", getIntent().getStringExtra("zsl") == null ? "off" : getIntent().getStringExtra("zsl"));
            camera.setParameters(params);
            note("SELECTED " + camera.getParameters().flatten());
            camera.setPreviewDisplay(holder);
            camera.setPreviewCallback((data, c) -> {
                frames++;
                if (frames == 1 || frames == 10 || frames == 60 || frames % 300 == 0) {
                    int ymin=255,ymax=0,uvmin=255,uvmax=0; long sum=0;
                    for (int i=0;i<data.length;i++) { int v=data[i]&255; if(i<width*height){ymin=Math.min(ymin,v);ymax=Math.max(ymax,v);sum+=v;}else{uvmin=Math.min(uvmin,v);uvmax=Math.max(uvmax,v);} }
                    note("FRAME " + frames + " ms=" + (System.currentTimeMillis()-started) + " bytes=" + data.length + " Y="+ymin+".."+ymax+" avg="+(sum/(double)(width*height))+" UV="+uvmin+".."+uvmax);
                    if (frames <= 60) try (FileOutputStream out = openFileOutput("frame-"+frames+".nv21", MODE_PRIVATE)) { out.write(data); } catch(Exception e){note("SAVE_ERROR "+e);}
                }
            });
            started = System.currentTimeMillis(); camera.startPreview(); note("PREVIEW_STARTED " + width + "x" + height);
            handler.postDelayed(() -> note("CHECKPOINT 15s frames="+frames), 15000);
        } catch(Exception e) { note("OPEN_ERROR " + e); }
    }
    @Override public void surfaceChanged(SurfaceHolder h,int f,int w,int he) {}
    @Override public void surfaceDestroyed(SurfaceHolder holder) { release(); }
    void release(){ if(camera!=null){camera.setPreviewCallback(null);camera.release();camera=null;} }
    @Override protected void onDestroy(){handler.removeCallbacksAndMessages(null);release();super.onDestroy();}
}
