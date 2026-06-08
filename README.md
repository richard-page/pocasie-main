# flutter_application_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android release signing

Google Play requires a signed `app-release.aab`. Before running a release build:

1. Copy `android/key.properties.example` to `android/key.properties`.
2. Fill in your keystore values.
3. Place your keystore file in `android/` (or adjust `storeFile` path).

Then build with:

`flutter build appbundle --release`
