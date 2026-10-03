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
  String get cancelBtn => isVi ? 'Hủy' : 'Cancel';
  String get processing => isVi ? 'Đang xử lý...' : 'Processing...';

  String get themeModeTitle => isVi ? 'Chế độ giao diện' : 'Appearance';
  String get themeSystem => isVi ? 'Theo hệ thống' : 'System Default';
  String get themeLight => isVi ? 'Giao diện Sáng' : 'Light Mode';
  String get themeDark => isVi ? 'Giao diện Tối' : 'Dark Mode';

  String get languageTitle => isVi ? 'Ngôn ngữ' : 'Language';
  String get langEnglish => 'English';
  String get langVietnamese => 'Tiếng Việt';

  String get offlineMessage => isVi
      ? 'Mất kết nối mạng. Một số chức năng cần internet.'
      : 'No network connection. Some online features may be unavailable.';

  String get playBtn => isVi ? 'Phát' : 'Play';
  String get versionLabel => isVi ? 'Phiên bản' : 'Version';
  String get sidebarTagline => isVi ? 'AI Di sản âm nhạc' : 'AI Heritage Music';

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

  String get emptyHistory => isVi ? 'Chưa có hoạt động nào được ghi lại trên thiết bị này.' : 'No activity recorded on this device yet.';
  String get clearHistory => isVi ? 'Xóa lịch sử' : 'Clear History';
  String get confirmClearHistory => isVi ? 'Bạn có chắc chắn muốn xóa toàn bộ lịch sử hoạt động trên thiết bị này?' : 'Are you sure you want to clear all activity history on this device?';
  String get historyPrivacyNote => isVi ? 'Lịch sử được lưu trữ bảo mật cục bộ trên thiết bị của bạn và không gửi lên máy chủ.' : 'Activity history is stored securely on your local device and never sent to any server.';
  String get deleteBtn => isVi ? 'Xóa' : 'Delete';
  String get collapseSidebar => isVi ? 'Thu gọn thanh bên' : 'Collapse sidebar';
  String get expandSidebar => isVi ? 'Mở rộng thanh bên' : 'Expand sidebar';
}
