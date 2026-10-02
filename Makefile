.PHONY: build app run test zip clean

build:
	swift build

app:
	./Scripts/build-app.sh

zip:
	./Scripts/build-app.sh --zip

run: app
	./Scripts/run-app.sh

test:
	swift test

clean:
	rm -rf .build build
