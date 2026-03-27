import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI音频分离'**
  String get appTitle;

  /// No description provided for @tabHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get tabHome;

  /// No description provided for @tabHistory.
  ///
  /// In zh, this message translates to:
  /// **'历史记录'**
  String get tabHistory;

  /// No description provided for @tabMine.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabMine;

  /// No description provided for @homeTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI音频分离'**
  String get homeTitle;

  /// No description provided for @homeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'智能音轨分离工具'**
  String get homeSubtitle;

  /// No description provided for @typeVocals.
  ///
  /// In zh, this message translates to:
  /// **'人声提取'**
  String get typeVocals;

  /// No description provided for @typeVocalsDesc.
  ///
  /// In zh, this message translates to:
  /// **'提取歌曲中的人声'**
  String get typeVocalsDesc;

  /// No description provided for @typeNoise.
  ///
  /// In zh, this message translates to:
  /// **'伴奏提取'**
  String get typeNoise;

  /// No description provided for @typeNoiseDesc.
  ///
  /// In zh, this message translates to:
  /// **'去除人声保留伴奏'**
  String get typeNoiseDesc;

  /// No description provided for @typeDrums.
  ///
  /// In zh, this message translates to:
  /// **'鼓点分离'**
  String get typeDrums;

  /// No description provided for @typeDrumsDesc.
  ///
  /// In zh, this message translates to:
  /// **'提取鼓和打击乐器'**
  String get typeDrumsDesc;

  /// No description provided for @typeBass.
  ///
  /// In zh, this message translates to:
  /// **'贝斯分离'**
  String get typeBass;

  /// No description provided for @typeBassDesc.
  ///
  /// In zh, this message translates to:
  /// **'提取贝斯音轨'**
  String get typeBassDesc;

  /// No description provided for @typePiano.
  ///
  /// In zh, this message translates to:
  /// **'钢琴分离'**
  String get typePiano;

  /// No description provided for @typePianoDesc.
  ///
  /// In zh, this message translates to:
  /// **'提取钢琴音轨'**
  String get typePianoDesc;

  /// No description provided for @typeOther.
  ///
  /// In zh, this message translates to:
  /// **'其他乐器'**
  String get typeOther;

  /// No description provided for @typeOtherDesc.
  ///
  /// In zh, this message translates to:
  /// **'提取其他乐器音轨'**
  String get typeOtherDesc;

  /// No description provided for @uploadTitle.
  ///
  /// In zh, this message translates to:
  /// **'上传音频'**
  String get uploadTitle;

  /// No description provided for @uploadSelectFile.
  ///
  /// In zh, this message translates to:
  /// **'选择本地文件'**
  String get uploadSelectFile;

  /// No description provided for @uploadInputUrl.
  ///
  /// In zh, this message translates to:
  /// **'输入音频链接'**
  String get uploadInputUrl;

  /// No description provided for @uploadUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入音频或视频URL'**
  String get uploadUrlHint;

  /// No description provided for @uploadUrlDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'输入链接'**
  String get uploadUrlDialogTitle;

  /// No description provided for @uploadUrlDialogCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get uploadUrlDialogCancel;

  /// No description provided for @uploadUrlDialogConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get uploadUrlDialogConfirm;

  /// No description provided for @uploadSupported.
  ///
  /// In zh, this message translates to:
  /// **'支持 MP3、WAV、FLAC、M4A 等常见格式'**
  String get uploadSupported;

  /// No description provided for @uploadSourceItunes.
  ///
  /// In zh, this message translates to:
  /// **'iTunes'**
  String get uploadSourceItunes;

  /// No description provided for @uploadSourceItunesDesc.
  ///
  /// In zh, this message translates to:
  /// **'设备上已下载的本地音轨'**
  String get uploadSourceItunesDesc;

  /// No description provided for @uploadSourceCameraRoll.
  ///
  /// In zh, this message translates to:
  /// **'相机胶卷'**
  String get uploadSourceCameraRoll;

  /// No description provided for @uploadSourceCameraRollDesc.
  ///
  /// In zh, this message translates to:
  /// **'设备相册中的任何视频'**
  String get uploadSourceCameraRollDesc;

  /// No description provided for @uploadSourceFiles.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get uploadSourceFiles;

  /// No description provided for @uploadSourceFilesDesc.
  ///
  /// In zh, this message translates to:
  /// **'文档中的音频文件'**
  String get uploadSourceFilesDesc;

  /// No description provided for @uploadSourceUrl.
  ///
  /// In zh, this message translates to:
  /// **'从 URL 导入'**
  String get uploadSourceUrl;

  /// No description provided for @uploadSourceUrlDesc.
  ///
  /// In zh, this message translates to:
  /// **'来自云服务或公共 URL 的任何媒体'**
  String get uploadSourceUrlDesc;

  /// No description provided for @uploadMaxSize.
  ///
  /// In zh, this message translates to:
  /// **'单文件最大 200MB'**
  String get uploadMaxSize;

  /// No description provided for @uploadFaqTitle.
  ///
  /// In zh, this message translates to:
  /// **'常见问题'**
  String get uploadFaqTitle;

  /// No description provided for @uploadProgress.
  ///
  /// In zh, this message translates to:
  /// **'上传中...'**
  String get uploadProgress;

  /// No description provided for @uploadSuccess.
  ///
  /// In zh, this message translates to:
  /// **'上传成功，已提交分离任务'**
  String get uploadSuccess;

  /// No description provided for @uploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'上传失败'**
  String get uploadFailed;

  /// No description provided for @historyTitle.
  ///
  /// In zh, this message translates to:
  /// **'历史记录'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史记录'**
  String get historyEmpty;

  /// No description provided for @historyEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'完成一次音频分离后将显示在这里'**
  String get historyEmptyHint;

  /// No description provided for @historyStatusUploading.
  ///
  /// In zh, this message translates to:
  /// **'上传中'**
  String get historyStatusUploading;

  /// No description provided for @historyStatusPending.
  ///
  /// In zh, this message translates to:
  /// **'等待处理'**
  String get historyStatusPending;

  /// No description provided for @historyStatusProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get historyStatusProcessing;

  /// No description provided for @historyStatusCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get historyStatusCompleted;

  /// No description provided for @historyStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get historyStatusFailed;

  /// No description provided for @historyPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get historyPlay;

  /// No description provided for @historyPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get historyPause;

  /// No description provided for @historyDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get historyDownload;

  /// No description provided for @historyTrackCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条分轨'**
  String historyTrackCount(Object count);

  /// No description provided for @historyDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get historyDelete;

  /// No description provided for @historyDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除这条记录吗？'**
  String get historyDeleteConfirm;

  /// No description provided for @historyRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get historyRetry;

  /// No description provided for @mineTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get mineTitle;

  /// No description provided for @mineAnonymousUser.
  ///
  /// In zh, this message translates to:
  /// **'匿名用户'**
  String get mineAnonymousUser;

  /// No description provided for @mineUserId.
  ///
  /// In zh, this message translates to:
  /// **'用户ID'**
  String get mineUserId;

  /// No description provided for @mineUsageGuide.
  ///
  /// In zh, this message translates to:
  /// **'使用须知'**
  String get mineUsageGuide;

  /// No description provided for @mineAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get mineAbout;

  /// No description provided for @mineVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get mineVersion;

  /// No description provided for @mineLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get mineLanguage;

  /// No description provided for @mineChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get mineChinese;

  /// No description provided for @mineEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get mineEnglish;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'好的'**
  String get ok;

  /// No description provided for @error.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get error;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get loading;

  /// No description provided for @networkError.
  ///
  /// In zh, this message translates to:
  /// **'网络错误，请稍后重试'**
  String get networkError;

  /// No description provided for @usageGuideContent.
  ///
  /// In zh, this message translates to:
  /// **'1. 本工具使用AI技术进行音频分离\n2. 支持多种音频格式\n3. 单次处理时间取决于文件大小\n4. 处理完成后可在线试听和下载\n5. 免费版有一定使用限制'**
  String get usageGuideContent;

  /// No description provided for @downloadPreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备下载中...'**
  String get downloadPreparing;

  /// No description provided for @downloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载失败'**
  String get downloadFailed;

  /// No description provided for @downloadSuccess.
  ///
  /// In zh, this message translates to:
  /// **'下载完成'**
  String get downloadSuccess;

  /// No description provided for @playFailed.
  ///
  /// In zh, this message translates to:
  /// **'播放失败'**
  String get playFailed;

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @stemLabelVocals.
  ///
  /// In zh, this message translates to:
  /// **'人声'**
  String get stemLabelVocals;

  /// No description provided for @stemLabelVoiceClean.
  ///
  /// In zh, this message translates to:
  /// **'去噪人声'**
  String get stemLabelVoiceClean;

  /// No description provided for @stemLabelDrum.
  ///
  /// In zh, this message translates to:
  /// **'鼓点'**
  String get stemLabelDrum;

  /// No description provided for @stemLabelBass.
  ///
  /// In zh, this message translates to:
  /// **'贝斯'**
  String get stemLabelBass;

  /// No description provided for @stemLabelAcousticGuitar.
  ///
  /// In zh, this message translates to:
  /// **'原声吉他'**
  String get stemLabelAcousticGuitar;

  /// No description provided for @stemLabelElectricGuitar.
  ///
  /// In zh, this message translates to:
  /// **'电吉他'**
  String get stemLabelElectricGuitar;

  /// No description provided for @stemLabelPiano.
  ///
  /// In zh, this message translates to:
  /// **'钢琴'**
  String get stemLabelPiano;

  /// No description provided for @stemLabelSynthesizer.
  ///
  /// In zh, this message translates to:
  /// **'合成器'**
  String get stemLabelSynthesizer;

  /// No description provided for @stemLabelStrings.
  ///
  /// In zh, this message translates to:
  /// **'弦乐'**
  String get stemLabelStrings;

  /// No description provided for @stemLabelWind.
  ///
  /// In zh, this message translates to:
  /// **'管乐'**
  String get stemLabelWind;

  /// No description provided for @stemLabelAccompaniment.
  ///
  /// In zh, this message translates to:
  /// **'伴奏'**
  String get stemLabelAccompaniment;

  /// No description provided for @stemLabelOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get stemLabelOther;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
