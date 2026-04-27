import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

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
    Locale('vi'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In vi, this message translates to:
  /// **'VinFast Battery'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In vi, this message translates to:
  /// **'Quản lý pin xe máy điện VinFast'**
  String get appTagline;

  /// No description provided for @tabHome.
  ///
  /// In vi, this message translates to:
  /// **'Trang chủ'**
  String get tabHome;

  /// No description provided for @tabAI.
  ///
  /// In vi, this message translates to:
  /// **'AI'**
  String get tabAI;

  /// No description provided for @tabTrip.
  ///
  /// In vi, this message translates to:
  /// **'Lộ trình'**
  String get tabTrip;

  /// No description provided for @tabService.
  ///
  /// In vi, this message translates to:
  /// **'Bảo dưỡng'**
  String get tabService;

  /// No description provided for @tabSettings.
  ///
  /// In vi, this message translates to:
  /// **'Cài đặt'**
  String get tabSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In vi, this message translates to:
  /// **'Cài đặt'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In vi, this message translates to:
  /// **'Giao diện'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceSystem.
  ///
  /// In vi, this message translates to:
  /// **'Theo hệ thống'**
  String get settingsAppearanceSystem;

  /// No description provided for @settingsAppearanceLight.
  ///
  /// In vi, this message translates to:
  /// **'Sáng'**
  String get settingsAppearanceLight;

  /// No description provided for @settingsAppearanceDark.
  ///
  /// In vi, this message translates to:
  /// **'Tối'**
  String get settingsAppearanceDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In vi, this message translates to:
  /// **'Ngôn ngữ'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In vi, this message translates to:
  /// **'Theo hệ thống'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageVietnamese.
  ///
  /// In vi, this message translates to:
  /// **'Tiếng Việt'**
  String get settingsLanguageVietnamese;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In vi, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsNotifications.
  ///
  /// In vi, this message translates to:
  /// **'Thông báo'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsEnable.
  ///
  /// In vi, this message translates to:
  /// **'Bật thông báo'**
  String get settingsNotificationsEnable;

  /// No description provided for @settingsAbout.
  ///
  /// In vi, this message translates to:
  /// **'Về ứng dụng'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In vi, this message translates to:
  /// **'Phiên bản'**
  String get settingsVersion;

  /// No description provided for @settingsPrivacy.
  ///
  /// In vi, this message translates to:
  /// **'Chính sách bảo mật'**
  String get settingsPrivacy;

  /// No description provided for @settingsTerms.
  ///
  /// In vi, this message translates to:
  /// **'Điều khoản sử dụng'**
  String get settingsTerms;

  /// No description provided for @vehicleSelect.
  ///
  /// In vi, this message translates to:
  /// **'Chọn xe'**
  String get vehicleSelect;

  /// No description provided for @vehicleAdd.
  ///
  /// In vi, this message translates to:
  /// **'Thêm xe mới'**
  String get vehicleAdd;

  /// No description provided for @vehicleEdit.
  ///
  /// In vi, this message translates to:
  /// **'Chỉnh sửa xe'**
  String get vehicleEdit;

  /// No description provided for @vehicleName.
  ///
  /// In vi, this message translates to:
  /// **'Tên xe'**
  String get vehicleName;

  /// No description provided for @vehicleModel.
  ///
  /// In vi, this message translates to:
  /// **'Model xe'**
  String get vehicleModel;

  /// No description provided for @vehicleOdo.
  ///
  /// In vi, this message translates to:
  /// **'Odometer'**
  String get vehicleOdo;

  /// No description provided for @vehicleLicensePlate.
  ///
  /// In vi, this message translates to:
  /// **'Biển số'**
  String get vehicleLicensePlate;

  /// No description provided for @batteryStatus.
  ///
  /// In vi, this message translates to:
  /// **'Trạng thái pin'**
  String get batteryStatus;

  /// No description provided for @batteryLevel.
  ///
  /// In vi, this message translates to:
  /// **'Mức pin'**
  String get batteryLevel;

  /// No description provided for @batteryHealth.
  ///
  /// In vi, this message translates to:
  /// **'Sức khỏe pin'**
  String get batteryHealth;

  /// No description provided for @batteryTemperature.
  ///
  /// In vi, this message translates to:
  /// **'Nhiệt độ pin'**
  String get batteryTemperature;

  /// No description provided for @batteryCycles.
  ///
  /// In vi, this message translates to:
  /// **'Số chu kỳ sạc'**
  String get batteryCycles;

  /// No description provided for @chargingTitle.
  ///
  /// In vi, this message translates to:
  /// **'Sạc pin'**
  String get chargingTitle;

  /// No description provided for @chargingStart.
  ///
  /// In vi, this message translates to:
  /// **'Bắt đầu sạc'**
  String get chargingStart;

  /// No description provided for @chargingStop.
  ///
  /// In vi, this message translates to:
  /// **'Dừng sạc'**
  String get chargingStop;

  /// No description provided for @chargingHistory.
  ///
  /// In vi, this message translates to:
  /// **'Lịch sử sạc'**
  String get chargingHistory;

  /// No description provided for @chargingEstimatedTime.
  ///
  /// In vi, this message translates to:
  /// **'Thời gian dự kiến'**
  String get chargingEstimatedTime;

  /// No description provided for @tripTitle.
  ///
  /// In vi, this message translates to:
  /// **'Lộ trình'**
  String get tripTitle;

  /// No description provided for @tripStart.
  ///
  /// In vi, this message translates to:
  /// **'Bắt đầu chuyến đi'**
  String get tripStart;

  /// No description provided for @tripEnd.
  ///
  /// In vi, this message translates to:
  /// **'Kết thúc chuyến đi'**
  String get tripEnd;

  /// No description provided for @tripHistory.
  ///
  /// In vi, this message translates to:
  /// **'Lịch sử chuyến đi'**
  String get tripHistory;

  /// No description provided for @tripDistance.
  ///
  /// In vi, this message translates to:
  /// **'Quãng đường'**
  String get tripDistance;

  /// No description provided for @tripDuration.
  ///
  /// In vi, this message translates to:
  /// **'Thời gian'**
  String get tripDuration;

  /// No description provided for @tripAvgSpeed.
  ///
  /// In vi, this message translates to:
  /// **'Tốc độ trung bình'**
  String get tripAvgSpeed;

  /// No description provided for @maintenanceTitle.
  ///
  /// In vi, this message translates to:
  /// **'Bảo dưỡng'**
  String get maintenanceTitle;

  /// No description provided for @maintenanceAdd.
  ///
  /// In vi, this message translates to:
  /// **'Thêm công việc'**
  String get maintenanceAdd;

  /// No description provided for @maintenanceEdit.
  ///
  /// In vi, this message translates to:
  /// **'Sửa công việc'**
  String get maintenanceEdit;

  /// No description provided for @maintenanceDelete.
  ///
  /// In vi, this message translates to:
  /// **'Xóa công việc'**
  String get maintenanceDelete;

  /// No description provided for @maintenanceDue.
  ///
  /// In vi, this message translates to:
  /// **'Đến hạn'**
  String get maintenanceDue;

  /// No description provided for @maintenanceOverdue.
  ///
  /// In vi, this message translates to:
  /// **'Quá hạn'**
  String get maintenanceOverdue;

  /// No description provided for @maintenanceCompleted.
  ///
  /// In vi, this message translates to:
  /// **'Đã hoàn thành'**
  String get maintenanceCompleted;

  /// No description provided for @aiTitle.
  ///
  /// In vi, this message translates to:
  /// **'Trợ lý AI'**
  String get aiTitle;

  /// No description provided for @aiModels.
  ///
  /// In vi, this message translates to:
  /// **'Models AI'**
  String get aiModels;

  /// No description provided for @aiPredict.
  ///
  /// In vi, this message translates to:
  /// **'Dự đoán'**
  String get aiPredict;

  /// No description provided for @aiChargingTime.
  ///
  /// In vi, this message translates to:
  /// **'Thời gian sạc'**
  String get aiChargingTime;

  /// No description provided for @aiChargingTimeDesc.
  ///
  /// In vi, this message translates to:
  /// **'Dự đoán thời gian sạc pin'**
  String get aiChargingTimeDesc;

  /// No description provided for @notificationTitle.
  ///
  /// In vi, this message translates to:
  /// **'Thông báo'**
  String get notificationTitle;

  /// No description provided for @notificationEmpty.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có thông báo'**
  String get notificationEmpty;

  /// No description provided for @notificationMarkAllRead.
  ///
  /// In vi, this message translates to:
  /// **'Đánh dấu tất cả đã đọc'**
  String get notificationMarkAllRead;

  /// No description provided for @notificationSettings.
  ///
  /// In vi, this message translates to:
  /// **'Cài đặt thông báo'**
  String get notificationSettings;

  /// No description provided for @actionSave.
  ///
  /// In vi, this message translates to:
  /// **'Lưu'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In vi, this message translates to:
  /// **'Hủy'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In vi, this message translates to:
  /// **'Xóa'**
  String get actionDelete;

  /// No description provided for @actionEdit.
  ///
  /// In vi, this message translates to:
  /// **'Sửa'**
  String get actionEdit;

  /// No description provided for @actionConfirm.
  ///
  /// In vi, this message translates to:
  /// **'Xác nhận'**
  String get actionConfirm;

  /// No description provided for @actionBack.
  ///
  /// In vi, this message translates to:
  /// **'Quay lại'**
  String get actionBack;

  /// No description provided for @actionClose.
  ///
  /// In vi, this message translates to:
  /// **'Đóng'**
  String get actionClose;

  /// No description provided for @actionRetry.
  ///
  /// In vi, this message translates to:
  /// **'Thử lại'**
  String get actionRetry;

  /// No description provided for @actionRefresh.
  ///
  /// In vi, this message translates to:
  /// **'Làm mới'**
  String get actionRefresh;

  /// No description provided for @errorGeneric.
  ///
  /// In vi, this message translates to:
  /// **'Đã xảy ra lỗi'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In vi, this message translates to:
  /// **'Lỗi kết nối mạng'**
  String get errorNetwork;

  /// No description provided for @errorServer.
  ///
  /// In vi, this message translates to:
  /// **'Lỗi máy chủ'**
  String get errorServer;

  /// No description provided for @errorNotFound.
  ///
  /// In vi, this message translates to:
  /// **'Không tìm thấy'**
  String get errorNotFound;

  /// No description provided for @errorUnauthorized.
  ///
  /// In vi, this message translates to:
  /// **'Chưa đăng nhập'**
  String get errorUnauthorized;

  /// No description provided for @loginTitle.
  ///
  /// In vi, this message translates to:
  /// **'Đăng nhập'**
  String get loginTitle;

  /// No description provided for @loginEmail.
  ///
  /// In vi, this message translates to:
  /// **'Email'**
  String get loginEmail;

  /// No description provided for @loginPassword.
  ///
  /// In vi, this message translates to:
  /// **'Mật khẩu'**
  String get loginPassword;

  /// No description provided for @loginButton.
  ///
  /// In vi, this message translates to:
  /// **'Đăng nhập'**
  String get loginButton;

  /// No description provided for @loginGoogle.
  ///
  /// In vi, this message translates to:
  /// **'Đăng nhập với Google'**
  String get loginGoogle;

  /// No description provided for @loginApple.
  ///
  /// In vi, this message translates to:
  /// **'Đăng nhập với Apple'**
  String get loginApple;

  /// No description provided for @loginForgotPassword.
  ///
  /// In vi, this message translates to:
  /// **'Quên mật khẩu?'**
  String get loginForgotPassword;

  /// No description provided for @loginNoAccount.
  ///
  /// In vi, this message translates to:
  /// **'Chưa có tài khoản?'**
  String get loginNoAccount;

  /// No description provided for @loginRegister.
  ///
  /// In vi, this message translates to:
  /// **'Đăng ký'**
  String get loginRegister;

  /// No description provided for @updateAvailable.
  ///
  /// In vi, this message translates to:
  /// **'Có phiên bản mới'**
  String get updateAvailable;

  /// No description provided for @updateRequired.
  ///
  /// In vi, this message translates to:
  /// **'Cần cập nhật'**
  String get updateRequired;

  /// No description provided for @updateDownload.
  ///
  /// In vi, this message translates to:
  /// **'Tải về & Cài đặt'**
  String get updateDownload;

  /// No description provided for @updateLater.
  ///
  /// In vi, this message translates to:
  /// **'Để sau'**
  String get updateLater;

  /// No description provided for @modelUpdated.
  ///
  /// In vi, this message translates to:
  /// **'Model AI đã cập nhật'**
  String get modelUpdated;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In vi, this message translates to:
  /// **'Tải model thất bại'**
  String get modelDownloadFailed;

  /// No description provided for @syncCompleted.
  ///
  /// In vi, this message translates to:
  /// **'Đồng bộ hoàn tất'**
  String get syncCompleted;

  /// No description provided for @syncFailed.
  ///
  /// In vi, this message translates to:
  /// **'Đồng bộ thất bại'**
  String get syncFailed;
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
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
