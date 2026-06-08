package sk.menopocasie.app

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var originalStatusBarColor: Int = Color.TRANSPARENT
    private var originalNavBarColor: Int = Color.TRANSPARENT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Edge-to-edge bez enableEdgeToEdge() — to je len pre ComponentActivity, nie FlutterActivity.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // Priesvitné system lišty (inak OS pridá svetlý „scrim" pod 3-tlačidlovú navigáciu).
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        originalStatusBarColor = Color.TRANSPARENT
        originalNavBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
    }

    override fun onPause() {
        super.onPause()
        // Pri pozastavení (app switcher) nastaviť pevnú farbu namiesto transparent
        // aby sa zabránilo grafickým artefaktom (mriežkam) v náhľade
        window.statusBarColor = Color.parseColor("#FF2D3A4A")
        window.navigationBarColor = Color.parseColor("#FF2D3A4A")
    }

    override fun onResume() {
        super.onResume()
        // Pri obnovení vrátiť priehľadné lišty
        window.statusBarColor = originalStatusBarColor
        window.navigationBarColor = originalNavBarColor
    }
}
