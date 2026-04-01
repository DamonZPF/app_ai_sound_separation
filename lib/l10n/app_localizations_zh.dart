// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'AI音频分离';

  @override
  String get tabHome => '首页';

  @override
  String get tabHistory => '历史记录';

  @override
  String get tabMine => '我的';

  @override
  String get homeTitle => 'AI音频分离';

  @override
  String get homeSubtitle => '智能音轨分离工具';

  @override
  String get typeVocals => '人声提取';

  @override
  String get typeVocalsDesc => '提取歌曲中的人声';

  @override
  String get typeNoise => '伴奏提取';

  @override
  String get typeNoiseDesc => '去除人声保留伴奏';

  @override
  String get typeDrums => '鼓点分离';

  @override
  String get typeDrumsDesc => '提取鼓和打击乐器';

  @override
  String get typeBass => '贝斯分离';

  @override
  String get typeBassDesc => '提取贝斯音轨';

  @override
  String get typePiano => '钢琴分离';

  @override
  String get typePianoDesc => '提取钢琴音轨';

  @override
  String get typeOther => '其他乐器';

  @override
  String get typeOtherDesc => '提取其他乐器音轨';

  @override
  String get uploadTitle => '上传音频';

  @override
  String get uploadSelectFile => '选择本地文件';

  @override
  String get uploadInputUrl => '输入音频链接';

  @override
  String get uploadUrlHint => '请输入音频或视频URL';

  @override
  String get uploadUrlDialogTitle => '输入链接';

  @override
  String get uploadUrlDialogCancel => '取消';

  @override
  String get uploadUrlDialogConfirm => '确认';

  @override
  String get uploadSupported => '支持 MP3、WAV、FLAC、M4A 等常见格式';

  @override
  String get uploadSourceItunes => 'iTunes';

  @override
  String get uploadSourceItunesDesc => '设备上已下载的本地音轨';

  @override
  String get uploadSourceCameraRoll => '相册视频';

  @override
  String get uploadSourceCameraRollDesc => '设备相册中的视频文件';

  @override
  String get uploadSourceFiles => '文件';

  @override
  String get uploadSourceFilesDesc => '文档中的音频文件';

  @override
  String get uploadSourceUrl => '从 URL 导入';

  @override
  String get uploadSourceUrlDesc => '来自云服务或公共 URL 的任何媒体';

  @override
  String get uploadMaxSize => '单文件最大 1GB';

  @override
  String get uploadFaqTitle => '常见问题';

  @override
  String get uploadProgress => '上传中...';

  @override
  String get uploadSuccess => '上传成功，已提交分离任务';

  @override
  String get uploadFailed => '上传失败';

  @override
  String get historyTitle => '历史记录';

  @override
  String get historyEmpty => '暂无历史记录';

  @override
  String get historyEmptyHint => '完成一次音频分离后将显示在这里';

  @override
  String get historyStatusUploading => '上传中';

  @override
  String get historyStatusPending => '等待处理';

  @override
  String get historyStatusProcessing => '处理中';

  @override
  String get historyStatusCompleted => '已完成';

  @override
  String get historyStatusQueued => '排队中';

  @override
  String get historyStatusFailed => '失败';

  @override
  String get historyPlay => '播放';

  @override
  String get historyPause => '暂停';

  @override
  String get historyDownload => '下载';

  @override
  String historyTrackCount(Object count) {
    return '$count 条分轨';
  }

  @override
  String get historyDelete => '删除';

  @override
  String get historyDeleteConfirm => '确定要删除这条记录吗？';

  @override
  String get historyRetry => '重试';

  @override
  String get historyAllLoaded => '已全部加载';

  @override
  String get mineTitle => '我的';

  @override
  String get mineAnonymousUser => '匿名用户';

  @override
  String get mineUserId => '用户ID';

  @override
  String get mineUsageGuide => '使用须知';

  @override
  String get mineAbout => '关于';

  @override
  String get mineVersion => '版本';

  @override
  String get mineLanguage => '语言';

  @override
  String get mineChinese => '中文';

  @override
  String get mineEnglish => 'English';

  @override
  String get confirm => '确认';

  @override
  String get cancel => '取消';

  @override
  String get ok => '好的';

  @override
  String get error => '错误';

  @override
  String get loading => '加载中...';

  @override
  String get networkError => '网络错误，请稍后重试';

  @override
  String get usageGuideContent =>
      '1. 本工具使用AI技术进行音频分离\n2. 支持多种音频格式\n3. 单次处理时间取决于文件大小\n4. 处理完成后可在线试听和下载\n5. 免费版有一定使用限制';

  @override
  String get downloadPreparing => '准备下载中...';

  @override
  String get downloadFailed => '下载失败';

  @override
  String get downloadSuccess => '下载完成';

  @override
  String get playFailed => '播放失败';

  @override
  String get share => '分享';

  @override
  String get stemLabelVocals => '人声';

  @override
  String get stemLabelVoiceClean => '去噪人声';

  @override
  String get stemLabelDrum => '鼓点';

  @override
  String get stemLabelBass => '贝斯';

  @override
  String get stemLabelAcousticGuitar => '原声吉他';

  @override
  String get stemLabelElectricGuitar => '电吉他';

  @override
  String get stemLabelPiano => '钢琴';

  @override
  String get stemLabelSynthesizer => '合成器';

  @override
  String get stemLabelStrings => '弦乐';

  @override
  String get stemLabelWind => '管乐';

  @override
  String get stemLabelAccompaniment => '伴奏';

  @override
  String get stemLabelOther => '其他';

  @override
  String get uploadSourceWifi => 'WiFi 传输';

  @override
  String get uploadSourceWifiDesc => '通过局域网从电脑浏览器上传文件';

  @override
  String get wifiTransferTitle => 'WiFi 传输';

  @override
  String get wifiTransferStep1 => '1. 确保手机和电脑连接同一 WiFi';

  @override
  String get wifiTransferStep2 => '2. 在电脑浏览器中打开下方地址';

  @override
  String get wifiTransferStep3 => '3. 在网页中拖拽或选择文件上传';

  @override
  String get wifiTransferStarted => 'WiFi 传输服务已启动';

  @override
  String get wifiTransferStopped => 'WiFi 传输服务已停止';

  @override
  String get wifiTransferReceived => '已收到文件，正在处理...';

  @override
  String get wifiTransferNoWifi => '未连接 WiFi，无法启动传输服务';

  @override
  String get wifiTransferClose => '关闭传输';

  @override
  String get wifiTransferFileReceived => '文件已接收';

  @override
  String wifiTransferFileReceivedMsg(Object fileName) {
    return '「$fileName」已接收完成。\n\n是否立即开始分离任务？';
  }

  @override
  String get wifiTransferContinue => '暂不执行';

  @override
  String get wifiTransferStartNow => '确认执行';

  @override
  String get wifiTransferMaxFiles => '请先处理已接收的文件';

  @override
  String get wifiTransferExitTitle => '确认离开';

  @override
  String get wifiTransferExitMessage => '离开当前页面将停止 WiFi 传输服务，无法继续接收文件。';

  @override
  String get errorNetworkLost => '网络连接中断，请检查网络后重试';

  @override
  String get errorTimeout => '上传超时，请检查网络后重试';

  @override
  String get errorNoInternet => '无网络连接，请检查网络设置';

  @override
  String get errorServerError => '服务器异常，请稍后重试';

  @override
  String get errorFileNotFound => '文件已被清理，请重新选择文件上传';

  @override
  String get errorUploadFailed => '上传失败，请重试';

  @override
  String get errorProcessingFailed => '处理失败';

  @override
  String get errorProcessingTimeout => '处理超时';

  @override
  String get errorUploadInterrupted => '上传已中断，请重试';

  @override
  String get errorMissingParams => '缺少上传参数';

  @override
  String get stemNameVocals => '提取人声与伴奏';

  @override
  String get stemNameNoise => '去除背景噪音';

  @override
  String get stemNameDrums => '提取鼓点音轨';

  @override
  String get stemNameBass => '提取贝斯音轨';

  @override
  String get stemNameAcoustic => '提取原声吉他音轨';

  @override
  String get stemNameElectric => '提取电吉他音轨';

  @override
  String get stemNamePiano => '提取钢琴音轨';

  @override
  String get stemNameSynth => '提取合成器音轨';

  @override
  String get stemNameStrings => '提取弦乐音轨';

  @override
  String get stemNameWind => '提取管乐器音轨';

  @override
  String get errorPickAudioFailed => '选取音频失败';

  @override
  String get wifiTransferOpenInBrowser => '在电脑浏览器中输入';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get wifiTransferCopyUrl => '复制地址';

  @override
  String wifiTransferReceivedCount(Object count) {
    return '已接收 $count 个文件';
  }

  @override
  String get mineNotLoggedIn => '未登录';

  @override
  String get permissionDeniedTitle => '需要访问权限';

  @override
  String get permissionPhotoDenied => '需要相册访问权限才能选择视频文件';

  @override
  String get permissionPhotoLimited =>
      '当前为“私密访问”模式，部分视频可能无法显示。建议在设置中开启“允许完全访问”。';

  @override
  String get permissionMediaDenied => '请允许访问媒体库以选取音频文件';

  @override
  String get permissionGoSettings => '前往设置';

  @override
  String get permissionDeniedMessage => '您已拒绝此权限。请前往「设置」手动开启相关权限开关。';
}
