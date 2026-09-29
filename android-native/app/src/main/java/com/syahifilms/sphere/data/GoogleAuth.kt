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
 * "Continue with Google" inside the app (native Google account popup, no browser).
 * Shows all Google accounts on the phone every time.
 */
object GoogleAuth {
    /** Returns false if the user closed the popup. Throws ApiException with a readable message on errors. */
    suspend fun signIn(activityContext: Context): Boolean {
        val rawNonce = UUID.randomUUID().toString()
        val hashedNonce = MessageDigest.getInstance("SHA-256")
            .digest(rawNonce.toByteArray())
            .joinToString("") { "%02x".format(it) }
        val option = GetSignInWithGoogleOption.Builder(Config.GOOGLE_WEB_CLIENT_ID)
            .setNonce(hashedNonce)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        try {
            val result = CredentialManager.create(activityContext).getCredential(activityContext, request)
            val credential = result.credential
            if (credential is CustomCredential &&
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                val google = GoogleIdTokenCredential.createFrom(credential.data)
                Api.signInWithIdToken(google.idToken, rawNonce)
                return true
            }
            throw ApiException(400, "Google sign-in did not return an account")
        } catch (e: GetCredentialCancellationException) {
            return false
        } catch (e: GetCredentialException) {
            throw ApiException(400, "Google sign-in failed: ${e.message ?: e.type}")
        }
    }
}
