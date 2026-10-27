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

  String get featSettingsSubtitle => isVi
      ? 'Cấu hình kết nối máy chủ AI, giao diện và ngôn ngữ'
      : 'Configure AI server connection, UI theme and language';

  String get authScreenTitle => isVi ? 'Tài khoản & Xác thực' : 'Account & Authentication';
  String get authTabLogin => isVi ? 'Đăng nhập' : 'Sign In';
  String get authTabRegister => isVi ? 'Đăng ký (Mã mời)' : 'Register (Invite Code)';
  String get authLoginIdLabel => isVi ? 'Tên tài khoản hoặc Gmail' : 'Username or Gmail';
  String get authLoginIdHint => isVi ? 'user123 hoặc abc@gmail.com' : 'user123 or abc@gmail.com';
  String get authPasswordLabel => isVi ? 'Mật khẩu' : 'Password';
  String get authPasswordMinLabel => isVi ? 'Mật khẩu (tối thiểu 6 ký tự)' : 'Password (min 6 characters)';
  String get authUsernameLabel => isVi ? 'Tên tài khoản' : 'Username';
  String get authGmailLabel => 'Gmail (@gmail.com)';
  String get authGmailHint => isVi ? 'vidu@gmail.com' : 'example@gmail.com';
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
      ? 'Phiên bản hiện tại chưa hỗ trợ đặt lại mật khẩu. Vui lòng ghi nhớ thông tin đăng nhập.'
      : 'The current version does not support password reset yet. Please remember your credentials.';
  String get authStorageWarning => isVi
      ? 'Máy này chưa có kho bảo mật (keyring/libsecret trên Linux) nên không lưu được phiên đăng nhập. Hãy cài libsecret hoặc dùng Chế độ Khách.'
      : 'This machine has no secure keyring (libsecret on Linux), so sign-in cannot be saved. Install libsecret or use Guest Mode.';
  String get authRegisterFootnote => isVi
      ? '* Mỗi Gmail chỉ được tạo 1 tài khoản. Cần mã mời hợp lệ.'
      : '* Each Gmail can create only one account. A valid invite code is required.';
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
  String get authErrLoginId => isVi ? 'Vui lòng nhập tên tài khoản hoặc Gmail' : 'Please enter your username or Gmail';
  String get authErrPasswordEmpty => isVi ? 'Vui lòng nhập mật khẩu' : 'Please enter your password';
  String get authErrUsernameShort => isVi
      ? 'Tên tài khoản phải có ít nhất 3 ký tự'
      : 'Username must be at least 3 characters';
  String get authErrGmail => isVi
      ? 'Chỉ chấp nhận địa chỉ email có đuôi @gmail.com'
      : 'Only @gmail.com addresses are accepted';
  String get authErrPasswordShort => isVi
      ? 'Mật khẩu phải có ít nhất 6 ký tự'
      : 'Password must be at least 6 characters';
  String get authErrInvite => isVi ? 'Vui lòng nhập mã mời hợp lệ' : 'Please enter a valid invite code';
}
