.PHONY: build app run test zip dmg sandbox appstore appstore-shots clean

build:
	swift build

app:
	./Scripts/build-app.sh

zip:
	./Scripts/build-app.sh --zip

dmg: app
	./Scripts/make-dmg.sh

run: app
	./Scripts/run-app.sh

# Runs the app in the App Sandbox, the way the Mac App Store version runs.
# It gets its own bundle ID, so its data stays apart from your normal build's.
sandbox:
	NOTCHER_SANDBOX=1 NOTCHER_BUNDLE_ID=app.notcher.Notcher.sandbox ./Scripts/build-app.sh
	./Scripts/run-app.sh

# Signed installer package for App Store Connect (see AppStore/README.md).
appstore:
	./Scripts/build-appstore.sh

# App Store screenshots into AppStore/Screenshots.
appstore-shots: app
	build/Notcher.app/Contents/MacOS/Notcher --render-appstore AppStore/Screenshots

test:
	swift test

clean:
	rm -rf .build build
