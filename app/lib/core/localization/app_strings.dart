class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  bool get isVi => languageCode == 'vi';

  String get appTitle => isVi ? 'Di sản âm nhạc Huế' : 'Hue Heritage Music';
  String get appSubtitle => isVi
      ? 'Nền tảng AI bảo tồn, truyền dạy và phát huy ca Huế, nhã nhạc cung đình và nhạc cụ truyền thống.'
      : 'AI platform for preserving, teaching, and advancing Ca Hue, Court Music, and traditional instruments.';

  String get featuresHeader => isVi ? 'Chức năng' : 'Features';
  String get settingsTitle => isVi ? 'Cài đặt' : 'Settings';
  String get projectInfoTitle => isVi ? 'Thông tin dự án' : 'Project Info';
  String get taskHistoryTitle => isVi ? 'Lịch sử tác vụ' : 'Task History';

  String get navHome => isVi ? 'Trang chủ' : 'Home';
  String get navHeritage => isVi ? 'Kho di sản' : 'Heritage Archive';
  String get navLearning => isVi ? 'Học hát Ca Huế' : 'Singing Practice';
  String get navAnalysis => isVi ? 'Phân tích F0' : 'Pitch Analysis';
  String get navTranscription => isVi ? 'Audio -> Bản nhạc' : 'Audio to Sheet';
  String get navCreation => isVi ? 'Sáng tạo cùng Ca Huế' : 'Hue Heritage Studio';
  String get navCover => isVi ? 'Cover' : 'Cover Song';
  String get navRestoration => isVi ? 'Phục dựng' : 'Restoration';
  String get navInstruments => isVi ? 'Nhạc cụ' : 'Instruments';
  String get navMore => isVi ? 'Danh mục' : 'More';
  String get authTitle => isVi ? 'Tài khoản' : 'Account';

  String get featHeritageTitle => isVi ? 'Kho di sản số' : 'Heritage Archive';
  String get featHeritageDesc => isVi
      ? 'Lưu trữ, tra cứu và thưởng thức các bản ghi âm cổ truyền nguyên bản (Chỉ nghe nhạc)'
      : 'Browse, search, and listen to authentic historical heritage recordings';

  String get featLearningTitle => isVi ? 'Học hát Ca Huế' : 'Singing Practice';
  String get featLearningDesc => isVi
      ? 'Thu âm giọng hát, so sánh cao độ với bản mẫu của nghệ nhân'
      : 'Record voice, compare pitch contours against master artisans';

  String get featAnalysisTitle => isVi ? 'Phân tích bản thu' : 'Pitch Analysis';
  String get featAnalysisDesc => isVi
      ? 'Phân tích đường cao độ F0 của một bản thu bất kỳ'
      : 'Analyze F0 fundamental frequency curve of any recording';
  String get analysisNoServer => isVi
      ? 'Chưa cấu hình máy chủ. Vào Cài đặt để nhập địa chỉ.'
      : 'Server not configured. Go to Settings to enter the address.';
  String get analysisPickHint => isVi
      ? 'Chọn bản thu để phân tích cao độ F0 và nhận diện nhạc cụ.'
      : 'Pick a recording to analyze its F0 pitch and detect instruments.';
  String get analysisPickBtn => isVi ? 'Chọn tệp âm thanh' : 'Choose audio file';
  String analysisFileLabel(String name) => isVi ? 'Tệp: $name' : 'File: $name';
  String get analysisF0Title => isVi ? 'Đường cao độ F0' : 'F0 Pitch Curve';
  String analysisMeanF0(String hz) => isVi ? 'F0 trung bình: $hz Hz' : 'Mean F0: $hz Hz';
  String get analysisInstrumentsTitle => isVi ? 'Nhạc cụ nhận diện được' : 'Detected Instruments';
  String get analysisNoInstruments => isVi ? 'Không nhận diện được nhạc cụ nào.' : 'No instruments detected.';
  String get analysisInstrumentsFail => isVi
      ? 'Không nhận diện được nhạc cụ (máy chủ gặp sự cố với bản thu này).'
      : 'Instrument detection failed (the server had trouble with this recording).';

  String get featTranscriptionTitle => isVi ? 'Audio -> Bản nhạc' : 'Audio to Sheet';
  String get featTranscriptionDesc => isVi
      ? 'Chuyển bản thu âm thành file MIDI và bản nhạc MusicXML'
      : 'Transcribe audio recordings into MIDI and MusicXML sheet music';

  String get featCreationTitle => isVi ? 'Sáng tạo cùng Ca Huế' : 'Hue Heritage Studio';
  String get featCreationDesc => isVi
      ? 'Hát nguyên bản di sản hoặc sáng tạo lời thơ mới trên lòng bản cố định'
      : 'Recreate original heritage pieces or sing new verses over classical melodies';


  String get featRestorationTitle => isVi ? 'Phục dựng (Beta)' : 'Restoration (Beta)';
  String get featRestorationDesc => isVi
      ? 'Đối chiếu bản ghi tìm tên bài & Khôi phục chất lượng âm thanh'
      : 'Cross-match recordings to find titles & restore audio quality';


  String get featHistoryTitle => isVi ? 'Lịch sử' : 'History';
  String get featHistoryDesc => isVi
      ? 'Xem lại các tác vụ đã thực hiện và trạng thái của chúng'
      : 'Review executed tasks, processing status, and results';


  String get searchHint => isVi
      ? 'Tìm theo tên, nghệ nhân, nhạc cụ, thời gian, địa điểm...'
      : 'Search by title, artisan, instrument, period, location...';
  String get searchBtn => isVi ? 'Tìm' : 'Search';
  String get noRecordings => isVi ? 'Chưa có bản ghi' : 'No recordings found';
  String get originalAudio => isVi ? 'Bản gốc' : 'Original';
  String get restoredAudio => isVi ? 'Bản phục chế' : 'Restored';
  String get restoreActionBtn => isVi ? 'Phục dựng' : 'Restore';
  String get closeBtn => isVi ? 'Đóng' : 'Close';
  String get practiceNoLessons => isVi ? 'Chưa có bài học nào. Hãy nạp dữ liệu di sản trên máy chủ (bài có file âm thanh sẽ thành bài học).' : 'No lessons yet. Load heritage data on the server (any item with audio becomes a lesson).';
  String get practicePickLesson => isVi ? 'Chọn bài học' : 'Choose lesson';
  String get practiceListenLoop => isVi ? 'Nghe mẫu (lặp)' : 'Listen (loop)';
  String get practiceStopSample => isVi ? 'Dừng mẫu' : 'Stop sample';
  String get practiceRecord => isVi ? 'Thu câu này' : 'Record this phrase';
  String get practiceStopRecord => isVi ? 'Dừng thu' : 'Stop recording';
  String get practiceGrade => isVi ? 'Chấm điểm' : 'Grade';
  String get practiceRecorded => isVi ? 'Đã thu xong — bấm "Chấm điểm".' : 'Recorded — tap "Grade".';
  String get practiceScaleTitle => isVi ? 'Luyện thang ngũ cung' : 'Pentatonic scale practice';
  String get practiceScaleHint => isVi ? 'Nghe mẫu thang âm rồi hát theo — chấm độ bám thang (chroma).' : 'Listen to the scale sample then sing along — scored by chroma adherence.';
  String get practiceScale => isVi ? 'Điệu thang' : 'Scale';
  String get practiceScaleNotes => isVi ? 'Nốt' : 'Notes';
  String get practiceScaleSample => isVi ? 'Mẫu thang' : 'Scale sample';
  String get practiceScaleRecord => isVi ? 'Thu tiếng hát' : 'Record singing';
  String get practiceScaleGrade => isVi ? 'Chấm thang' : 'Grade scale';
  String get practiceOnScale => isVi ? 'Độ bám thang' : 'Scale adherence';
  String get practiceMicDenied => isVi ? 'Mic bị từ chối' : 'Microphone denied';
  String get practiceMicStartFail => isVi ? 'Không bắt đầu được ghi âm. Kiểm tra quyền microphone.' : 'Could not start recording. Check microphone permission.';
  String get practiceBusySection => isVi ? 'Đang thu câu hát — hãy dừng bản thu đó trước.' : 'A phrase recording is in progress — stop it first.';
  String get practiceBusyScale => isVi ? 'Đang thu luyện thang — hãy dừng bản thu đó trước.' : 'A scale recording is in progress — stop it first.';
  String get practiceCountIn => isVi ? 'Đếm nhập' : 'Count-in';
  String get practiceReplayTake => isVi ? 'Nghe lại bản thu của bạn:' : 'Replay your take:';
  String get practiceMidiBtn => isVi ? 'MIDI bản luyện' : 'Practice MIDI';
  String get practiceSaved => isVi ? 'Đã lưu' : 'Saved';
  String get practiceProgressTitle => isVi ? 'Tiến độ gần đây' : 'Recent progress';
  String get practiceAvg5 => isVi ? 'TB 5 lượt' : 'Avg of 5';
  String get practiceLastScore => isVi ? 'Điểm lần gần nhất' : 'Latest score';
  String get practiceSentence => isVi ? 'Câu' : 'Phrase';
  String practiceHistoryPhrase(String title, int n) => isVi ? '$title — Câu $n' : '$title — Phrase $n';
  String practiceHistoryScale(String name) => isVi ? 'Luyện thang $name' : 'Scale practice $name';
  String lessonModeChip(String mode) => isVi ? 'Điệu $mode' : 'Mode $mode';
  String lessonSectionCount(int n) => isVi ? '$n câu' : '$n phrases';
  String practiceCountInLabel(String bpmInfo) => isVi ? 'Đếm nhập $bpmInfo' : 'Count-in $bpmInfo';
  String get practiceScoreTotal => isVi ? 'Tổng' : 'Total';
  String get practiceScorePitch => isVi ? 'Cao độ' : 'Pitch';
  String get practiceScoreTime => isVi ? 'Nhịp' : 'Timing';
  String practiceAvgError(String cents) => isVi ? 'Sai số TB: $cents cents' : 'Avg deviation: $cents cents';
  String practiceScaleResult(String score, String onScale) => isVi
      ? 'Độ bám thang: $score/100 (trong thang: $onScale%)'
      : 'Scale adherence: $score/100 (on scale: $onScale%)';
  String get listenTabTitle => isVi ? 'Thu & phân tích' : 'Record & analyze';
  String get practiceTabTitle => isVi ? 'Luyện tập theo bài' : 'Practice by lesson';
  String get learnRecordBtn => isVi ? 'Thu âm giọng hát' : 'Record your voice';
  String get learnStopBtn => isVi ? 'Dừng thu âm' : 'Stop recording';
  String get learnRecording => isVi ? 'Đang thu âm...' : 'Recording...';
  String get learnAnalyzeBtn => isVi ? 'Phân tích cao độ' : 'Analyze pitch';
  String get learnRetry => isVi ? 'Thử lại' : 'Retry';
  String get audioLoadFail => isVi ? 'Không tải được bản ghi âm. Kiểm tra kết nối với máy chủ AI.' : 'Could not load the recording. Check the AI server connection.';
  String get transcribeNoTake => isVi ? 'Chưa có bản thu. Hãy thu âm ở màn Học hát hoặc chọn tệp.' : 'No recording yet. Record in Learning or pick a file.';
  String get transcribeBpmRange => isVi ? 'BPM trong khoảng 1-300' : 'BPM must be 1-300';
  String get transcribePickFile => isVi ? 'Chưa chọn tệp âm thanh.' : 'No audio file chosen.';
  String get transcribeResultTitle => isVi ? 'Ký âm' : 'Transcription';
  String get transcribeNoSha => isVi ? 'Thiếu mã băm để tải file' : 'Missing hash for download';
  String get transcribeDownloaded => isVi ? 'Đã tải xuống' : 'Downloaded';
  String get transcribeSavedTemp => isVi ? 'Đã lưu vào thư mục tạm' : 'Saved to temp folder';
  String get transcribePickBtn => isVi ? 'Chọn tệp' : 'Pick file';
  String get transcribeUseLast => isVi ? 'Dùng bản thu vừa ghi' : 'Use last recording';
  String get transcribeSource => isVi ? 'Nguồn' : 'Source';
  String get transcribeEngine => isVi ? 'Bộ máy' : 'Engine';
  String get transcribeRunBtn => isVi ? 'Phân tích ký âm' : 'Transcribe';
  String get transcribeMidiBtn => isVi ? 'Tải MIDI' : 'Download MIDI';
  String get transcribeXmlBtn => isVi ? 'Tải MusicXML' : 'Download MusicXML';
  String get transcribePickHint => isVi
      ? 'Chọn tệp âm thanh (bản thu đã lưu ở máy chủ sẽ được liên kết khi ký âm).'
      : 'Pick an audio file (recordings already stored on the server will be linked during transcription).';
  String get transcribeRecordedSource => isVi ? 'bản thu vừa ghi' : 'last recording';
  String transcribeHistoryTitle(String source, int notes) => isVi
      ? 'Ký âm $source ($notes nốt)'
      : 'Transcription of $source ($notes notes)';
  String transcribeDownloadedFile(String name) => isVi ? 'Đã tải xuống $name' : 'Downloaded $name';
  String transcribeSavedTempFile(String name) => isVi ? 'Đã lưu $name vào thư mục tạm' : 'Saved $name to temp folder';
  String transcribeSavedTo(String path) => isVi ? 'Đã lưu $path' : 'Saved to $path';
  String transcribeShareDialog(String name) => isVi ? 'Đã mở hộp thoại lưu/chia sẻ cho $name' : 'Opened save/share dialog for $name';
  String transcribeNotesSummary(String label, int notes) => isVi ? '$label · $notes nốt' : '$label · $notes notes';
  String transcribeMoreNotes(int n) => isVi
      ? '... và $n nốt nữa (xem trong tệp MIDI/MusicXML)'
      : '... and $n more notes (see the MIDI/MusicXML file)';
  String saveFileDialog(String name) => isVi ? 'Lưu $name' : 'Save $name';

  String get creationBannerSubtitle => isVi
      ? 'Bảo tồn 100% lòng bản di sản — Thăng hoa sáng tạo lời ca mới'
      : 'Preserving 100% of the heritage melody — soar with your new lyrics';
  String get creationTabOriginal => isVi ? 'Hát Nguyên Bản' : 'Sing Original';
  String get creationTabNewLyrics => isVi ? 'Sáng Tạo Lời Mới' : 'New Lyrics';
  String get creationPickTuneLabel => isVi ? 'Chọn Bài Bản Di Sản:' : 'Choose a Heritage Piece:';
  String get creationFolkArtist => isVi ? 'Nghệ nhân dân gian Huế' : 'Hue folk artisan';
  String get creationModeLabel => isVi ? 'Hơi / Điệu thức:' : 'Mode / Scale:';
  String get creationVerseLabel => isVi ? 'Thể thơ:' : 'Verse form:';
  String get creationInstrumentsLabel => isVi ? 'Dàn nhạc cụ:' : 'Instrumental ensemble:';
  String get creationLyricsTitle => isVi ? 'Lời Ca Di Sản Chuẩn Mực' : 'Canonical Heritage Lyrics';
  String get creationModeOrnamented => isVi ? 'Chế độ: Có luyến láy' : 'Mode: With ornaments';
  String get creationModePlain => isVi ? 'Chế độ: Lời thơ' : 'Mode: Plain verse';
  String get creationNoLyrics => isVi ? '[Không có lời ca]' : '[No lyrics]';
  String get creationListenMaster => isVi ? '🎧 Nghe Bản Gốc Nghệ Nhân' : '🎧 Listen to the Artisan Original';
  String get creationCollapseMaster => isVi ? 'Thu gọn nghe bản gốc' : 'Collapse original player';
  String creationOriginalTrack(String title) => isVi ? 'Bản gốc: $title' : 'Original: $title';
  String get creationAiRecreateTitle => isVi ? 'AI Tái Hiện Bài Bản Nguyên Gốc' : 'AI Recreation of the Original Piece';
  String get creationVocalLabel => isVi ? 'Giọng hát' : 'Voice';
  String get creationTempoLabel => isVi ? 'Tốc độ' : 'Tempo';
  String get creationDurationLabel => isVi ? 'Thời lượng' : 'Duration';
  String get creationMoodLabel => isVi ? 'Cảm xúc' : 'Mood';
  String get creationLoraModelLabel => isVi ? 'Mô hình LoRA' : 'LoRA model';
  String get creationLoraBaseDefault => isVi ? 'Mô hình nền mặc định' : 'Default base model';
  String get creationDefault => isVi ? 'Mặc định' : 'Default';
  String get creationRunOriginalBtn => isVi ? '✨ Bắt Đầu AI Tái Hiện Nguyên Bản' : '✨ Start AI Original Recreation';
  String get creationRunNewLyricsBtn => isVi ? '✨ AI Cất Giọng Hát Lời Mới' : '✨ AI Sings Your New Lyrics';
  String get creationLyricsRequired => isVi ? 'Vui lòng nhập lời thơ hoặc sáng tác mới.' : 'Please enter new or original verses.';
  String get creationFallbackTuneTitle => isVi ? 'Bài bản di sản' : 'Heritage piece';
  String creationLockedMelody(String title) => isVi ? 'KHÓA 100% GIAI ĐIỆU LÒNG BẢN: $title' : 'MELODY 100% LOCKED: $title';
  String get creationLockedMelodyDesc => isVi
      ? 'Hệ thống dùng toàn bộ xương sống giai điệu lòng bản di sản cổ truyền làm nhạc nền. AI sẽ giữ nguyên vẹn giai điệu và hát chính xác theo lời thơ mới do bạn sáng tạo.'
      : 'The system uses the full traditional heritage melody as the backing track. The AI keeps the melody intact and sings exactly your new lyrics.';
  String get creationRhymeGuideTitle => isVi ? 'Hướng Dẫn Thể Thơ & Vần Điệu:' : 'Verse Form & Rhyme Guide:';
  String creationRhymeGuideDefault(String? bpm) {
    final bpmText = bpm ?? (isVi ? 'khoan thai' : 'leisurely');
    return isVi
        ? 'Khuyên dùng thơ Lục bát hoặc thể 4 chữ, ngắt nhịp tương ứng với nhịp $bpmText.'
        : 'Prefer Luc Bat or four-word verse, phrasing to match the $bpmText tempo.';
  }
  String get creationSampleVerseTitle => isVi ? 'Gợi ý thơ mẫu 1 chạm:' : 'One-tap sample verses:';
  String get creationSampleLucBat => isVi ? 'Thơ Lục bát Sông Hương' : 'Perfume River Luc Bat';
  String get creationSampleFourWord => isVi ? 'Thơ 4 chữ rộn ràng' : 'Lively four-word verse';
  String get creationSampleTuTinh => isVi ? 'Tự tình cố đô' : 'Old Capital Musings';
  String get creationComposeTitle => isVi ? 'Soạn Thảo Lời Thơ Mới *' : 'Compose New Verses *';
  String creationWordCount(int n) => isVi ? '$n từ' : '$n words';
  String get creationLyricsHint => isVi
      ? 'Nhập lời ca hoặc bài thơ do bạn sáng tác vào đây...\n(Ví dụ: thơ lục bát, thơ 4 chữ hoặc khúc hát đối đáp)'
      : 'Type your own lyrics or poem here...\n(e.g. Luc Bat, four-word verse or an antiphonal song)';
  String get creationEmptyTunesTitle => isVi ? 'Chưa có bài bản di sản nào trong cơ sở dữ liệu' : 'No heritage pieces in the database yet';
  String get creationEmptyTunesDesc => isVi
      ? 'Hãy chạy lệnh "python -m app.database.seed_heritage" trên máy chủ hoặc tải lên bài bản mới từ mục Kho di sản.'
      : 'Run "python -m app.database.seed_heritage" on the server or upload new pieces from the Heritage Archive.';
  String get creationReloadData => isVi ? 'Tải lại dữ liệu' : 'Reload data';
  String creationPollLost(int attempts) => isVi
      ? 'Mất kết nối máy chủ khi chờ kết quả (đã thử $attempts lần). Tác vụ vẫn chạy phía máy chủ.'
      : 'Lost server connection while waiting for the result (tried $attempts times). The task is still running on the server.';

  String get serverNotConfigured => isVi ? 'Chưa cấu hình máy chủ.' : 'Server not configured.';
  String get errorPrefix => isVi ? 'Lỗi' : 'Error';
  String get noData => isVi ? 'Chưa có dữ liệu' : 'No data';

  String get cancelBtn => isVi ? 'Hủy' : 'Cancel';
  String get processing => isVi ? 'Đang xử lý...' : 'Processing...';

  String get themeModeTitle => isVi ? 'Chế độ giao diện' : 'Appearance';
  String get themeSystem => isVi ? 'Theo hệ thống' : 'System Default';
  String get themeLight => isVi ? 'Giao diện Sáng' : 'Light Mode';
  String get themeDark => isVi ? 'Giao diện Tối' : 'Dark Mode';

  String get languageTitle => isVi ? 'Ngôn ngữ' : 'Language';
  String get langEnglish => 'English';
  String get langVietnamese => 'Tiếng Việt';

  String get settingsAppInfo => isVi ? 'Ứng dụng' : 'Application';
  String get settingsName => isVi ? 'Tên' : 'Name';
  String get settingsDescription => isVi ? 'Mô tả' : 'Summary';

  String get offlineMessage => isVi
      ? 'Mất kết nối mạng. Một số chức năng cần internet.'
      : 'No network connection. Some online features may be unavailable.';

  String get playBtn => isVi ? 'Phát' : 'Play';
  String get versionLabel => isVi ? 'Phiên bản' : 'Version';
  String get sidebarTagline => isVi ? 'AI Di sản âm nhạc' : 'AI Heritage Music';
  String get sheetDisclaimer => isVi
      ? 'Bản nhạc dự đoán tự động – cần nghệ nhân kiểm duyệt.'
      : 'Auto-predicted sheet music – needs artisan review.';
  String get sheetEmpty => isVi ? 'Chưa có nốt nhạc để hiển thị' : 'No notes to display';
  String get waveformEmpty => isVi ? 'Chưa có dữ liệu sóng âm' : 'No waveform data';
  String get taskStatusLabel => isVi ? 'Trạng thái tác vụ:' : 'Task status:';
  String taskNotice(String reason) => isVi ? 'Thông báo: $reason' : 'Notice: $reason';
  String get taskBlockedNote => isVi
      ? 'Máy chủ AI đang ở chế độ chờ kiểm thử trọng số. Tác phẩm AI cần HuếMusic-LoRA được nạp từ các checkpoint đã huấn luyện.'
      : 'The AI server is on standby for checkpoint testing. AI works require the trained HueMusic-LoRA checkpoints to be loaded.';
  String get taskAiGenerated => isVi ? 'TÁC PHẨM ĐƯỢC AI TẠO MỚI (AI_GENERATED)' : 'AI-GENERATED WORK (AI_GENERATED)';

  String modulesCount(int n) => isVi ? '$n chức năng' : '$n modules';


  String get serverOnline => isVi ? 'Máy chủ AI: Trực tuyến' : 'AI Server: Online';
  String get serverOffline => isVi ? 'Máy chủ AI: Ngoại tuyến' : 'AI Server: Offline';

  String get masterDetailEmptyTitle => isVi
      ? 'Chọn một tác phẩm từ danh sách'
      : 'Select a recording from the archive';
  String get masterDetailEmptySubtitle => isVi
      ? 'Xem thông tin lịch sử, lời ca và thưởng thức bản thu âm di sản'
      : 'Inspect metadata, lyrics, and listen to authentic heritage recordings';

  String get heritageArchiveTitle => isVi ? 'Kho Di sản Âm nhạc Số' : 'Digital Heritage Archive';
  String get heritageArchiveSubtitle => isVi
      ? 'Lưu trữ và thưởng thức các bản ghi âm cổ truyền nguyên bản'
      : 'Preserve and enjoy authentic traditional heritage recordings';
  String heritageTonal(String t) => isVi ? 'Cung bậc / Tông: $t' : 'Mode / Key: $t';
  String heritageNowPlaying(String title) => isVi ? 'Đang phát: $title' : 'Now playing: $title';
  String get heritageLyricsTitle => isVi ? 'Lời ca di sản' : 'Heritage Lyrics';
  String get heritageInfoTitle => isVi ? 'Thông tin tư liệu di sản' : 'Heritage Documentation';
  String get heritageOriginalNote => isVi
      ? 'Bản thu gốc di sản được bảo toàn nguyên trạng, dành riêng cho nghe và thưởng thức.'
      : 'The original heritage recording is preserved intact, for listening and enjoyment only.';

  String get restorationLabTitle => isVi
      ? 'Phân hệ Nghiên cứu Phục dựng Âm thanh Cổ truyền (Beta)'
      : 'Heritage Audio Restoration Research Lab (Beta)';
  String get restorationLabDesc => isVi
      ? 'Công cụ DSP chuyên sâu phục vụ nghiên cứu bảo tồn: Khử nhiễu nền, bù trừ DC-offset, triệt tiêu xung nhiễu (clicks & pops) và cân bằng phổ âm thanh bản ghi lịch sử.'
      : 'Dedicated DSP tools for heritage acoustic research: broadband denoising, DC-offset filtering, click/pop suppression, and spectral normalization.';

  String get restorationBeforeLabel => isVi ? 'Bản thu gốc (Trước phục dựng)' : 'Original (Before Restoration)';
  String get restorationAfterLabel => isVi ? 'Bản phục dựng (Sau xử lý DSP)' : 'Restored (After DSP Processing)';
  String get restorationRunBtn => isVi ? 'Chạy phục dựng (Beta)' : 'Run Restoration (Beta)';
  String get restorationMetricsTitle => isVi ? 'Chỉ số Kỹ thuật Phục dựng DSP' : 'DSP Restoration Metrics';
  String get restorationDcRemoved => isVi ? 'Thành phần DC đã khử' : 'DC Offset Removed';
  String get restorationClicksFixed => isVi ? 'Xung nhiễu đã sửa' : 'Clicks & Pops Fixed';
  String get restorationPeakChange => isVi ? 'Mức đỉnh biên độ' : 'Peak Amplitude Level';
  String get restorationNoiseFloor => isVi ? 'Mức nền nhiễu ước lượng' : 'Estimated Noise Floor';
  String get restorationAlgorithm => isVi
      ? 'Giải thuật: Median Filter + High-pass IIR + Adaptive Limiter'
      : 'Algorithm: Median Filter + High-pass IIR + Adaptive Limiter';
  String get restorationEmptyTitle => isVi
      ? 'Chọn một bản thu để nghiên cứu phục dựng'
      : 'Select a recording to research restoration';
  String get restorationEmptySubtitle => isVi
      ? 'Thực hiện khử nhiễu, sửa xung click/pop và so sánh trực tiếp A/B'
      : 'Perform denoising, click/pop repair, and compare audio A/B directly';

  String get restorationTabDsp => isVi ? 'Khôi phục chất lượng âm thanh' : 'Audio Restoration';
  String get restorationTabCompare => isVi ? 'Đối chiếu & Tìm tên bài' : 'Cross-Compare & Identify';
  String get comparePickSample => isVi ? 'Bản ghi mẫu (Kho di sản)' : 'Reference Heritage Track';
  String get comparePickTarget => isVi ? 'Bản ghi cần đối chiếu / nhận diện' : 'Target Track to Identify';
  String get compareRunBtn => isVi ? 'Đối chiếu âm học & Nhận diện bài' : 'Run Acoustic Matching & Identify';
  String get compareIdentifiedMatch => isVi ? 'Làn điệu nhận diện khớp nhất' : 'Best Matching Tune';
  String get compareContourTitle => isVi ? 'Biểu đồ đối chiếu cao độ F0' : 'F0 Pitch Contour Alignment';
  String get compareUploadPrompt => isVi ? 'Tải lên bản ghi của bạn để đối chiếu' : 'Upload Your Own Recording to Compare';
  String get restorationUploadVintageBtn => isVi ? 'Tải lên bản thu cũ để phục dựng' : 'Upload Vintage Recording';
  String get restorationCompareAB => isVi
      ? 'So sánh Đối chứng A/B (Trước & Sau phục dựng)'
      : 'A/B Reference Comparison (Before & After Restoration)';
  String get compareTabDescription => isVi
      ? 'Đối chiếu bản thu âm cổ chưa rõ nguồn gốc với cơ sở dữ liệu làn điệu Ca Huế và Nhã nhạc cung đình để tìm ra tên bài và kiểm định âm luật.'
      : 'Cross-compare vintage recordings against the Hue heritage tune database to identify song names and verify musical scales.';
  String get compareNoTarget => isVi ? 'Chưa chọn bản ghi cần đối chiếu' : 'No target track selected';
  String get compareVerdictHigh => isVi ? 'Trùng khớp điệu thức cao' : 'High Match';
  String get compareVerdictModerate => isVi ? 'Tương đồng một phần điệu thức' : 'Moderate Match';
  String get compareVerdictDifferent => isVi ? 'Khác làn điệu hoặc chênh lệch âm giai' : 'Different Tune';
  String get compareResultsTitle => isVi ? 'Kết quả Nhận diện & Đối chiếu' : 'Identification & Match Results';
  String compareVerdictLine(String verdict) => isVi ? 'Nhận định: $verdict' : 'Verdict: $verdict';
  String compareMetricsLine(String cents, String ms) => isVi
      ? 'Sai số cao độ: $cents cents · Lệch thời gian: $ms ms'
      : 'Pitch deviation: $cents cents · Time offset: $ms ms';
  String get compareChartSample => isVi ? 'Bản ghi mẫu' : 'Sample track';
  String get compareChartTarget => isVi ? 'Bản ghi đối chiếu' : 'Comparison track';
  String get compareChartSampleDataset => isVi ? 'Bản ghi mẫu (Dataset)' : 'Sample track';

  String get emptyHistory => isVi ? 'Chưa có hoạt động nào được ghi lại trên thiết bị này.' : 'No activity recorded on this device yet.';
  String get clearHistory => isVi ? 'Xóa lịch sử' : 'Clear History';
  String get confirmClearHistory => isVi ? 'Bạn có chắc chắn muốn xóa toàn bộ lịch sử hoạt động trên thiết bị này?' : 'Are you sure you want to clear all activity history on this device?';
  String get historyPrivacyNote => isVi ? 'Lịch sử được lưu trữ bảo mật cục bộ trên thiết bị của bạn và không gửi lên máy chủ.' : 'Activity history is stored securely on your local device and never sent to any server.';
  String get historyFilterAll => isVi ? 'Tất cả' : 'All';
  String get historyFilterPractice => isVi ? 'Luyện tập' : 'Practice';
  String get historyStatusDone => isVi ? 'Hoàn thành' : 'Done';
  String get historyStatusError => isVi ? 'Lỗi' : 'Error';
  String get historyStatusRunning => isVi ? 'Đang chạy' : 'Running';
  String historyScore(String score) => isVi ? '$score đ' : '$score pts';
  String historySingOriginal(String title) => isVi ? 'Hát nguyên bản: $title' : 'Sing original: $title';
  String historySingNew(String title) => isVi ? 'Sáng tạo mới: $title' : 'New creation: $title';
  String get deleteBtn => isVi ? 'Xóa' : 'Delete';
  String get collapseSidebar => isVi ? 'Thu gọn thanh bên' : 'Collapse sidebar';
  String get expandSidebar => isVi ? 'Mở rộng thanh bên' : 'Expand sidebar';

  String get featSettingsSubtitle => isVi
      ? 'Cấu hình kết nối máy chủ AI, giao diện và ngôn ngữ'
      : 'Configure AI server connection, UI theme and language';

  String get authScreenTitle => isVi ? 'Tài khoản & Xác thực' : 'Account & Authentication';
  String get authTabLogin => isVi ? 'Đăng nhập' : 'Sign In';
  String get authTabRegister => isVi ? 'Đăng ký (Mã mời)' : 'Register (Invite Code)';
  String get authLoginIdLabel => isVi ? 'Tên tài khoản hoặc Email' : 'Username or Email';
  String get authLoginIdHint => isVi ? 'user123 hoặc abc@gmail.com' : 'user123 or abc@gmail.com';
  String get authPasswordLabel => isVi ? 'Mật khẩu' : 'Password';
  String get authPasswordMinLabel => isVi ? 'Mật khẩu (tối thiểu 6 ký tự)' : 'Password (min 6 characters)';
  String get authUsernameLabel => isVi ? 'Tên tài khoản' : 'Username';
  String get authGmailLabel => 'Email';
  String get authGmailHint => isVi ? 'vidu@tenmien.vn' : 'you@example.com';
  String get authInviteLabel => isVi ? 'Mã mời tham gia' : 'Invitation code';
  String get authInviteHint => isVi
      ? 'Nhập mã mời do ban quản trị cấp (VD: QHH2026)'
      : 'Enter the invite code issued by the admin (e.g. QHH2026)';
  String get authLoginBtn => isVi ? 'Đăng nhập' : 'Sign In';
  String get authRegisterBtn => isVi ? 'Đăng ký tài khoản' : 'Create Account';
  String get authGuestBtn => isVi ? 'Trải nghiệm ngay (Chế độ Khách)' : 'Try now (Guest Mode)';
  String get authGuestNote => isVi
      ? '* Chế độ khách cho phép trải nghiệm trực tiếp nhưng không lưu lại dữ liệu sau khi thoát ứng dụng.'
      : '* Guest mode lets you explore instantly, but nothing is saved after you exit the app.';
  String get authNoResetNote => isVi
      ? 'Quên mật khẩu? Liên hệ quản trị viên để được đặt lại (bạn sẽ nhận mật khẩu tạm).'
      : 'Forgot your password? Contact the administrator for a reset (you will receive a temporary password).';
  String get authStorageWarning => isVi
      ? 'Máy này chưa có kho bảo mật (keyring/libsecret trên Linux) nên không lưu được phiên đăng nhập. Hãy cài libsecret hoặc dùng Chế độ Khách.'
      : 'This machine has no secure keyring (libsecret on Linux), so sign-in cannot be saved. Install libsecret or use Guest Mode.';
  String get authRegisterFootnote => isVi
      ? '* Mỗi email chỉ được tạo 1 tài khoản. Cần mã mời hợp lệ.'
      : '* Each email can create only one account. A valid invite code is required.';
  String get authOrDivider => isVi ? 'HOẶC' : 'OR';
  String get authLogoutBtn => isVi ? 'Đăng xuất' : 'Sign Out';
  String get authGuestModeBtn => isVi ? 'Chế độ Khách' : 'Guest Mode';
  String get authLoggedInChip => isVi
      ? 'Chế độ Tài khoản — Lưu phiên đăng nhập trên máy này'
      : 'Account Mode — sign-in saved on this device';
  String get authRoleAdmin => isVi ? 'Quản trị trưởng (Admin)' : 'Head Administrator';
  String get authRoleUser => isVi ? 'Người dùng' : 'User';
  String get authInviteTitle => isVi ? 'Quản lý mã mời (Admin)' : 'Invite Code Management (Admin)';
  String get authInviteManageHint => isVi
      ? 'Mã dùng một lần — người được tặng đăng ký xong mã tự vô hiệu. Tạo, sao chép, hoặc xóa tại đây.'
      : 'One-time codes — they disable themselves after one registration. Create, copy or delete here.';
  String get authInviteEmpty => isVi ? 'Chưa có mã mời nào trong cơ sở dữ liệu.' : 'No invite codes in the database yet.';
  String get authInviteCreate => isVi ? 'Tạo mã mời mới' : 'Create new invite code';
  String get authInviteUsed => isVi ? 'Đã dùng' : 'Used';
  String get authInviteAvailable => isVi ? 'Còn hiệu lực' : 'Available';
  String get authInviteCopy => isVi ? 'Sao chép' : 'Copy';
  String get authInviteCopied => isVi ? 'Đã sao chép' : 'Copied';
  String get authInviteCopyFail => isVi ? 'Không sao chép được tự động — hãy ghi tay mã' : 'Auto-copy failed — please note the code manually';
  String get authInviteDelete => isVi ? 'Xóa mã' : 'Delete code';
  String get authInviteDeleteConfirm => isVi ? 'Xóa mã mời' : 'Delete invite code';
  String get authInviteCreated => isVi ? 'Đã tạo mã mời' : 'Invite code created';
  String get authInviteLoadFail => isVi ? 'Không tải được danh sách mã mời' : 'Failed to load invite codes';
  String get changePasswordBtn => isVi ? 'Đổi mật khẩu' : 'Change password';
  String get changePasswordOld => isVi ? 'Mật khẩu hiện tại' : 'Current password';
  String get changePasswordNew => isVi ? 'Mật khẩu mới (tối thiểu 6 ký tự)' : 'New password (min 6 characters)';
  String get changePasswordConfirm => isVi ? 'Nhập lại mật khẩu mới' : 'Confirm new password';
  String get changePasswordMismatch => isVi
      ? 'Mật khẩu mới chưa khớp hoặc ngắn hơn 6 ký tự.'
      : 'New passwords do not match or are shorter than 6 characters.';
  String get changePasswordDone => isVi ? 'Đã đổi mật khẩu — các thiết bị khác bị đăng xuất.' : 'Password changed — other devices were signed out.';
  String get logoutEverywhereBtn => isVi ? 'Đăng xuất mọi thiết bị' : 'Sign out on all devices';
  String get logoutEverywhereConfirm => isVi
      ? 'Thu hồi toàn bộ phiên đăng nhập của tài khoản này trên mọi thiết bị (kể cả máy hiện tại)?'
      : 'Revoke all sessions of this account on every device (including this one)?';
  String get logoutEverywhereDone => isVi ? 'Đã thu hồi toàn bộ phiên.' : 'All sessions revoked.';
  String get accountManagerTitle => isVi ? 'Danh sách tài khoản (Admin)' : 'Accounts (Admin)';
  String get accountManagerHint => isVi
      ? 'Vô hiệu hóa/kích hoạt tài khoản, đặt lại mật khẩu hộ (mật khẩu tạm tự sinh).'
      : 'Disable/enable accounts, reset a password (a temporary one is generated).';
  String get accountResetPassword => isVi ? 'Đặt lại mật khẩu' : 'Reset password';
  String get accountResetConfirm => isVi ? 'Đặt lại mật khẩu cho' : 'Reset password for';
  String get accountTempPassword => isVi ? 'Mật khẩu tạm' : 'Temporary password';
  String get accountDeleteTitle => isVi ? 'Xóa tài khoản' : 'Delete account';
  String get accountDeleteConfirm => isVi ? 'XÓA VĨNH VIỄN tài khoản' : 'PERMANENTLY delete account';
  String get accountDeleteIrreversible => isVi ? 'Hành động này không thể hoàn tác.' : 'This cannot be undone.';
  String get accountDeleted => isVi ? 'Đã xóa tài khoản' : 'Account deleted';
  String get onboardingTitle => isVi ? 'Kết nối máy chủ AI' : 'Connect to AI Server';
  String get onboardingHint => isVi
      ? 'Nhập địa chỉ máy chủ HUE HERITAGE MUSIC trong mạng nội bộ (bạn có thể thay đổi sau trong Cài đặt).'
      : 'Enter the HUE HERITAGE MUSIC server address on your local network (changeable later in Settings).';
  String get onboardingUrlLabel => isVi ? 'Địa chỉ máy chủ' : 'Server address';
  String get onboardingConnect => isVi ? 'Kết nối' : 'Connect';
  String get onboardingLater => isVi ? 'Để sau' : 'Later';
  String get onboardingEnterUrl => isVi ? 'Vui lòng nhập địa chỉ máy chủ.' : 'Please enter the server address.';
  String get onboardingSaveFail => isVi ? 'Không lưu được địa chỉ.' : 'Could not save the address.';
  String get authDefaultUser => isVi ? 'Người dùng' : 'User';
  String get authGuestUsername => isVi ? 'Khách' : 'Guest';
  String get authTooltipLoggedIn => isVi ? 'Tài khoản' : 'Account';
  String get authTooltipGuest => isVi ? 'Tài khoản / Chế độ Khách' : 'Account / Guest Mode';
  String get authErrLoginId => isVi ? 'Vui lòng nhập tên tài khoản hoặc Email' : 'Please enter your username or Email';
  String get authErrPasswordEmpty => isVi ? 'Vui lòng nhập mật khẩu' : 'Please enter your password';
  String get authErrUsernameShort => isVi
      ? 'Tên tài khoản phải có ít nhất 3 ký tự'
      : 'Username must be at least 3 characters';
  String get authErrEmail => isVi
      ? 'Địa chỉ email không hợp lệ'
      : 'Invalid email address';
  String get authErrPasswordShort => isVi
      ? 'Mật khẩu phải có ít nhất 6 ký tự'
      : 'Password must be at least 6 characters';
  String get authErrInvite => isVi ? 'Vui lòng nhập mã mời hợp lệ' : 'Please enter a valid invite code';

  String get sessionExpired => isVi
      ? 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.'
      : 'Your session has expired, please log in again.';

  String get mustChangeTitle => isVi ? 'Đổi mật khẩu' : 'Change password';
  String get mustChangeBody => isVi
      ? 'Quản trị viên đã đặt mật khẩu tạm cho tài khoản của bạn. Hãy đặt mật khẩu mới để bảo mật.'
      : 'An administrator set a temporary password for your account. Please set a new one.';
  String get mustChangeNow => isVi ? 'Đổi mật khẩu' : 'Change password';
  String get mustChangeLater => isVi ? 'Để sau' : 'Later';

  String get navAdmin => isVi ? 'Quản trị' : 'Admin';
  String get adminTitle => isVi ? 'Quản trị hệ thống' : 'System Administration';
  String get adminTabDashboard => isVi ? 'Tổng quan' : 'Dashboard';
  String get adminTabUsers => isVi ? 'Người dùng' : 'Users';
  String get adminTabInvites => isVi ? 'Mã mời' : 'Invites';
  String get adminTabStorage => isVi ? 'Kho lưu trữ' : 'Storage';
  String get adminStatUsers => isVi ? 'Tài khoản' : 'Accounts';
  String get adminStatActive => isVi ? 'Đang hoạt động' : 'Active';
  String get adminStatInvites => isVi ? 'Mã mời' : 'Invites';
  String get adminStatUnused => isVi ? 'Còn hiệu lực' : 'Unused';
  String get adminStatItems => isVi ? 'Bản ghi di sản' : 'Heritage items';
  String get adminStatStorage => isVi ? 'Dung lượng kho' : 'Archive size';
  String get adminStatDerived => isVi ? 'File dẫn xuất' : 'Derived files';
  String get adminStatGenerated => isVi ? 'Bản thu AI đã tạo' : 'AI-generated audio';
  String get adminStatTasks => isVi ? 'Tác vụ theo trạng thái' : 'Tasks by status';
  String get adminStatTasksKind => isVi ? 'Tác vụ theo loại' : 'Tasks by kind';
  String get adminEngineOnline => isVi ? 'Engine AI: ĐANG CHẠY' : 'AI engine: ONLINE';
  String get adminEngineOffline => isVi ? 'Engine AI: NGOẠI TUYẾN' : 'AI engine: OFFLINE';
  String get adminEngineOfflineHint => isVi
      ? 'Engine AI đang ngoại tuyến — tính năng Sáng tạo sẽ bị chặn cho tới khi máy chủ AI hoạt động lại.'
      : 'The AI engine is offline — Creation features will be blocked until the AI server is back.';
  String get adminCreateUserTitle => isVi ? 'Tạo tài khoản mới' : 'Create new account';
  String get adminCreateUserUsername => isVi ? 'Tên tài khoản' : 'Username';
  String get adminCreateUserEmail => isVi ? 'Email (không bắt buộc)' : 'Email (optional)';
  String get adminCreateUserPassword => isVi
      ? 'Mật khẩu (để trống để tự sinh)'
      : 'Password (leave empty to auto-generate)';
  String get adminCreateUserButton => isVi ? 'Tạo tài khoản' : 'Create account';
  String adminCreateUserDone(String username, String pass) => isVi
      ? 'Đã tạo "$username" — mật khẩu tạm: $pass'
      : 'Created "$username" — temporary password: $pass';
  String get adminCreateUserFail => isVi ? 'Không tạo được tài khoản.' : 'Could not create the account.';
  String get adminStorageEmpty => isVi ? 'Kho lưu trữ trống.' : 'Storage is empty.';
  String get adminStorageDeleteConfirm => isVi
      ? 'Xóa bản ghi này cùng toàn bộ file đính kèm (gốc, MIDI, MusicXML, phục dựng)?'
      : 'Delete this item and all attached files (original, MIDI, MusicXML, restored)?';
  String get adminStorageDeleted => isVi ? 'Đã xóa bản ghi.' : 'Item deleted.';
  String get adminStorageOriginalMissing => isVi ? 'Thiếu file gốc' : 'Original file missing';
  String get adminRefresh => isVi ? 'Làm mới' : 'Refresh';
  String get adminSearchHint => isVi ? 'Tìm trong kho...' : 'Search storage...';
  String get adminDelete => isVi ? 'Xóa' : 'Delete';
  String get adminCancel => isVi ? 'Hủy' : 'Cancel';
  String get adminLoadFail => isVi ? 'Không tải được dữ liệu quản trị.' : 'Failed to load admin data.';
  String get adminReauthTitle => isVi ? 'Xác thực quản trị' : 'Admin re-authorization';
  String get adminReauthBody => isVi
      ? 'Hành động này nhạy cảm — nhập lại mật khẩu tài khoản quản trị để tiếp tục (hiệu lực 10 phút).'
      : 'This is a sensitive action — re-enter the admin password to continue (valid for 10 minutes).';
  String get adminReauthPasswordLabel => isVi ? 'Mật khẩu quản trị' : 'Admin password';
  String get adminReauthConfirm => isVi ? 'Xác nhận' : 'Confirm';
  String get adminReauthWrong => isVi ? 'Mật khẩu không đúng' : 'Wrong password';
  String get adminReauthCancelled => isVi ? 'Đã hủy — chưa xác thực quản trị.' : 'Cancelled — admin not re-authorized.';
}
