package io.github.mohammedanasasif.bookit

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Lets automated tests open a demo screen:
    //   adb shell am start -n io.github.mohammedanasasif.bookit/.MainActivity --es bookit_args "--demo=home"
    override fun getDartEntrypointArgs(): List<String>? {
        val extra = intent?.getStringExtra("bookit_args") ?: return super.getDartEntrypointArgs()
        return extra.split(' ').filter { it.isNotBlank() }
    }
}
