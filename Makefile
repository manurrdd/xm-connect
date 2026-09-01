APP := .build/XMConnect.app

.PHONY: test app run clean

test:
	swift test

app:
	swift build -c release --product XMConnect
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp .build/release/XMConnect "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	codesign --force --sign - "$(APP)"

run: app
	open "$(APP)"

clean:
	rm -rf .build
