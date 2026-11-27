package com.syahifilms.sphere.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

data class PortfolioItem(val id:String,val title:String,val category:String,val imagePath:String,val video:String) {
    companion object { fun from(o:JSONObject) = PortfolioItem(o.str("id"),o.str("title"),o.str("category"),o.str("image_path"),o.str("video_url")) }
    val displayCategory: String get() = category.takeIf { it in Config.CATEGORIES } ?: "Other"
}
object NativePortfolio {
    const val MAX_ITEMS = 12
    fun validLink(s:String):Boolean = s.isBlank() || runCatching {
        val u = Uri.parse(s.trim())
        u.scheme == "https" && !u.host.isNullOrBlank() && u.userInfo == null
    }.getOrDefault(false)
    fun youtubeId(s:String):String? {
        if (!validLink(s) || s.isBlank()) return null
        val u = Uri.parse(s)
        val id = when (u.host?.lowercase()) {
            "youtu.be" -> u.pathSegments.firstOrNull()
            "youtube.com","www.youtube.com","m.youtube.com" -> if (u.path == "/watch") u.getQueryParameter("v")
                else if (u.pathSegments.firstOrNull() in listOf("shorts","embed")) u.pathSegments.getOrNull(1) else null
            else -> null
        }
        return id?.takeIf { Regex("^[A-Za-z0-9_-]{11}$").matches(it) }
    }
    fun thumbnail(s:String) = youtubeId(s)?.let { "https://img.youtube.com/vi/$it/hqdefault.jpg" }.orEmpty()
    fun completion(p:Profile,items:List<PortfolioItem>):String {
        val bio=p.bio.isNotBlank()
        val skills=p.skills.any { it.isNotBlank() }
        val portfolio=p.portfolio.isNotBlank() || p.sample.isNotBlank() || items.any { it.video.isNotBlank() }
        return if (bio && skills && portfolio) "Complete" else if (bio || skills || portfolio) "Partial" else "Incomplete"
    }
    suspend fun items(id:String):List<PortfolioItem> {
        require(NativeChat.validId(id))
        return Api.select("sp_portfolio?editor_id=eq.$id&order=created_at.desc&select=id,title,category,image_path,video_url").mapObjects { PortfolioItem.from(it) }
    }
    private suspend fun image(ctx:Context,uri:Uri,maxDim:Int):ByteArray = withContext(Dispatchers.IO) {
        // Bound actual input size and decode dimensions before allocating bitmap.
        val tmp = File.createTempFile("profile-image-", ".tmp",ctx.cacheDir)
        try {
            require(ctx.contentResolver.getType(uri)?.startsWith("image/") == true) { "Select a photo" }
            ctx.contentResolver.openInputStream(uri)?.use { src ->
                tmp.outputStream().use { out ->
                    val buf=ByteArray(65536); var n=0L
                    while(true) { val count=src.read(buf); if(count<0) break; n+=count; require(n<=25L*1024*1024) { "Photo exceeds 25 MB" }; out.write(buf,0,count) }
                }
            } ?: error("Cannot read photo")
            val bounds=BitmapFactory.Options().apply { inJustDecodeBounds=true }
            BitmapFactory.decodeFile(tmp.absolutePath,bounds)
            require(bounds.outWidth>0 && bounds.outHeight>0) { "Unsupported image" }
            var sample=1
            while(maxOf(bounds.outWidth,bounds.outHeight)/sample > maxDim*2) sample*=2
            val original=BitmapFactory.decodeFile(tmp.absolutePath,BitmapFactory.Options().apply { inSampleSize=sample }) ?: error("Cannot decode photo")
            val scale=minOf(1.0,maxDim.toDouble()/maxOf(original.width,original.height))
            val resized=if(scale<1) Bitmap.createScaledBitmap(original,maxOf(1,(original.width*scale).toInt()),maxOf(1,(original.height*scale).toInt()),true) else original
            try {
                val out=ByteArrayOutputStream()
                check(resized.compress(Bitmap.CompressFormat.JPEG,85,out))
                require(out.size() in 1..(10*1024*1024)) { "Compressed photo too large" }
                out.toByteArray()
            } finally { if(resized!==original) resized.recycle(); original.recycle() }
        } finally { tmp.delete() }
    }
    private suspend fun upload(ctx:Context,uri:Uri,owner:String,folder:String,size:Int):String {
        val bytes=image(ctx,uri,size)
        require(Api.userId==owner)
        val path="$owner/$folder/${UUID.randomUUID()}.jpg"
        Api.uploadBytes("sphere-media",path,bytes,"image/jpeg")
        return path
    }
    suspend fun avatar(ctx:Context,uri:Uri) {
        val owner=Api.userId ?: error("Please log in")
        val path=upload(ctx,uri,owner,"avatar",400)
        require(Api.userId==owner)
        // Do not delete on an ambiguous write: the profile may already reference the object.
        val updated=Api.updateReturning("profiles?id=eq.$owner",JSONObject().put("avatar_url",path))
        require(updated?.str("avatar_url")==path) { "Photo update not confirmed" }
    }
    suspend fun add(ctx:Context,title:String,category:String,uri:Uri?,video:String) {
        val owner=Api.userId ?: error("Please log in")
        require(Repo.loadMe()?.role in setOf("editor","admin"))
        require(title.trim().length in 1..80 && category in Config.CATEGORIES)
        require(validLink(video) && (uri!=null || youtubeId(video)!=null)) { "Choose a photo or a YouTube video link" }
        require(items(owner).size<MAX_ITEMS) { "Maximum 12 portfolio items" }
        val id=UUID.randomUUID().toString()
        val path=uri?.let { upload(ctx,it,owner,"portfolio",1280) }
        require(Api.userId==owner)
        val row=JSONObject().put("id",id).put("editor_id",owner).put("title",title.trim()).put("category",category)
            .put("image_path",path ?: JSONObject.NULL).put("video_url",video.ifBlank { null } ?: JSONObject.NULL)
        val saved=Api.insert("sp_portfolio",row)
        require(saved?.str("id")==id) { "Upload not confirmed. Refresh portfolio before retrying." }
    }
    suspend fun remove(id:String) {
        val owner=Api.userId ?: error("Please log in")
        require(NativeChat.validId(id))
        Api.delete("sp_portfolio?id=eq.$id&editor_id=eq.$owner")
        require(items(owner).none { it.id==id }) { "Removal not confirmed" }
        // Public object cleanup is deferred until references are checked server-side.
    }
    suspend fun reapply() {
        val p=Repo.loadMe() ?: error("Please log in")
        require(p.id==Api.userId && p.role=="editor" && !p.verified && p.verificationStatus=="rejected")
        require(p.categories.isNotEmpty() && p.languages.isNotEmpty() && p.device in setOf("mobile","pc","both")) { "Complete editor details first" }
        val result=Api.updateReturning("profiles?id=eq.${p.id}&verification_status=eq.rejected",JSONObject().put("verification_status","pending"))
        require(result?.str("verification_status")=="pending") { "Application not confirmed" }
    }
}
