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

Podpis sa ukladá **mimo projektu** do `%USERPROFILE%\.menopocasie\android\`.
Stačí ho nastaviť **raz na každom PC** — potom funguje build z ľubovoľnej kópie priečinka.

**Prvé nastavenie na PC:**

```powershell
cd android
.\setup_signing.ps1
```

**Nový PC / záloha:**

```powershell
cd android
.\export_signing.ps1
# na novom PC:
.\import_signing.ps1 -SourceDir ".\signing-backup-YYYY-MM-DD"
```

Potom:

`flutter build appbundle --release`
