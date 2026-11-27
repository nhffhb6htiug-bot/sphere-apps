package com.syahifilms.sphere.data

import android.content.Context
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.AbsoluteSizeSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.sin

data class EncodedPreview internal constructor(val media:LocalProjectMedia,val durationSeconds:Double)

@OptIn(UnstableApi::class)
object PreviewEncoder {
    private suspend fun duration(file:File):Long=withContext(Dispatchers.IO){
        val r=MediaMetadataRetriever()
        try{
            r.setDataSource(file.absolutePath)
            require(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO)=="yes"){"Select a video"}
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.takeIf{it>0}
                ?:error("Video duration unavailable")
        }finally{r.release()}
    }

    suspend fun encode(context:Context,input:LocalProjectMedia,minutes:Int,maxMb:Int,progress:(String)->Unit):EncodedPreview {
        require(minutes>0 && maxMb in 1..50)
        val limit=maxMb*1048576L
        require(input.mime.startsWith("video/") && input.size in 1L..limit){"Video exceeds file limit"}
        val ms=duration(input.file)
        require(ms<=minutes*60000L){"Preview exceeds $minutes minutes"}
        val out=File.createTempFile("sphere-preview-", ".mp4",context.cacheDir)
        out.delete()
        try {
            withContext(Dispatchers.Main.immediate){
                coroutineScope {
                    var transformer:Transformer?=null
                    val ticker=launch {
                        while(true){
                            delay(500)
                            val holder=ProgressHolder()
                            val t=transformer ?: continue
                            if(t.getProgress(holder)==Transformer.PROGRESS_STATE_AVAILABLE)
                                progress("Encoding SPHERE watermark… ${holder.progress}%")
                            else progress("Encoding SPHERE watermark…")
                        }
                    }
                    try {
                        suspendCancellableCoroutine<Unit>{cont->
                            val label=SpannableString("SPHERE").apply{
                                setSpan(ForegroundColorSpan(Color.WHITE),0,length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                                setSpan(AbsoluteSizeSpan(56),0,length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                                setSpan(StyleSpan(Typeface.BOLD),0,length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                            }
                            val mark=object:TextOverlay(){
                                override fun getText(presentationTimeUs:Long):SpannableString=label
                                override fun getOverlaySettings(presentationTimeUs:Long):OverlaySettings{
                                    val time=presentationTimeUs/1_000_000.0
                                    return OverlaySettings.Builder()
                                        .setAlphaScale(.72f)
                                        .setBackgroundFrameAnchor((.52*sin(time*.8)).toFloat(),(.50*sin(time*.61+1.0)).toFloat())
                                        .build()
                                }
                            }
                            val item=EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input.file)))
                                .setEffects(Effects(emptyList(),listOf(OverlayEffect(ImmutableList.of(mark)))))
                                .build()
                            val t=Transformer.Builder(context.applicationContext)
                                .setVideoMimeType(MimeTypes.VIDEO_H264)
                                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                                .addListener(object:Transformer.Listener{
                                    override fun onCompleted(composition:Composition,exportResult:ExportResult){if(cont.isActive)cont.resume(Unit)}
                                    override fun onError(composition:Composition,exportResult:ExportResult,exportException:ExportException){
                                        if(cont.isActive)cont.resumeWithException(exportException)
                                    }
                                }).build()
                            transformer=t
                            cont.invokeOnCancellation{
                                Handler(Looper.getMainLooper()).post{runCatching{t.cancel()};out.delete()}
                            }
                            try{t.start(item,out.absolutePath)}catch(e:Exception){if(cont.isActive)cont.resumeWithException(e)}
                        }
                    }finally{ticker.cancel()}
                }
            }
            require(out.length() in 1L..limit){"Encoded video exceeds $maxMb MB. Use a smaller video or pre-watermarked link."}
            val exportedMs=duration(out)
            require(kotlin.math.abs(exportedMs-ms)<=2000L && exportedMs<=minutes*60000L+1000){"Export duration mismatch"}
            return EncodedPreview(LocalProjectMedia(out,"SPHERE-preview.mp4","video/mp4",true),exportedMs/1000.0)
        }catch(e:Throwable){out.delete();throw e}
    }
}
