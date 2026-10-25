## [1.11.2](https://github.com/lookmail88/melonthump/compare/v1.11.1...v1.11.2) (2026-10-25)


### Bug Fixes

* **ios:** stats upload stays attested-only by design (unsigned posts are 401 by spec) ([e7b64e1](https://github.com/lookmail88/melonthump/commit/e7b64e1e1d0af81def82e03983ff667dc1796aa6))
* **server:** parse SEQUENCE-wrapped nonce in real Apple attestation certs ([d8a7328](https://github.com/lookmail88/melonthump/commit/d8a73285c787245253d6ef53628266dcb1573bbc))

## [1.11.1](https://github.com/lookmail88/melonthump/compare/v1.11.0...v1.11.1) (2026-10-25)


### Bug Fixes

* **ios:** stats upload no longer waits on attestation; log enrollment failures in Debug ([b376d89](https://github.com/lookmail88/melonthump/commit/b376d89fdf6e6e569b7669c6b4b5b474457426cb))
* **server:** log the attestation rejection reason at DEBUG ([bc30512](https://github.com/lookmail88/melonthump/commit/bc305123526d1e25cba6a779da680fb873f64bd2))

# [1.11.0](https://github.com/lookmail88/melonthump/compare/v1.10.0...v1.11.0) (2026-10-25)


### Bug Fixes

* **ios:** Xcode (Debug) builds bypass the version gate in test mode ([2e1a4eb](https://github.com/lookmail88/melonthump/commit/2e1a4ebf3db88a74e72cb10709e9990d8456fc54))


### Features

* **server:** log every request at DEBUG; log level DEBUG on dev, ERROR on prod ([45b594e](https://github.com/lookmail88/melonthump/commit/45b594e6268c92aa88048407d6051115da0ec3c5))

# [1.10.0](https://github.com/lookmail88/melonthump/compare/v1.9.1...v1.10.0) (2026-10-25)


### Features

* **ios:** send X-App-Version header and report version/channel in stats uploads ([d11ab7a](https://github.com/lookmail88/melonthump/commit/d11ab7a812895dd6f891a52f99160af9bc979f93))
* **server:** store client app version and channel with usage events ([3648798](https://github.com/lookmail88/melonthump/commit/3648798f8b741052091368049d0258d034661c19))

## [1.9.1](https://github.com/lookmail88/melonthump/compare/v1.9.0...v1.9.1) (2026-10-25)


### Bug Fixes

* **server:** release the OpenAPI branding (chore commits do not trigger semantic-release) ([b7a3cf9](https://github.com/lookmail88/melonthump/commit/b7a3cf9e3a3318bc59e8ee77f42ae3ebfbd5dd2d))
* **server:** ship the OpenAPI branding (chore type + path filter had kept it from releasing) ([a6ec865](https://github.com/lookmail88/melonthump/commit/a6ec865f82b39420c166334a0509288b9736fe1e))

# [1.9.0](https://github.com/lookmail88/melonthump/compare/v1.8.1...v1.9.0) (2026-10-24)


### Features

* **ios:** App Attest client, stats reporter, server-issued ad unit (1.1.0) ([d46e922](https://github.com/lookmail88/melonthump/commit/d46e9222902e47aacba121b3da2a4edfd2b359a9))
* **server:** App Attest gating, usage stats, attested ad config (1.1.0) ([a56b666](https://github.com/lookmail88/melonthump/commit/a56b66683ef0a0a25a64743781a7fd97a19cca2e))

## [1.8.1](https://github.com/lookmail88/melonthump/compare/v1.8.0...v1.8.1) (2026-10-23)


### Bug Fixes

* **ios:** result screen no longer shows placeholder threshold copy ([3f15ef7](https://github.com/lookmail88/melonthump/commit/3f15ef74a458f8f11e3297c25cb5fac1247691db))

# [1.8.0](https://github.com/lookmail88/melonthump/compare/v1.7.1...v1.8.0) (2026-10-23)


### Bug Fixes

* **ios:** fall back to test rewarded ad when configured unit fails to load ([1495531](https://github.com/lookmail88/melonthump/commit/1495531db40c2ce43dfdf8e8b151c3977ab03efa))


### Features

* **ios:** fallback ad unit now comes from DEFAULT_* build settings ([6109022](https://github.com/lookmail88/melonthump/commit/61090223f1d4b2f0ce4351f3f1658ad766f6f355))

## [1.7.1](https://github.com/lookmail88/melonthump/compare/v1.7.0...v1.7.1) (2026-10-23)


### Bug Fixes

* **ios:** promo unlock is session-scoped, not day-scoped ([3eeb917](https://github.com/lookmail88/melonthump/commit/3eeb917898dcd2f5e6ce06880e7062c3652fd38c))

# [1.7.0](https://github.com/lookmail88/melonthump/compare/v1.6.0...v1.7.0) (2026-10-23)


### Features

* **ios:** launch promo mode - one ad unlocks the rest of the day ([e5089bd](https://github.com/lookmail88/melonthump/commit/e5089bdbfe694e67290a71c4d22a1661d2d6d387))
* **server:** promoEndsAtEpochMillis in the client version policy ([5b423d5](https://github.com/lookmail88/melonthump/commit/5b423d5ed93129f1e3ad54e4d7e2d22e9a950223))

# [1.6.0](https://github.com/lookmail88/melonthump/compare/v1.5.0...v1.6.0) (2026-10-23)


### Bug Fixes

* **ios:** declare supported interface orientations (portrait on iPhone, all four on iPad) for App Store validation ([edce44e](https://github.com/lookmail88/melonthump/commit/edce44e0e92878a67de3ebdb04217a8bb47eb809))


### Features

* **ios:** AdMob rewarded ads with on-device credit wallet ([7347190](https://github.com/lookmail88/melonthump/commit/7347190053161176df96e94614a7d947d8023eb8))

# [1.5.0](https://github.com/lookmail88/melonthump/compare/v1.4.0...v1.5.0) (2026-10-22)


### Features

* **ios:** decode creditPerAd from the version policy ([22fe11e](https://github.com/lookmail88/melonthump/commit/22fe11e7918c0f857aa8ebd2811484f25f44f436))
* **server:** add creditPerAd to the client version policy ([2232a30](https://github.com/lookmail88/melonthump/commit/2232a30706f47a14a1902280a5e8b2f77a4df5ca))

# [1.4.0](https://github.com/lookmail88/melonthump/compare/v1.3.0...v1.4.0) (2026-10-22)


### Bug Fixes

* **ios:** create the audio tap block in a nonisolated context ([d63c597](https://github.com/lookmail88/melonthump/commit/d63c5972b05535446e493d186783477ef68ba82b))
* **ios:** hop to main actor with Task in the audio tap (assumeIsolated tripped dispatch_assert_queue_fail) ([206b614](https://github.com/lookmail88/melonthump/commit/206b6146bfc7102a6e99fdf1d9752f590407e2af))
* **ios:** keep the launch version-check timeout at 10s ([f84c0fe](https://github.com/lookmail88/melonthump/commit/f84c0fe06ee88d88155eeae2152d24e8e4964115))


### Features

* **ios:** 3-second launch splash with enlarged app icon ([f3c10ee](https://github.com/lookmail88/melonthump/commit/f3c10eeec26f19dc5e63515629d3f9510cfa2290))
* **ios:** 5-second recording countdown with auto-stop; stop unlocks after 1s ([88ddaa8](https://github.com/lookmail88/melonthump/commit/88ddaa8421ad9e391b9adf545f7c92d1f36c2d3d))
* **ios:** app name and powered-by line on the splash ([315e737](https://github.com/lookmail88/melonthump/commit/315e7379964eb5d24c3e280b9f22099f56ba4804))
* **ios:** conclude the version check inside the 3-second splash window ([1f054b9](https://github.com/lookmail88/melonthump/commit/1f054b93cab1d5e919183544372b2940ff94dbac))
* **ios:** heuristic-v2 thump gates — silence/noise now returns UNKNOWN ([d8b8083](https://github.com/lookmail88/melonthump/commit/d8b8083226be6fbd216f0353c6f130689ab29a6d))
* **ios:** heuristic-v2.2 — trim window, peak width, absolute floor, gate debug line ([3487528](https://github.com/lookmail88/melonthump/commit/3487528f0f10f5aa9ff9aec0b28bc5b360858848))
* **ios:** unlock Stop & Analyze after 3s instead of 1s ([24694c4](https://github.com/lookmail88/melonthump/commit/24694c4700d9e3a226e52ecc6a370fa031ea7a82))
* **ios:** version line on the splash, above the powered-by line ([da33bdb](https://github.com/lookmail88/melonthump/commit/da33bdb9bba3a081ec1dcba48b9ffdfe254c39bb))

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
