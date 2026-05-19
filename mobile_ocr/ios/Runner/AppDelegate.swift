import Flutter
import UIKit
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let beepChannel = FlutterMethodChannel(name: "com.example.mobile_ocr/beep",
                                              binaryMessenger: controller.binaryMessenger)
    beepChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "playBeep" || call.method == "playSuccess" {
        // System sound 1407 is the Apple Pay success chime (very loud and high-fidelity)
        AudioServicesPlaySystemSound(1407)
        result(nil)
      } else if call.method == "playError" {
        // System sound 1053 is a distinct warning/error sound on iOS
        AudioServicesPlaySystemSound(1053)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
