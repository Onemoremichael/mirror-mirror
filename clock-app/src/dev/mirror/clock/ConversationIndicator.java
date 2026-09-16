package dev.mirror.clock;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;

/** Small native conversation glyph; works independently of the old WebView. */
final class ConversationIndicator extends View {
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private final float dp;
    private String phase="off";
    private float level, displayed;
    private boolean motion=true;
    private long lastFrame;

    ConversationIndicator(Context context){
        super(context);dp=getResources().getDisplayMetrics().density;
        setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        setVisibility(GONE);
    }
    void update(String next,float amplitude){
        level=Math.max(0,Math.min(1,amplitude));
        if(!phase.equals(next)){
            phase=next;
            motion=Settings.Global.getFloat(getContext().getContentResolver(),Settings.Global.ANIMATOR_DURATION_SCALE,1f)>0;
            setContentDescription("standby".equals(phase)?"Local wake phrase listening; no cloud audio":
                "connecting".equals(phase)?"Connecting; wait for the chime":
                "muted".equals(phase)?"Conversation active, microphone muted":
                "speaking".equals(phase)?"Assistant speaking, microphone temporarily suppressed":
                "listening".equals(phase)?"Conversation active, microphone listening":"Microphone off");
            setVisibility("off".equals(phase)?GONE:VISIBLE);
        }
        if(!motion)displayed=.3f;
        invalidate();
    }
    @Override protected void onDraw(Canvas canvas){
        super.onDraw(canvas);if("off".equals(phase))return;
        long now=SystemClock.uptimeMillis();float dt=Math.min(100,Math.max(1,now-lastFrame));lastFrame=now;
        displayed+=(level-displayed)*Math.min(1,dt/110f);
        float cx=getWidth()/2f,cy=getHeight()/2f;
        if("standby".equals(phase)){
            // Quiet, text-free indication that local wake listening is armed.
            paint.setStyle(Paint.Style.FILL);paint.setColor(Color.rgb(176,228,219));paint.setAlpha(150);
            canvas.drawCircle(cx,cy,3*dp,paint);
            return;
        }
        boolean muted="muted".equals(phase),speaking="speaking".equals(phase);
        int color=muted?Color.rgb(231,185,121):speaking?Color.rgb(247,220,171):Color.rgb(176,228,219);
        // A restrained halo, not an opaque card. Black space remains reflective.
        paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp);
        paint.setColor(color);paint.setAlpha(muted?75:45);
        canvas.drawRoundRect(cx-49*dp,cy-23*dp,cx+49*dp,cy+23*dp,23*dp,23*dp,paint);
        paint.setStyle(Paint.Style.FILL);paint.setAlpha(255);
        if("connecting".equals(phase)){
            paint.setTextSize(12*dp);paint.setTypeface(android.graphics.Typeface.create("sans-serif-medium",0));
            paint.setTextAlign(Paint.Align.CENTER);
            canvas.drawText("Connecting",cx,cy+4*dp,paint);
            paint.setTextAlign(Paint.Align.LEFT);
        }else if(muted){
            // Static pause mark plus a short readable label; never looks like listening.
            canvas.drawRoundRect(cx-31*dp,cy-7*dp,cx-28*dp,cy+7*dp,1.5f*dp,1.5f*dp,paint);
            canvas.drawRoundRect(cx-24*dp,cy-7*dp,cx-21*dp,cy+7*dp,1.5f*dp,1.5f*dp,paint);
            paint.setTextSize(12*dp);paint.setTypeface(android.graphics.Typeface.create("sans-serif-medium",0));
            canvas.drawText("Muted",cx-12*dp,cy+4*dp,paint);
        }else{
            float time=motion?now/1000f:0;
            for(int i=0;i<5;i++){
                float shape=1-Math.abs(i-2)*.2f;
                float wave=motion?(float)(.5+.5*Math.sin(time*(speaking?4.3:2.2)-i*.65)):0.5f;
                float h=(5+shape*(3*wave+displayed*(14+10*wave)))*dp;
                float x=cx+(i-2)*12*dp;
                canvas.drawRoundRect(x-2.5f*dp,cy-h/2,x+2.5f*dp,cy+h/2,2.5f*dp,2.5f*dp,paint);
            }
        }
        if(motion&&!muted&&localAnimation()&&isShown())postInvalidateDelayed(33);
    }
    private boolean localAnimation(){return !"standby".equals(phase)&&!"connecting".equals(phase);}
}
