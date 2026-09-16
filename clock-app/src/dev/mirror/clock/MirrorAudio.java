package dev.mirror.clock;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.media.audiofx.AcousticEchoCanceler;
import android.os.SystemClock;
import android.util.Log;
import java.io.*;
import java.net.*;
import java.util.concurrent.ArrayBlockingQueue;
import org.json.JSONObject;

/** Explicitly enabled, foreground-only USB audio. No WebView bridge or API key. */
final class MirrorAudio {
    private volatile boolean closed, capturing, muted;
    private volatile Socket socket;
    private DataOutputStream output;
    private AudioRecord recorder;
    private AudioTrack player;
    private AcousticEchoCanceler echo;
    private Thread captureThread, playThread;
    private final ArrayBlockingQueue<byte[]> playback = new ArrayBlockingQueue<>(50);
    private volatile long speakerUntil;
    private long inputFrames, outputFrames;
    private int peak;
    private double rms;
    private volatile float outputLevel;
    interface Indicator {void accept(String phase,float level);}
    private final Indicator indicator;

    MirrorAudio(Indicator indicator) {
        this.indicator=indicator;
        new Thread(this::connectLoop,"mirror-audio-link").start();
    }
    private void connectLoop() {
        while(!closed) {
            try {
                Socket s=new Socket();socket=s;
                s.connect(new InetSocketAddress("127.0.0.1",8782),3000);
                s.setTcpNoDelay(true);s.setSoTimeout(5000);
                output=new DataOutputStream(s.getOutputStream());
                DataInputStream in=new DataInputStream(s.getInputStream());
                send(1,new JSONObject().put("version",1).put("rate",16000).toString().getBytes("UTF-8"));
                Thread heartbeat=new Thread(()->{
                    while(!closed&&socket==s&&!s.isClosed()) {
                        try {send(4,new byte[0]);Thread.sleep(1000);}catch(Exception e){try{s.close();}catch(Exception ignored){}break;}
                    }
                },"mirror-audio-heartbeat");heartbeat.start();
                while(!closed) {
                    int type=in.readUnsignedByte(),size=in.readInt();
                    if(size<0||size>65536)throw new IOException("Invalid audio frame");
                    byte[] data=new byte[size];in.readFully(data);
                    if(type==10)startAudio();
                    else if(type==11)stopAudio();
                    else if(type==12){muted=size==1&&data[0]!=0;indicator.accept(muted?"muted":"listening",0);}
                    else if(type==13&&capturing){
                        if(size%2!=0)throw new IOException("Invalid PCM");
                        // Split provider chunks into bounded 20ms playback blocks.
                        for(int i=0;i<size;i+=640){byte[] part=java.util.Arrays.copyOfRange(data,i,Math.min(i+640,size));if(!playback.offer(part))throw new IOException("Audio backlog");}
                    }
                }
            } catch(Exception e) {if(!closed)Log.w("MirrorAudio","Audio link stopped: "+e.getClass().getSimpleName());}
            finally {stopAudio();Socket s=socket;socket=null;try{if(s!=null)s.close();}catch(Exception ignored){} }
            if(!closed)try{Thread.sleep(2000);}catch(InterruptedException ignored){}
        }
    }
    private synchronized void send(int type,byte[] data)throws IOException {
        if(output==null)throw new IOException("No link");
        output.writeByte(type);output.writeInt(data.length);output.write(data);output.flush();
    }
    private void startAudio() throws Exception {
        if(capturing)return;
        int minimum=AudioRecord.getMinBufferSize(16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT);
        recorder=new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION,16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT,Math.max(minimum,6400));
        if(recorder.getState()!=AudioRecord.STATE_INITIALIZED)throw new IOException("Microphone unavailable");
        if(AcousticEchoCanceler.isAvailable()){echo=AcousticEchoCanceler.create(recorder.getAudioSessionId());if(echo!=null)echo.setEnabled(true);}
        player=new AudioTrack(AudioManager.STREAM_MUSIC,16000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT,Math.max(1280,AudioTrack.getMinBufferSize(16000,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT)),AudioTrack.MODE_STREAM);
        if(player.getState()!=AudioTrack.STATE_INITIALIZED)throw new IOException("Speakers unavailable");
        muted=false;speakerUntil=0;inputFrames=outputFrames=0;capturing=true;
        recorder.startRecording();player.play();indicator.accept("listening",0);
        captureThread=new Thread(()->{
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);
            byte[] frame=new byte[640];int filled=0;
            try {
                while(capturing){
                    int n=recorder.read(frame,filled,frame.length-filled);if(n<=0)throw new IOException("Microphone read failed");filled+=n;if(filled<frame.length)continue;filled=0;
                    double energy=0;peak=0;for(int i=0;i<frame.length;i+=2){int v=(short)((frame[i]&255)|(frame[i+1]<<8));energy+=(double)v*v;peak=Math.max(peak,Math.abs(v));}rms=Math.sqrt(energy/320);
                    boolean quiet=muted||SystemClock.elapsedRealtime()<speakerUntil;
                    send(2,quiet?new byte[640]:frame);inputFrames++;
                    if(inputFrames%5==0){boolean speaking=SystemClock.elapsedRealtime()<speakerUntil;indicator.accept(muted?"muted":speaking?"speaking":"listening",muted?0:speaking?outputLevel:(float)Math.min(1,Math.max(0,(rms-60)/1800)));}
                    if(inputFrames%50==0)send(3,new JSONObject().put("capturing",true).put("playing",SystemClock.elapsedRealtime()<speakerUntil).put("rms",rms).put("peak",peak).put("inputFrames",inputFrames).put("outputFrames",outputFrames).toString().getBytes("UTF-8"));
                }
            }catch(Exception e){if(capturing)fail();}
        },"mirror-microphone");
        playThread=new Thread(()->{
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO);
            try {while(capturing){byte[] frame=playback.poll(100,java.util.concurrent.TimeUnit.MILLISECONDS);if(frame==null)continue;
                // Live also streams silence. Only audible PCM gates the microphone.
                int level=0;for(int i=0;i+1<frame.length;i+=2)level=Math.max(level,Math.abs((short)((frame[i]&255)|(frame[i+1]<<8))));
                if(level>180)speakerUntil=SystemClock.elapsedRealtime()+350;
                outputLevel=Math.min(1,level/12000f);
                int offset=0;while(offset<frame.length&&capturing){int n=player.write(frame,offset,frame.length-offset);if(n<=0)throw new IOException("Playback failed");offset+=n;}outputFrames++;}}
            catch(Exception e){if(capturing)fail();}
        },"mirror-speakers");
        captureThread.start();playThread.start();
    }
    private void fail(){try{Socket s=socket;if(s!=null)s.close();}catch(Exception ignored){} }
    private void stopAudio(){
        capturing=false;indicator.accept("off",0);
        try{if(recorder!=null)recorder.stop();}catch(Exception ignored){}
        try{if(player!=null){player.pause();player.flush();}}catch(Exception ignored){}
        try{if(captureThread!=null)captureThread.join(1000);if(playThread!=null)playThread.join(1000);}catch(InterruptedException ignored){}
        if(echo!=null){echo.release();echo=null;}
        if(recorder!=null){recorder.release();recorder=null;}
        if(player!=null){player.release();player=null;}
        playback.clear();
        try{send(3,new JSONObject().put("capturing",false).put("inputFrames",inputFrames).put("outputFrames",outputFrames).toString().getBytes("UTF-8"));}catch(Exception ignored){}
    }
    void close(){closed=true;fail();}
}
