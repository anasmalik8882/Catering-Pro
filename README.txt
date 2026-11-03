Caterer Pro release signing patch (2026-11-02)
Replace only android/app/build.gradle.kts in your project with the file in this ZIP.
Place a copy of android/key.properties.example at android/key.properties and fill in passwords locally.
Android .gitignore already ignores key.properties and *.jks.
NOTE: first keystore certificate says C=92. Create a new key with C=PK before Play registration, retaining the original safely.
Validate from project/android: .\gradlew.bat :app:signingReport --no-daemon
Then build from root: flutter build appbundle --flavor production --release --dart-define=APP_ENV=production
IMPORTANT: applicationId is still com.example.catering_pro. Set a permanent ID and update Firebase config before first Google Play registration if renaming.
