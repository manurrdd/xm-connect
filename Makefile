APP := .build/XM Connect.app
DMG := .build/XMConnect.dmg
IDENTITY := $(shell security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)

.PHONY: test icon app sign run install dmg notarize clean

test:
	swift test

icon:
	swift Tools/make-icon.swift

app:
	swift build -c release --product XMConnect
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp .build/release/XMConnect "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/"
	$(MAKE) sign

# Signed with a Developer ID when one is installed, so the build is distributable; ad hoc
# otherwise, which still runs locally.
sign:
	@if [ -n "$(IDENTITY)" ]; then \
		echo "signing as $(IDENTITY)"; \
		codesign --force --options runtime --timestamp --sign "$(IDENTITY)" "$(APP)"; \
	else \
		echo "no Developer ID found, signing ad hoc"; \
		codesign --force --sign - "$(APP)"; \
	fi

run: app
	open "$(APP)"

install: app
	rm -rf "/Applications/XM Connect.app"
	cp -R "$(APP)" "/Applications/XM Connect.app"
	open "/Applications/XM Connect.app"

dmg: app
	rm -rf .build/dmg "$(DMG)"
	mkdir -p .build/dmg
	cp -R "$(APP)" .build/dmg/
	ln -s /Applications .build/dmg/Applications
	hdiutil create -volname "XM Connect" -srcfolder .build/dmg -ov -format UDZO "$(DMG)"

# Needs a keychain profile once. Run "xcrun notarytool store-credentials" and answer its
# questions, naming the profile xm-connect.
notarize: dmg
	xcrun notarytool submit "$(DMG)" --keychain-profile xm-connect --wait
	xcrun stapler staple "$(DMG)"
	xcrun stapler staple "$(APP)"
	spctl -a -vv "$(APP)"

clean:
	rm -rf .build
