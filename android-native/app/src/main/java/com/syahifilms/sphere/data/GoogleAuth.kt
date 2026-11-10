package com.syahifilms.sphere.data

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import java.security.MessageDigest
import java.util.UUID

/**
 * Google Identity Services uses the Android account picker, NOT a WebView or
 * an embedded Google login page. The SHA-1 of the installed APK must be
 * registered as an Android OAuth client for this package in Google Cloud.
 */
object GoogleAuth {
    data class Token(val idToken: String, val rawNonce: String)

    /**
     * Obtain a Google ID token for Supabase. The token must be handed directly
     * to Supabase Auth with the original (unhashed) nonce; it is never logged.
     * Returns null if the user explicitly closes the Google account picker.
     */
    suspend fun getIdToken(context: Context): Token? {
        val rawNonce = UUID.randomUUID().toString()
        val hashedNonce = MessageDigest.getInstance("SHA-256")
            .digest(rawNonce.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        val option = GetSignInWithGoogleOption.Builder(Config.GOOGLE_WEB_CLIENT_ID)
            .setNonce(hashedNonce)
            .build()
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(option)
            .build()
        try {
            val credential = CredentialManager.create(context)
                .getCredential(context, request).credential
            if (credential is CustomCredential &&
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                val token = GoogleIdTokenCredential.createFrom(credential.data).idToken
                return Token(token, rawNonce)
            }
            throw ApiException(400, "Google account picker did not return an ID token")
        } catch (_: GetCredentialCancellationException) {
            return null
        } catch (e: GetCredentialException) {
            // Credential providers need the app's SHA-1 registered in Google Cloud.
            throw ApiException(400, "Google account picker unavailable: ${e.message ?: e.type}")
        }
    }

    /** Legacy Compose screens (the live APK currently uses the website-parity shell). */
    suspend fun signIn(context: Context): Boolean {
        val result = getIdToken(context) ?: return false
        Api.signInWithIdToken(result.idToken, result.rawNonce)
        return true
    }
}
