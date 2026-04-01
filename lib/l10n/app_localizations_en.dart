// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'AI Sound Separation';

  @override
  String get tabHome => 'Home';

  @override
  String get tabHistory => 'History';

  @override
  String get tabMine => 'Me';

  @override
  String get homeTitle => 'AI Sound Separation';

  @override
  String get homeSubtitle => 'Intelligent Audio Track Separation';

  @override
  String get typeVocals => 'Vocal Extraction';

  @override
  String get typeVocalsDesc => 'Extract vocals from songs';

  @override
  String get typeNoise => 'Accompaniment';

  @override
  String get typeNoiseDesc => 'Remove vocals, keep accompaniment';

  @override
  String get typeDrums => 'Drums Separation';

  @override
  String get typeDrumsDesc => 'Extract drums and percussion';

  @override
  String get typeBass => 'Bass Separation';

  @override
  String get typeBassDesc => 'Extract bass tracks';

  @override
  String get typePiano => 'Piano Separation';

  @override
  String get typePianoDesc => 'Extract piano tracks';

  @override
  String get typeOther => 'Other Instruments';

  @override
  String get typeOtherDesc => 'Extract other instrument tracks';

  @override
  String get uploadTitle => 'Upload Audio';

  @override
  String get uploadSelectFile => 'Select Local File';

  @override
  String get uploadInputUrl => 'Input Audio URL';

  @override
  String get uploadUrlHint => 'Enter audio or video URL';

  @override
  String get uploadUrlDialogTitle => 'Input URL';

  @override
  String get uploadUrlDialogCancel => 'Cancel';

  @override
  String get uploadUrlDialogConfirm => 'Confirm';

  @override
  String get uploadSupported => 'Supports MP3, WAV, FLAC, M4A and more';

  @override
  String get uploadSourceItunes => 'iTunes';

  @override
  String get uploadSourceItunesDesc =>
      'Local audio tracks downloaded on device';

  @override
  String get uploadSourceCameraRoll => 'Album Videos';

  @override
  String get uploadSourceCameraRollDesc =>
      'Video files from device photo library';

  @override
  String get uploadSourceFiles => 'Files';

  @override
  String get uploadSourceFilesDesc => 'Audio files from documents';

  @override
  String get uploadSourceUrl => 'Import from URL';

  @override
  String get uploadSourceUrlDesc =>
      'Any media from cloud services or public URL';

  @override
  String get uploadMaxSize => 'Max file size: 1GB';

  @override
  String get uploadFaqTitle => 'FAQ';

  @override
  String get uploadProgress => 'Uploading...';

  @override
  String get uploadSuccess => 'Upload successful, separation task submitted';

  @override
  String get uploadFailed => 'Upload failed';

  @override
  String get historyTitle => 'History';

  @override
  String get historyEmpty => 'No history yet';

  @override
  String get historyEmptyHint =>
      'Complete an audio separation to see results here';

  @override
  String get historyStatusUploading => 'Uploading';

  @override
  String get historyStatusPending => 'Pending';

  @override
  String get historyStatusProcessing => 'Processing';

  @override
  String get historyStatusCompleted => 'Completed';

  @override
  String get historyStatusQueued => 'Queued';

  @override
  String get historyStatusFailed => 'Failed';

  @override
  String get historyPlay => 'Play';

  @override
  String get historyPause => 'Pause';

  @override
  String get historyDownload => 'Download';

  @override
  String historyTrackCount(Object count) {
    return '$count tracks';
  }

  @override
  String get historyDelete => 'Delete';

  @override
  String get historyDeleteConfirm =>
      'Are you sure you want to delete this record?';

  @override
  String get historyRetry => 'Retry';

  @override
  String get historyAllLoaded => 'All loaded';

  @override
  String get mineTitle => 'Me';

  @override
  String get mineAnonymousUser => 'Anonymous User';

  @override
  String get mineUserId => 'User ID';

  @override
  String get mineUsageGuide => 'Usage Guide';

  @override
  String get mineAbout => 'About';

  @override
  String get mineVersion => 'Version';

  @override
  String get mineLanguage => 'Language';

  @override
  String get mineChinese => '中文';

  @override
  String get mineEnglish => 'English';

  @override
  String get confirm => 'Confirm';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get error => 'Error';

  @override
  String get loading => 'Loading...';

  @override
  String get networkError => 'Network error, please try again';

  @override
  String get usageGuideContent =>
      '1. This tool uses AI technology for audio separation\n2. Supports multiple audio formats\n3. Processing time depends on file size\n4. Listen and download after processing\n5. Free version has usage limits';

  @override
  String get downloadPreparing => 'Preparing download...';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get downloadSuccess => 'Download complete';

  @override
  String get playFailed => 'Playback failed';

  @override
  String get share => 'Share';

  @override
  String get stemLabelVocals => 'Vocals';

  @override
  String get stemLabelVoiceClean => 'Clean Voice';

  @override
  String get stemLabelDrum => 'Drums';

  @override
  String get stemLabelBass => 'Bass';

  @override
  String get stemLabelAcousticGuitar => 'Acoustic Guitar';

  @override
  String get stemLabelElectricGuitar => 'Electric Guitar';

  @override
  String get stemLabelPiano => 'Piano';

  @override
  String get stemLabelSynthesizer => 'Synthesizer';

  @override
  String get stemLabelStrings => 'Strings';

  @override
  String get stemLabelWind => 'Wind';

  @override
  String get stemLabelAccompaniment => 'Accompaniment';

  @override
  String get stemLabelOther => 'Other';

  @override
  String get uploadSourceWifi => 'WiFi Transfer';

  @override
  String get uploadSourceWifiDesc =>
      'Upload files from computer browser via LAN';

  @override
  String get wifiTransferTitle => 'WiFi Transfer';

  @override
  String get wifiTransferStep1 =>
      '1. Connect phone and computer to the same WiFi';

  @override
  String get wifiTransferStep2 =>
      '2. Open the address below in your computer browser';

  @override
  String get wifiTransferStep3 =>
      '3. Drag or select files to upload on the webpage';

  @override
  String get wifiTransferStarted => 'WiFi transfer service started';

  @override
  String get wifiTransferStopped => 'WiFi transfer service stopped';

  @override
  String get wifiTransferReceived => 'File received, processing...';

  @override
  String get wifiTransferNoWifi => 'Not connected to WiFi';

  @override
  String get wifiTransferClose => 'Stop Transfer';

  @override
  String get wifiTransferFileReceived => 'File Received';

  @override
  String wifiTransferFileReceivedMsg(Object fileName) {
    return '\"$fileName\" has been received.\n\nWould you like to start the separation task now?';
  }

  @override
  String get wifiTransferContinue => 'Not Now';

  @override
  String get wifiTransferStartNow => 'Confirm';

  @override
  String get wifiTransferMaxFiles => 'Please process the received file first';

  @override
  String get errorNetworkLost =>
      'Network connection lost, please check and retry';

  @override
  String get errorTimeout => 'Upload timed out, please check network and retry';

  @override
  String get errorNoInternet =>
      'No internet connection, please check network settings';

  @override
  String get errorServerError => 'Server error, please try again later';

  @override
  String get errorFileNotFound =>
      'File has been cleaned up, please select a new file';

  @override
  String get errorUploadFailed => 'Upload failed, please retry';

  @override
  String get errorProcessingFailed => 'Processing failed';

  @override
  String get errorProcessingTimeout => 'Processing timed out';

  @override
  String get errorUploadInterrupted => 'Upload interrupted, please retry';

  @override
  String get errorMissingParams => 'Missing upload parameters';

  @override
  String get stemNameVocals => 'Extract Vocals & Accompaniment';

  @override
  String get stemNameNoise => 'Remove Background Noise';

  @override
  String get stemNameDrums => 'Extract Drums';

  @override
  String get stemNameBass => 'Extract Bass';

  @override
  String get stemNameAcoustic => 'Extract Acoustic Guitar';

  @override
  String get stemNameElectric => 'Extract Electric Guitar';

  @override
  String get stemNamePiano => 'Extract Piano';

  @override
  String get stemNameSynth => 'Extract Synthesizer';

  @override
  String get stemNameStrings => 'Extract Strings';

  @override
  String get stemNameWind => 'Extract Wind Instruments';

  @override
  String get errorPickAudioFailed => 'Failed to pick audio';

  @override
  String get wifiTransferOpenInBrowser => 'Open in your computer browser';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get wifiTransferCopyUrl => 'Copy URL';

  @override
  String wifiTransferReceivedCount(Object count) {
    return '$count file(s) received';
  }

  @override
  String get mineNotLoggedIn => 'Not logged in';

  @override
  String get permissionDeniedTitle => 'Permission Required';

  @override
  String get permissionPhotoDenied =>
      'Please allow photo library access to select videos';

  @override
  String get permissionMediaDenied =>
      'Please allow media library access to select audio files';

  @override
  String get permissionGoSettings => 'Open Settings';

  @override
  String get permissionDeniedMessage =>
      'You have denied this permission. Please go to Settings to enable it manually.';
}
