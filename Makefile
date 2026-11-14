all:
	/usr/bin/xcodebuild -project ClassicFullscreen.xcodeproj -target ClassicFullscreen -configuration Release build
clean:
	/usr/bin/xcodebuild -project ClassicFullscreen.xcodeproj -target ClassicFullscreen -configuration Release clean
