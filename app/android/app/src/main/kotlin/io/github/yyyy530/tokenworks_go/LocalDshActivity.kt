package io.github.yyyy530.tokenworks_go

import android.app.Activity
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream

/** The local engine's configuration UI, using the same login as the native workspace. */
class LocalDshActivity : Activity() {
    private var page: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val origin = intent.getStringExtra("origin")
        val cookie = intent.getStringExtra("cookie")
        if (origin == null || cookie == null) {
            finish()
            return
        }

        title = "本机 DSH"
        val view = WebView(this)
        page = view
        setContentView(view)
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
        }
        val base = android.net.Uri.parse(origin)
        view.webViewClient = object : WebViewClient() {
            private fun allows(request: WebResourceRequest): Boolean {
                val uri = request.url
                return uri.scheme == base.scheme && uri.host == base.host && uri.port == base.port
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                !allows(request)

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                if (allows(request)) null else WebResourceResponse(
                    "text/plain", "utf-8", 403, "Forbidden", emptyMap(), ByteArrayInputStream(byteArrayOf()),
                )
        }
        CookieManager.getInstance().setCookie(origin, "$cookie; Path=/; HttpOnly; SameSite=Strict") { saved ->
            if (page === view && !isFinishing) {
                if (saved) view.loadUrl(origin) else finish()
            }
        }
    }

    override fun onDestroy() {
        page?.let { view ->
            (view.parent as? android.view.ViewGroup)?.removeView(view)
            view.destroy()
        }
        page = null
        super.onDestroy()
    }
}
