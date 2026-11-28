# Spindle — test-case results, build 104

Cases: 93 · passed 76 · failed 1 · untested 0 · manual pending 16

Gate: no failed case and no untested automatable case. Manual (M/D) cases are listed for the acceptance run.

**Failed:** TC-L10N-02

| Case | Priority | Method | Result | Evidence |
|---|---|---|---|---|
| TC-HOME-01 | P0 | A | ✅ passed | test_TC_HOME_01_TC_HOME_02_TC_HOME_03_TC_LIB_13_firstLaunchPlaysWithoutSetup |
| TC-HOME-02 | P0 | A | ✅ passed | test_TC_HOME_01_TC_HOME_02_TC_HOME_03_TC_LIB_13_firstLaunchPlaysWithoutSetup |
| TC-HOME-03 | P0 | A | ✅ passed | test_TC_HOME_01_TC_HOME_02_TC_HOME_03_TC_LIB_13_firstLaunchPlaysWithoutSetup |
| TC-HOME-04 | P2 | U | ✅ passed | test_TC_HOME_04_spindleThickness |
| TC-HOME-05 | P1 | A | ✅ passed | test_TC_HOME_05_emptyStateOffersBothSources |
| TC-HOME-06 | P1 | U | ✅ passed | test_TC_HOME_06_demoShelfGenerates |
| TC-SRC-01 | P0 | U | ✅ passed | test_TC_SRC_01_parsesRootListing |
| TC-SRC-02 | P1 | U | ✅ passed | test_TC_SRC_02_parsesSizesDatesAbsoluteHrefs |
| TC-SRC-03 | P1 | U | ✅ passed | test_TC_SRC_03_normalizesAddresses |
| TC-SRC-04 | P0 | D | 🖐 manual | — |
| TC-SRC-05 | P1 | U（401 映射）+ D | ✅ passed | test_TC_SRC_05_TC_ERR_01_mapsErrors |
| TC-SRC-06 | P0 | D | 🖐 manual | — |
| TC-SRC-07 | P1 | U | ✅ passed | test_TC_SRC_07_scansFolderRecursively |
| TC-SRC-08 | P0 | A | ✅ passed | test_TC_SRC_08_TC_SRC_09_TC_IAP_05_TC_IAP_07_freeLimits, test_TC_SRC_08_TC_IAP_01_secondSourceOpensPaywall |
| TC-SRC-09 | P1 | U | ✅ passed | test_TC_SRC_08_TC_SRC_09_TC_IAP_05_TC_IAP_07_freeLimits |
| TC-SRC-10 | P0 | U | ✅ passed | test_TC_SRC_10_passwordOnlyInKeychain |
| TC-SRC-11 | P1 | U | ✅ passed | test_TC_SRC_11_TC_LIFE_01_sourcesDoNotMix |
| TC-SRC-12 | P1 | D | 🖐 manual | — |
| TC-LIB-01 | P0 | U | ✅ passed | test_TC_LIB_01_infersFromPath |
| TC-LIB-02 | P1 | U | ✅ passed | test_TC_LIB_02_infersWithMissingLevels |
| TC-LIB-03 | P1 | U | ✅ passed | test_TC_LIB_03_mergesSameAlbumAcrossFolders |
| TC-LIB-04 | P1 | U | ✅ passed | test_TC_LIB_04_ordersAlbumsAndTracks |
| TC-LIB-05 | P1 | U | ✅ passed | test_TC_LIB_05_searchesAllFields |
| TC-LIB-06 | P1 | A | ✅ passed | test_TC_LIB_06_searchGroupsResults |
| TC-LIB-07 | P2 | U | ✅ passed | test_TC_LIB_07_recentlyAdded |
| TC-LIB-08 | P0 | U | ✅ passed | test_TC_LIB_08_savesAndLoadsAtomically |
| TC-LIB-09 | P0 | U | ✅ passed | test_TC_LIB_09_recoversFromDamagedFile |
| TC-LIB-10 | P1 | U | ✅ passed | test_TC_LIB_10_artworkStoredOncePerAlbum |
| TC-LIB-11 | P1 | U | ✅ passed | test_TC_LIB_11_playableFormats |
| TC-LIB-12 | P1 | U | ✅ passed | test_TC_LIB_12_tagsOverrideGuesses |
| TC-LIB-13 | P1 | A | ✅ passed | test_TC_HOME_01_TC_HOME_02_TC_HOME_03_TC_LIB_13_firstLaunchPlaysWithoutSetup |
| TC-LIB-14 | P2 | A | ✅ passed | test_TC_LIB_14_artistPage |
| TC-PLY-01 | P0 | U | ✅ passed | test_TC_PLY_01_queueNextPrevious |
| TC-PLY-02 | P1 | U | ✅ passed | test_TC_PLY_02_shuffleNoRepeats |
| TC-PLY-03 | P0 | D | 🖐 manual | — |
| TC-PLY-04 | P0 | U（中断处理逻辑）+ D | ✅ passed | test_TC_PLY_04_TC_PLY_05_sessionPolicy |
| TC-PLY-05 | P1 | U（路由变化逻辑）+ D | ✅ passed | test_TC_PLY_04_TC_PLY_05_sessionPolicy |
| TC-PLY-06 | P1 | U | ✅ passed | test_TC_PLY_06_stallWatchdog |
| TC-PLY-07 | P1 | U | ✅ passed | test_TC_PLY_07_skipsUnplayable |
| TC-PLY-08 | P2 | M | 🖐 manual | — |
| TC-PLY-09 | P2 | U | ✅ passed | test_TC_PLY_09_sleepTimer |
| TC-PLY-10 | P1 | A | ✅ passed | test_TC_PLY_10_sleepTimerIsPro |
| TC-PLY-11 | P2 | D | 🖐 manual | — |
| TC-PLY-12 | P1 | A（截屏）+ M | ✅ passed | test_TC_PLY_12_TC_SHR_03_nowPlayingAndShare |
| TC-PLY-13 | P2 | M | 🖐 manual | — |
| TC-PLY-14 | P1 | U | ✅ passed | test_TC_PLY_14_repeatModes |
| TC-OFF-01 | P1 | U（队列逻辑）+ A | ✅ passed | test_TC_OFF_01_downloadAlbum |
| TC-OFF-02 | P0 | U | ✅ passed | test_TC_OFF_02_TC_OFF_06_offlineFilesWinAndClear |
| TC-OFF-03 | P0 | D | 🖐 manual | — |
| TC-OFF-04 | P0 | U+A | ✅ passed | test_TC_OFF_04_TC_OFF_05_offlineLimitCountsFinishedOnly |
| TC-OFF-05 | P1 | U | ✅ passed | test_TC_OFF_04_TC_OFF_05_offlineLimitCountsFinishedOnly |
| TC-OFF-06 | P1 | U | ✅ passed | test_TC_OFF_02_TC_OFF_06_offlineFilesWinAndClear |
| TC-PL-01 | P1 | U+A | ✅ passed | test_TC_PL_01_TC_PL_03_TC_PL_04_playlists, test_TC_PL_01_addSongToPlaylist, test_TC_PL_01_TC_PL_02_playlistsAndLimit |
| TC-PL-02 | P0 | U+A | ✅ passed | test_TC_PL_01_TC_PL_02_playlistsAndLimit |
| TC-PL-03 | P1 | U | ✅ passed | test_TC_PL_01_TC_PL_03_TC_PL_04_playlists |
| TC-PL-04 | P1 | U | ✅ passed | test_TC_PL_01_TC_PL_03_TC_PL_04_playlists |
| TC-IAP-01 | P0 | U（原因→标题）+ A | ✅ passed | test_TC_IAP_01_paywallHeadlines, test_TC_SRC_08_TC_IAP_01_secondSourceOpensPaywall |
| TC-IAP-02 | P0 | M | 🖐 manual | — |
| TC-IAP-03 | P1 | M | 🖐 manual | — |
| TC-IAP-04 | P0 | U（静态检查脚本） | ✅ passed | tc_static.py |
| TC-IAP-05 | P0 | U | ✅ passed | test_TC_SRC_08_TC_SRC_09_TC_IAP_05_TC_IAP_07_freeLimits |
| TC-IAP-06 | P1 | M | 🖐 manual | — |
| TC-IAP-07 | P1 | U | ✅ passed | test_TC_SRC_08_TC_SRC_09_TC_IAP_05_TC_IAP_07_freeLimits |
| TC-IAP-08 | P0 | D | 🖐 manual | — |
| TC-RVW-01 | P0 | U | ✅ passed | test_TC_RVW_01_TC_RVW_02_TC_RVW_03_reviewTiming |
| TC-RVW-02 | P1 | U | ✅ passed | test_TC_RVW_01_TC_RVW_02_TC_RVW_03_reviewTiming |
| TC-RVW-03 | P0 | U | ✅ passed | test_TC_RVW_01_TC_RVW_02_TC_RVW_03_reviewTiming |
| TC-RVW-04 | P0 | U | ✅ passed | test_TC_RVW_04_loveItRequestsSystemReview |
| TC-RVW-05 | P1 | U | ✅ passed | test_TC_RVW_05_feedbackLinkHasNoServerDetails |
| TC-RVW-06 | P1 | A | ✅ passed | test_TC_SET_01_TC_SET_03_TC_RVW_06_settingsRows |
| TC-RVW-07 | P0 | U（静态检查脚本） | ✅ passed | tc_static.py |
| TC-SHR-01 | P0 | U（渲染尺寸）+ A | ✅ passed | test_TC_SHR_01_TC_SHR_02_shareCards, test_TC_SHR_01_shareShelfCard |
| TC-SHR-02 | P0 | U | ✅ passed | test_TC_SHR_01_TC_SHR_02_shareCards |
| TC-SHR-03 | P1 | A | ✅ passed | test_TC_PLY_12_TC_SHR_03_nowPlayingAndShare |
| TC-SHR-04 | P2 | M | 🖐 manual | — |
| TC-SET-01 | P0 | A | ✅ passed | test_TC_SET_01_TC_SET_03_TC_RVW_06_settingsRows |
| TC-SET-02 | P0 | A | ✅ passed | test_TC_SET_02_languageSwitchesInstantlyAndPersists |
| TC-SET-03 | P1 | A | ✅ passed | test_TC_SET_01_TC_SET_03_TC_RVW_06_settingsRows |
| TC-L10N-01 | P0 | U（CI） | ✅ passed | tc_static.py |
| TC-L10N-02 | P0 | A+M | ❌ failed | test_TC_L10N_02_tourGerman, test_TC_L10N_02_tourJapanese, test_TC_L10N_02_tourTraditionalChinese |
| TC-L10N-03 | P0 | U（CI） | ✅ passed | tc_static.py |
| TC-SYS-01 | P0 | U（脚本） | ✅ passed | tc_static.py |
| TC-SYS-02 | P0 | U（脚本） | ✅ passed | tc_static.py |
| TC-SYS-03 | P0 | U（脚本 grep URL 常量） | ✅ passed | tc_static.py |
| TC-ERR-01 | P1 | U | ✅ passed | test_TC_SRC_05_TC_ERR_01_mapsErrors |
| TC-LIFE-01 | P1 | U | ✅ passed | test_TC_SRC_11_TC_LIFE_01_sourcesDoNotMix |
| TC-LIFE-02 | P1 | U+A | ✅ passed | test_TC_LIFE_02_extremeNames |
| TC-STORE-01 | P1 | M | 🖐 manual | — |
| TC-UX-01 | P0 | A（截屏）+ M | ✅ passed | test_TC_UX_01_largestText |
| TC-UX-02 | P1 | A+M | ✅ passed | test_TC_UX_02_lightAndDark |
| TC-UX-03 | P1 | M | 🖐 manual | — |
| TC-UX-04 | P1 | M | 🖐 manual | — |
| TC-CRASH-01 | P0 | A | ✅ passed | test_TC_CRASH_01_rapidTaps |
