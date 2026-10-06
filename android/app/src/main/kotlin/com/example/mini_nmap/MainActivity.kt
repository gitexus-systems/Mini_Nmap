package com.example.mini_nmap

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "mini_nmap/multicast"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    acquireMulticastLock()
                    result.success(null)
                }
                "release" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun acquireMulticastLock() {
        val currentLock = multicastLock
        if (currentLock?.isHeld == true) return

        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock =
            wifiManager.createMulticastLock("mini_nmap_mdns").apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { lock ->
            if (lock.isHeld) lock.release()
        }
        multicastLock = null
    }

    override fun onStop() {
        releaseMulticastLock()
        super.onStop()
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }
}
