# [1.3.0](https://github.com/lookmail88/melonthump/compare/v1.2.0...v1.3.0) (2026-10-21)


### Bug Fixes

* **ios:** decode recordings with AVAudioFile instead of a hand-rolled WAV parser ([e0fa59f](https://github.com/lookmail88/melonthump/commit/e0fa59f1df3c43dded59d529bf0e3a2b8f80a309))
* **ios:** pre-activate the audio session off the main thread ([df6044a](https://github.com/lookmail88/melonthump/commit/df6044a6f30b0956a754af39a638b61a91332865))
* **ios:** record with AVAudioEngine instead of AVAudioRecorder ([21d7396](https://github.com/lookmail88/melonthump/commit/21d739651b8e90174ccc146d7c3d238704c763fb))
* **ios:** ZoneBar marker follows the high-to-low frequency axis ([0d4fa53](https://github.com/lookmail88/melonthump/commit/0d4fa53d45f86380829ccb845a13cdf5c76c8822)), closes [hi#to-low](https://github.com/hi/issues/to-low)


### Features

* **ci:** stamp iOS version into server version policy on every build ([a979618](https://github.com/lookmail88/melonthump/commit/a979618930c6e414117648fcf1b357de8c3dcf64))
* **ios:** denoise tap analysis — high-pass, spectral subtraction, SNR gate ([32fd6b0](https://github.com/lookmail88/melonthump/commit/32fd6b05d60900339e1180b4ac8e74e53e45d8e9)), closes [hi#pass](https://github.com/hi/issues/pass) [hi#passes](https://github.com/hi/issues/passes)

# [1.2.0](https://github.com/lookmail88/melonthump/compare/v1.1.0...v1.2.0) (2026-10-21)


### Bug Fixes

* **ios:** accept WAVE_FORMAT_EXTENSIBLE WAV headers from AVAudioRecorder ([108318f](https://github.com/lookmail88/melonthump/commit/108318f126f37fa45410934ba804eed43d09a363))


### Features

* **ios:** on-device tap analysis and launch version gate with App Store redirect ([1e12e9d](https://github.com/lookmail88/melonthump/commit/1e12e9d035d688c549ddc151176dbb1586d3fe07))
* **ios:** pick Prod/Dev server from a list instead of editing a URL ([209b99c](https://github.com/lookmail88/melonthump/commit/209b99cd024fa9d19060b486e2eb20e8830a553d))
* **ios:** real-time mic waveform on the recording screen ([96fafad](https://github.com/lookmail88/melonthump/commit/96fafad2ae51a47c2c5d11da59fd4ba3b5d9a5ea))

# [1.1.0](https://github.com/lookmail88/melonthump/compare/v1.0.0...v1.1.0) (2026-10-21)


### Bug Fixes

* **ios:** default to prod server URL and show analyze errors as alert ([894a901](https://github.com/lookmail88/melonthump/commit/894a901e410d7e74962efb1a226dcde40507fdc3))


### Features

* **server:** add client version policy endpoint ([cfb5796](https://github.com/lookmail88/melonthump/commit/cfb5796277635b135d85dd145e98d6197523b828))

# 1.0.0 (2026-10-21)


### Bug Fixes

* **k8s:** store manifests as plain YAML instead of base64 ([09febb2](https://github.com/lookmail88/melonthump/commit/09febb28aa821fb9afd37843e3b168a8d15b14ef))


### Features

* initial scaffold — Spring Boot server + SwiftUI iOS app ([540de47](https://github.com/lookmail88/melonthump/commit/540de476e9f040a79a9b1d0f26e773d31db5b3f2))
* **ios:** Stephanie UI v4 + cartoon watermelon AppIcon; fix missing bundle ID in Info.plist ([c264d8b](https://github.com/lookmail88/melonthump/commit/c264d8b2bfdf52f7120ec2b0f35a0e81c028a6db))

# Changelog
