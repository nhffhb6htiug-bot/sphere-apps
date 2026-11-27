package com.syahifilms.sphere.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-bound AES-GCM session storage. No plaintext fallback; no session survives a lost key. */
internal class SessionVault(context:Context) {
    private val prefs=context.getSharedPreferences("sphere_secure_session_v1",Context.MODE_PRIVATE)
    private val alias="sphere.session.aes.v1"
    private val aad="sphere-preview-session-v1".toByteArray(Charsets.UTF_8)
    private fun store()=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
    private fun key(create:Boolean):SecretKey {
        (store().getKey(alias,null) as? SecretKey)?.let{return it}
        if(!create)error("Session key unavailable")
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").run{
            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
            generateKey()
        }
    }
    fun read():String? {
        val encoded=prefs.getString("ciphertext",null)?:return null
        return try{
            val parts=encoded.split(':')
            require(parts.size==2)
            val c=Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE,key(false),GCMParameterSpec(128,Base64.decode(parts[0],Base64.NO_WRAP)))
            c.updateAAD(aad)
            String(c.doFinal(Base64.decode(parts[1],Base64.NO_WRAP)),Charsets.UTF_8)
        }catch(_:Exception){clear();null}
    }
    fun write(value:String){
        val c=Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE,key(true))
        c.updateAAD(aad)
        val cipher=c.doFinal(value.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("ciphertext",Base64.encodeToString(c.iv,Base64.NO_WRAP)+":"+Base64.encodeToString(cipher,Base64.NO_WRAP)).commit())
    }
    fun clear(){
        // Delete both ciphertext and its key to prevent reuse after logout.
        runCatching{store().deleteEntry(alias)}
        prefs.edit().remove("ciphertext").commit()
    }
}
