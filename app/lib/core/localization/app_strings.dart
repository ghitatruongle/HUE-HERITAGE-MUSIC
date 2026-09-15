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
  String get navCreation => isVi ? 'AI Sáng tạo' : 'AI Creation';
  String get navCover => isVi ? 'Cover' : 'Cover Song';
  String get navRestoration => isVi ? 'Phục dựng' : 'Restoration';
  String get navInstruments => isVi ? 'Nhạc cụ' : 'Instruments';

  String get featHeritageTitle => isVi ? 'Kho di sản' : 'Heritage Archive';
  String get featHeritageDesc => isVi
      ? 'Tra cứu, tìm kiếm bản ghi di sản, nghe bản gốc và bản phục chế'
      : 'Browse and search heritage recordings, listen to original and restored audio';

  String get featLearningTitle => isVi ? 'Học hát Ca Huế' : 'Singing Practice';
  String get featLearningDesc => isVi
      ? 'Thu âm giọng hát, so sánh cao độ với bản mẫu của nghệ nhân'
      : 'Record voice, compare pitch contours against master artisans';

  String get featAnalysisTitle => isVi ? 'Phân tích bản thu' : 'Pitch Analysis';
  String get featAnalysisDesc => isVi
      ? 'Phân tích đường cao độ F0 của một bản thu bất kỳ'
      : 'Analyze F0 fundamental frequency curve of any recording';

  String get featTranscriptionTitle => isVi ? 'Audio -> Bản nhạc' : 'Audio to Sheet';
  String get featTranscriptionDesc => isVi
      ? 'Chuyển bản thu âm thành file MIDI và bản nhạc MusicXML'
      : 'Transcribe audio recordings into MIDI and MusicXML sheet music';

  String get featCreationTitle => isVi ? 'AI Sáng tạo' : 'AI Creation';
  String get featCreationDesc => isVi
      ? 'Sáng tác bản nhạc mới mang âm hưởng Huế (cần model đã huấn luyện)'
      : 'Compose new music pieces imbued with Hue heritage melodies';

  String get featCoverTitle => isVi ? 'Cover' : 'Cover Song';
  String get featCoverDesc => isVi
      ? 'Tạo phiên bản cover từ bản ghi di sản (cần model đã huấn luyện)'
      : 'Generate cover variations from heritage source recordings';

  String get featRestorationTitle => isVi ? 'Phục dựng' : 'Restoration';
  String get featRestorationDesc => isVi
      ? 'Khử nhiễu, phục hồi bản ghi cũ trong kho di sản'
      : 'Denoise and enhance vintage historical Hue recordings';

  String get featInstrumentsTitle => isVi ? 'Nhạc cụ' : 'Instruments';
  String get featInstrumentsDesc => isVi
      ? 'Nhận diện nhạc cụ truyền thống xuất hiện trong bản thu'
      : 'Identify traditional Vietnamese instruments appearing in audio';

  String get featHistoryTitle => isVi ? 'Lịch sử' : 'History';
  String get featHistoryDesc => isVi
      ? 'Xem lại các tác vụ đã thực hiện và trạng thái của chúng'
      : 'Review executed tasks, processing status, and results';

  String get featInfoTitle => isVi ? 'Thông tin dự án' : 'Project Info';
  String get featInfoDesc => isVi
      ? 'Triết lý, nhãn dữ liệu và thông tin bản quyền của hệ thống'
      : 'Philosophy, dataset taxonomy, ethics, and copyright terms';

  String get searchHint => isVi
      ? 'Tìm theo tên, nghệ nhân, nhạc cụ, thời gian, địa điểm...'
      : 'Search by title, artisan, instrument, period, location...';
  String get searchBtn => isVi ? 'Tìm' : 'Search';
  String get addRecordingBtn => isVi ? 'Thêm bản ghi' : 'Add Recording';
  String get noRecordings => isVi ? 'Chưa có bản ghi' : 'No recordings found';
  String get originalAudio => isVi ? 'Bản gốc' : 'Original';
  String get restoredAudio => isVi ? 'Bản phục chế' : 'Restored';
  String get detailsBtn => isVi ? 'Chi tiết' : 'Details';
  String get useAsSampleBtn => isVi ? 'Luyện hát' : 'Use as Sample';
  String get restoreActionBtn => isVi ? 'Phục dựng' : 'Restore';
  String get detectInstrumentsBtn => isVi ? 'Nhạc cụ' : 'Instruments';
  String get closeBtn => isVi ? 'Đóng' : 'Close';
  String get cancelBtn => isVi ? 'Hủy' : 'Cancel';
  String get submitBtn => isVi ? 'Lưu' : 'Submit';
  String get processing => isVi ? 'Đang xử lý...' : 'Processing...';

  String get themeModeTitle => isVi ? 'Chế độ giao diện' : 'Appearance';
  String get themeSystem => isVi ? 'Theo hệ thống' : 'System Default';
  String get themeLight => isVi ? 'Giao diện Sáng' : 'Light Mode';
  String get themeDark => isVi ? 'Giao diện Tối' : 'Dark Mode';

  String get languageTitle => isVi ? 'Ngôn ngữ' : 'Language';
  String get langEnglish => 'English';
  String get langVietnamese => 'Tiếng Việt';
  String get langAuto => isVi ? 'Tự động' : 'Auto Detect';

  String get offlineMessage => isVi
      ? 'Mất kết nối mạng. Một số chức năng cần internet.'
      : 'No network connection. Some online features may be unavailable.';

  String get playingNow => isVi ? 'Đang phát' : 'Now Playing';
  String get loopTrack => isVi ? 'Lặp lại' : 'Loop Track';
  String get volumeLabel => isVi ? 'Âm lượng' : 'Volume';
  String get playBtn => isVi ? 'Phát' : 'Play';
  String get versionLabel => isVi ? 'Phiên bản' : 'Version';
  String get sidebarTagline => isVi ? 'AI Di sản âm nhạc' : 'AI Heritage Music';

  String modulesCount(int n) => isVi ? '$n chức năng' : '$n modules';

  String get statsRecordings => isVi ? 'Bản ghi di sản' : 'Heritage Tracks';
  String get statsRestored => isVi ? 'Phục chế' : 'Restored';
  String get statsInstruments => isVi ? 'Nhạc cụ' : 'Instruments';

  String get serverOnline => isVi ? 'Máy chủ AI: Trực tuyến' : 'AI Server: Online';
  String get serverOffline => isVi ? 'Máy chủ AI: Ngoại tuyến' : 'AI Server: Offline';

  String get masterDetailEmptyTitle => isVi
      ? 'Chọn một tác phẩm từ danh sách'
      : 'Select a recording from the archive';
  String get masterDetailEmptySubtitle => isVi
      ? 'Xem thông tin lịch sử, phổ F0, lời ca và nghe bản gốc hoặc phục dựng'
      : 'Inspect metadata, pitch contour, lyrics, and play original or restored audio';
}
