.PHONY: build app run test zip clean

build:
	swift build

app:
	./Scripts/build-app.sh

zip:
	./Scripts/build-app.sh --zip

run: app
	open build/Notcher.app

test:
	swift test

clean:
	rm -rf .build build
