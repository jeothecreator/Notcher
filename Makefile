.PHONY: build app run test zip dmg clean

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

test:
	swift test

clean:
	rm -rf .build build
