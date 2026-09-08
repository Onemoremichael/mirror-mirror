package dev.mirror.cameraprobe;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.hardware.Camera;
import android.media.MediaRecorder;
import android.media.CamcorderProfile;
import android.media.MediaCodec;
import android.media.MediaFormat;
import android.media.MediaCodecInfo;
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
    MediaRecorder recorder;
    SurfaceHolder previewHolder;
    SurfaceView surface;
    boolean resumed;
    TextView status;
    int frames, width, height;
    long started;
    final Handler handler = new Handler();
    String report = "";
    void note(String text) {
        if (android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) {
            runOnUiThread(() -> note(text)); return;
        }
        report += text + "\n";
        Log.i("MirrorCameraProbe", text);
        status.setText(text);
        try (FileOutputStream out = openFileOutput("report.txt", MODE_PRIVATE)) { out.write(report.getBytes("UTF-8")); } catch (Exception e) { Log.e("MirrorCameraProbe", "Report write", e); }
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        FrameLayout layout = new FrameLayout(this);
        surface = new SurfaceView(this);
        layout.addView(surface);
        status = new TextView(this); status.setTextColor(0xffffffff); status.setBackgroundColor(0xcc000000); status.setTextSize(16);
        layout.addView(status); setContentView(layout);
        if (getIntent().getBooleanExtra("codecBuffer", false)) {
            new Thread(() -> probeEncoderBuffers(), "MirrorCodecProbe").start(); return;
        }
        if (getIntent().getBooleanExtra("codec", false)) { probeEncoder(); return; }
        surface.getHolder().addCallback(this);
        note("Camera probe ready");
    }
    void probeEncoderBuffers() {
        MediaCodec codec = null;
        android.media.MediaMuxer muxer = null;
        boolean codecStarted = false, muxerStarted = false;
        int sent = 0, written = 0, track = -1;
        boolean inputEnded = false, outputEnded = false;
        long began = android.os.SystemClock.elapsedRealtime();
        try {
            deleteFile("codec-buffer.mp4");
            codec = MediaCodec.createByCodecName("OMX.google.h264.encoder");
            MediaFormat format = MediaFormat.createVideoFormat("video/avc", 1280, 720);
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar);
            format.setInteger(MediaFormat.KEY_BIT_RATE, 4000000);
            format.setInteger(MediaFormat.KEY_FRAME_RATE, 30);
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            codec.start(); codecStarted = true;
            muxer = new android.media.MediaMuxer(getFileStreamPath("codec-buffer.mp4").getAbsolutePath(),
                android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            byte[] pixels = new byte[1280 * 720 * 3 / 2];
            java.util.Arrays.fill(pixels, 1280 * 720, 1280 * 720 * 5 / 4, (byte)96);
            java.util.Arrays.fill(pixels, 1280 * 720 * 5 / 4, pixels.length, (byte)160);
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (!outputEnded && android.os.SystemClock.elapsedRealtime() - began < 30000) {
                if (!inputEnded) {
                    int slot = codec.dequeueInputBuffer(10000);
                    if (slot >= 0) {
                        if (sent == 30) {
                            codec.queueInputBuffer(slot, 0, 0, sent * 1000000L / 30, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEnded = true;
                        } else {
                            for (int i = 0; i < 1280 * 720; i++) pixels[i] = (byte)(16 + ((i % 1280 + sent * 8) % 200));
                            java.nio.ByteBuffer input = codec.getInputBuffer(slot); input.clear(); input.put(pixels);
                            codec.queueInputBuffer(slot, 0, pixels.length, sent * 1000000L / 30, 0); sent++;
                        }
                    }
                }
                int slot = codec.dequeueOutputBuffer(info, 10000);
                if (slot == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    track = muxer.addTrack(codec.getOutputFormat()); muxer.start(); muxerStarted = true;
                    note("BUFFER_CODEC_FORMAT " + codec.getOutputFormat());
                } else if (slot >= 0) {
                    if (info.size > 0 && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        if (!muxerStarted) throw new IllegalStateException("Output before format");
                        java.nio.ByteBuffer output = codec.getOutputBuffer(slot);
                        output.position(info.offset); output.limit(info.offset + info.size);
                        muxer.writeSampleData(track, output, info); written++;
                    }
                    outputEnded = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    codec.releaseOutputBuffer(slot, false);
                }
            }
            note("BUFFER_CODEC_RESULT sent=" + sent + " written=" + written + " eos=" + outputEnded
                + " elapsedMs=" + (android.os.SystemClock.elapsedRealtime() - began));
        } catch (Exception e) { note("BUFFER_CODEC_ERROR " + e); }
        finally {
            if (codec != null) {
                try { if (codecStarted) codec.stop(); } catch (Exception e) { note("BUFFER_CODEC_STOP_ERROR " + e); }
                codec.release();
            }
            if (muxer != null) {
                try { if (muxerStarted) muxer.stop(); } catch (Exception e) { note("BUFFER_MUX_STOP_ERROR " + e); }
                muxer.release();
            }
            note("BUFFER_CODEC_FILE bytes=" + getFileStreamPath("codec-buffer.mp4").length());
        }
    }
    void probeEncoder() {
        for (String name : new String[]{"OMX.qcom.video.encoder.avc", "OMX.google.h264.encoder"}) {
            MediaCodec codec = null;
            android.view.Surface input = null;
            try {
                codec = MediaCodec.createByCodecName(name);
                note("CODEC_CREATED " + name);
                MediaFormat format = MediaFormat.createVideoFormat("video/avc", 1280, 720);
                format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
                format.setInteger(MediaFormat.KEY_BIT_RATE, 4000000);
                format.setInteger(MediaFormat.KEY_FRAME_RATE, 30);
                format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
                input = codec.createInputSurface(); codec.start();
                note("CODEC_STARTED " + name); codec.stop();
            } catch (Exception e) { note("CODEC_ERROR " + name + " " + e); }
            finally { if (input != null) input.release(); if (codec != null) codec.release(); }
        }
    }
    @Override public void surfaceCreated(SurfaceHolder holder) {
        previewHolder = holder;
        if (!resumed || camera != null) return;
        try {
            frames = 0;
            for (int sample : new int[]{1, 10, 60}) deleteFile("frame-" + sample + ".raw");
            camera = Camera.open(0);
            camera.setErrorCallback((error, c) -> note("CAMERA_ERROR " + error + " frames=" + frames));
            Camera.Parameters params = camera.getParameters();
            note("DEFAULT " + params.flatten());
            width = getIntent().getIntExtra("width", 1280); height = getIntent().getIntExtra("height", 720);
            params.setPreviewSize(width, height);
            params.setPreviewFormat("yv12".equals(getIntent().getStringExtra("format")) ? ImageFormat.YV12 : ImageFormat.NV21);
            params.setPictureSize(getIntent().getIntExtra("pictureWidth", 1280), getIntent().getIntExtra("pictureHeight", 720));
            params.setRecordingHint(getIntent().getBooleanExtra("recording", getIntent().getBooleanExtra("video", false)));
            params.set("video-size", width + "x" + height);
            params.set("zsl", getIntent().getStringExtra("zsl") == null ? "off" : getIntent().getStringExtra("zsl"));
            if (getIntent().hasExtra("exposure")) {
                int exposure = getIntent().getIntExtra("exposure", 0);
                if (exposure < params.getMinExposureCompensation()
                        || exposure > params.getMaxExposureCompensation())
                    throw new IllegalArgumentException("Exposure outside advertised range");
                params.setExposureCompensation(exposure);
                note("EXPOSURE_REQUEST steps=" + exposure + " EV="
                        + exposure * params.getExposureCompensationStep());
            }
            if (getIntent().hasExtra("brightness")) {
                int brightness = getIntent().getIntExtra("brightness", 3);
                if (brightness < 0 || brightness > 6)
                    throw new IllegalArgumentException("Brightness outside 0..6");
                params.set("luma-adaptation", brightness);
                note("BRIGHTNESS_REQUEST " + brightness);
            }
            camera.setParameters(params);
            note("SELECTED " + camera.getParameters().flatten());
            int previewRotation = getIntent().getIntExtra("previewRotation", 270);
            int displayRotation = getWindowManager().getDefaultDisplay().getRotation();
            note("DISPLAY_ROTATION " + displayRotation);
            Camera.CameraInfo cameraInfo = new Camera.CameraInfo();
            Camera.getCameraInfo(0, cameraInfo);
            note("CAMERA_INFO facing=" + cameraInfo.facing + " orientation=" + cameraInfo.orientation);
            if (getIntent().getBooleanExtra("autoRotation", false)) {
                int degrees = displayRotation * 90;
                previewRotation = cameraInfo.facing == Camera.CameraInfo.CAMERA_FACING_FRONT
                    ? (360 - (cameraInfo.orientation + degrees) % 360) % 360
                    : (cameraInfo.orientation - degrees + 360) % 360;
                note("AUTO_PREVIEW_ROTATION " + previewRotation);
            }
            if (previewRotation != 0 && previewRotation != 90 && previewRotation != 180 && previewRotation != 270)
                throw new IllegalArgumentException("previewRotation must be a quarter turn");
            camera.setDisplayOrientation(previewRotation);
            note("PREVIEW_ROTATION " + previewRotation + " (display only; raw samples unchanged)");
            final double previewAspect = (previewRotation == 90 || previewRotation == 270)
                ? height / (double) width : width / (double) height;
            surface.post(() -> {
                android.view.View parent = (android.view.View) surface.getParent();
                int fitWidth = parent.getWidth(), fitHeight = (int) (fitWidth / previewAspect);
                if (fitHeight > parent.getHeight()) {
                    fitHeight = parent.getHeight(); fitWidth = (int) (fitHeight * previewAspect);
                }
                if (fitWidth > 0 && fitHeight > 0)
                    surface.setLayoutParams(new FrameLayout.LayoutParams(fitWidth, fitHeight, android.view.Gravity.CENTER));
            });
            camera.setPreviewDisplay(holder);
            camera.setPreviewCallback((data, c) -> {
                frames++;
                if (frames == 1 || frames == 10 || frames == 60 || frames % 300 == 0) {
                    int ymin=255,ymax=0,uvmin=255,uvmax=0; long sum=0;
                    for (int i=0;i<data.length;i++) { int v=data[i]&255; if(i<width*height){ymin=Math.min(ymin,v);ymax=Math.max(ymax,v);sum+=v;}else{uvmin=Math.min(uvmin,v);uvmax=Math.max(uvmax,v);} }
                    note("FRAME " + frames + " ms=" + (System.currentTimeMillis()-started) + " bytes=" + data.length + " Y="+ymin+".."+ymax+" avg="+(sum/(double)(width*height))+" UV="+uvmin+".."+uvmax);
                    if (frames <= 60) try (FileOutputStream out = openFileOutput("frame-"+frames+".raw", MODE_PRIVATE)) { out.write(data); } catch(Exception e){note("SAVE_ERROR "+e);}
                }
            });
            started = System.currentTimeMillis(); camera.startPreview(); note("PREVIEW_STARTED " + width + "x" + height);
            handler.postDelayed(() -> note("CHECKPOINT 15s frames="+frames), 15000);
            if (getIntent().getBooleanExtra("video", false)) handler.postDelayed(() -> {
                if (camera == null || frames < 5) { note("VIDEO_NOT_READY"); return; }
                try {
                    deleteFile("video.mp4");
                    camera.setPreviewCallback(null);
                    camera.unlock();
                    recorder = new MediaRecorder();
                    recorder.setCamera(camera);
                    recorder.setAudioSource(MediaRecorder.AudioSource.CAMCORDER);
                    recorder.setVideoSource(MediaRecorder.VideoSource.CAMERA);
                    recorder.setProfile(CamcorderProfile.get(0, CamcorderProfile.QUALITY_720P));
                    int videoBitrate = getIntent().getIntExtra("videoBitrate", 14000000);
                    if (videoBitrate < 100000 || videoBitrate > 20000000)
                        throw new IllegalArgumentException("videoBitrate out of diagnostic bounds");
                    recorder.setVideoEncodingBitRate(videoBitrate);
                    recorder.setOrientationHint(270);
                    note("VIDEO_CONFIG 1280x720 bitrate=" + videoBitrate + " orientation=270");
                    recorder.setOutputFile(getFileStreamPath("video.mp4").getAbsolutePath());
                    recorder.setPreviewDisplay(holder.getSurface());
                    recorder.prepare(); recorder.start(); note("VIDEO_STARTED");
                    handler.postDelayed(() -> { stopRecording(); release(); }, 10000);
                } catch (Exception e) { note("VIDEO_ERROR " + e); stopRecording(); release(); }
            }, 5000);
            if (getIntent().getBooleanExtra("photo", false)) {
                deleteFile("photo.jpg");
                handler.postDelayed(() -> {
                    if (camera == null) return;
                    try {
                        note("PHOTO_REQUEST frames=" + frames);
                        camera.takePicture(null, null, (data, c) -> {
                            try (FileOutputStream out = openFileOutput("photo.jpg", MODE_PRIVATE)) {
                                out.write(data);
                                note("PHOTO_SAVED bytes=" + data.length);
                            } catch (Exception e) { note("PHOTO_SAVE_ERROR " + e); }
                            try { c.startPreview(); note("PREVIEW_RESUMED"); }
                            catch (Exception e) { note("RESUME_ERROR " + e); }
                        });
                    } catch (Exception e) { note("PHOTO_ERROR " + e); }
                }, 20000);
            }
        } catch(Exception e) { note("OPEN_ERROR " + e); }
    }
    @Override public void surfaceChanged(SurfaceHolder h,int f,int w,int he) {}
    @Override public void surfaceDestroyed(SurfaceHolder holder) { previewHolder = null; release(); }
    @Override protected void onResume() {
        super.onResume(); resumed = true;
        if (previewHolder != null && previewHolder.getSurface().isValid()) surfaceCreated(previewHolder);
    }
    @Override protected void onPause() { resumed = false; release(); super.onPause(); }
    void release(){
        handler.removeCallbacksAndMessages(null);
        stopRecording();
        Camera closing = camera; camera = null;
        if (closing != null) {
            long releaseStarted = android.os.SystemClock.elapsedRealtime();
            note("CAMERA_RELEASE_BEGIN");
            closing.setPreviewCallback(null);
            try { closing.stopPreview(); } catch (RuntimeException e) { note("STOP_ERROR " + e); }
            note("PREVIEW_STOPPED ms=" + (android.os.SystemClock.elapsedRealtime() - releaseStarted));
            closing.release();
            note("CAMERA_RELEASE_DURATION ms=" + (android.os.SystemClock.elapsedRealtime() - releaseStarted));
            note("CAMERA_RELEASED");
        }
    }
    void stopRecording() {
        if (recorder == null) return;
        MediaRecorder closing = recorder; recorder = null;
        try { closing.stop(); note("VIDEO_FINALIZED_UNVERIFIED bytes=" + getFileStreamPath("video.mp4").length()); }
        catch (RuntimeException e) { note("VIDEO_STOP_ERROR " + e); }
        closing.release();
        if (camera != null) try { camera.reconnect(); }
        catch (Exception e) { note("RECONNECT_ERROR " + e); }
    }
    @Override protected void onDestroy(){handler.removeCallbacksAndMessages(null);release();super.onDestroy();}
}
