package sk.menopocasie.app

import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var originalStatusBarColor: Int = Color.TRANSPARENT
    private var originalNavBarColor: Int = Color.TRANSPARENT

    /** Rovnaká farba ako Flutter kAmbientBlendColor — len keď appka nie je viditeľná. */
    private val recentsBarColor: Int = Color.parseColor("#FF172438")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sk.menopocasie.app/install",
        ).setMethodCallHandler { call, result ->
            if (call.method == "firstInstallTimeMs") {
                try {
                    val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        packageManager.getPackageInfo(
                            packageName,
                            PackageManager.PackageInfoFlags.of(0),
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getPackageInfo(packageName, 0)
                    }
                    result.success(info.firstInstallTime)
                } catch (e: Exception) {
                    result.error("install_time", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge-to-edge bez enableEdgeToEdge() — to je len pre ComponentActivity, nie FlutterActivity.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        applyTransparentSystemBars()
        originalStatusBarColor = Color.TRANSPARENT
        originalNavBarColor = Color.TRANSPARENT
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
    }

    override fun onStart() {
        super.onStart()
        // Späť na obrazovku — priehľadné lišty (aj po systémovom dialógu oprávnení).
        applyTransparentSystemBars()
    }

    override fun onResume() {
        super.onResume()
        applyTransparentSystemBars()
    }

    override fun onStop() {
        super.onStop()
        // Len keď appka nie je viditeľná (recents / iná appka).
        // onPause NIE — systémový dialóg upozornení/polohy pause-uje Activity a inak
        // by navigation bar zčernal pri „Povoliť upozornenia“.
        window.statusBarColor = recentsBarColor
        window.navigationBarColor = recentsBarColor
    }

    private fun applyTransparentSystemBars() {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }
}
