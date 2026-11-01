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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
  /// **'个人日报'**
  String get appTitle;

  /// No description provided for @weekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'周一'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'周二'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'周三'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'周四'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'周五'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'周六'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'周日'**
  String get weekdaySun;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @unreadCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条未读'**
  String unreadCount(int count);

  /// No description provided for @allRead.
  ///
  /// In zh, this message translates to:
  /// **'全部已读'**
  String get allRead;

  /// No description provided for @markAllRead.
  ///
  /// In zh, this message translates to:
  /// **'全部已读'**
  String get markAllRead;

  /// No description provided for @syncNow.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get syncNow;

  /// No description provided for @refreshDone.
  ///
  /// In zh, this message translates to:
  /// **'已同步 · 刚刚'**
  String get refreshDone;

  /// No description provided for @offline.
  ///
  /// In zh, this message translates to:
  /// **'暂时连不上收件服务'**
  String get offline;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @checkNetwork.
  ///
  /// In zh, this message translates to:
  /// **'检查网络后再试一次。'**
  String get checkNetwork;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @catTech.
  ///
  /// In zh, this message translates to:
  /// **'科技'**
  String get catTech;

  /// No description provided for @catMarkets.
  ///
  /// In zh, this message translates to:
  /// **'财经'**
  String get catMarkets;

  /// No description provided for @catWorld.
  ///
  /// In zh, this message translates to:
  /// **'国际'**
  String get catWorld;

  /// No description provided for @catSociety.
  ///
  /// In zh, this message translates to:
  /// **'社会'**
  String get catSociety;

  /// No description provided for @catLife.
  ///
  /// In zh, this message translates to:
  /// **'生活'**
  String get catLife;

  /// No description provided for @catOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get catOther;

  /// No description provided for @emptyNoneTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有卡片'**
  String get emptyNoneTitle;

  /// No description provided for @emptyNoneBody.
  ///
  /// In zh, this message translates to:
  /// **'有新内容时会出现在这里。'**
  String get emptyNoneBody;

  /// No description provided for @emptyUnreadTitle.
  ///
  /// In zh, this message translates to:
  /// **'没有未读卡片了'**
  String get emptyUnreadTitle;

  /// No description provided for @emptyUnreadBody.
  ///
  /// In zh, this message translates to:
  /// **'这一栏的卡片都读完了。关掉「只看未读」，可以再看一遍。'**
  String get emptyUnreadBody;

  /// No description provided for @emptyCategoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'本栏还没有卡片'**
  String get emptyCategoryTitle;

  /// No description provided for @emptyCategoryBody.
  ///
  /// In zh, this message translates to:
  /// **'有新内容时会出现在这里，或切回「全部」看看其他栏目。'**
  String get emptyCategoryBody;

  /// No description provided for @showAll.
  ///
  /// In zh, this message translates to:
  /// **'显示全部'**
  String get showAll;

  /// No description provided for @filterUnread.
  ///
  /// In zh, this message translates to:
  /// **'只看未读 · {count}'**
  String filterUnread(int count);

  /// No description provided for @groupCountOne.
  ///
  /// In zh, this message translates to:
  /// **'1 则'**
  String get groupCountOne;

  /// No description provided for @groupCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 则'**
  String groupCount(int count);

  /// No description provided for @endEdition.
  ///
  /// In zh, this message translates to:
  /// **'本期完 · 共 {count} 则'**
  String endEdition(int count);

  /// No description provided for @unreadOnly.
  ///
  /// In zh, this message translates to:
  /// **'只看未读'**
  String get unreadOnly;

  /// No description provided for @unreadNote.
  ///
  /// In zh, this message translates to:
  /// **'隐藏已经读过的卡片。'**
  String get unreadNote;

  /// No description provided for @read.
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get read;

  /// No description provided for @minutesRead.
  ///
  /// In zh, this message translates to:
  /// **'读 {count} 分钟'**
  String minutesRead(int count);

  /// No description provided for @minutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分钟前'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 小时前'**
  String hoursAgo(int count);

  /// No description provided for @hoursMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时 {minutes} 分前'**
  String hoursMinutesAgo(int hours, int minutes);

  /// No description provided for @todayAt.
  ///
  /// In zh, this message translates to:
  /// **'今天 {time}'**
  String todayAt(String time);

  /// No description provided for @yesterdayAt.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String yesterdayAt(String time);

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @me.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get me;

  /// No description provided for @reading.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get reading;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @accountBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get accountBack;

  /// No description provided for @accountFoot.
  ///
  /// In zh, this message translates to:
  /// **'已读状态与界面偏好保存在这台设备上。'**
  String get accountFoot;

  /// No description provided for @toTop.
  ///
  /// In zh, this message translates to:
  /// **'回到顶部'**
  String get toTop;

  /// No description provided for @settingsLabel.
  ///
  /// In zh, this message translates to:
  /// **'设置与界面语言'**
  String get settingsLabel;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get language;

  /// No description provided for @languageNote.
  ///
  /// In zh, this message translates to:
  /// **'卡片正文保持提交时的原文。'**
  String get languageNote;

  /// No description provided for @autoSync.
  ///
  /// In zh, this message translates to:
  /// **'自动同步'**
  String get autoSync;

  /// No description provided for @autoSyncNote.
  ///
  /// In zh, this message translates to:
  /// **'每 {seconds} 秒检查一次新卡片。'**
  String autoSyncNote(int seconds);

  /// No description provided for @running.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get running;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @readProgress.
  ///
  /// In zh, this message translates to:
  /// **'阅读进度'**
  String get readProgress;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回信息流'**
  String get back;

  /// No description provided for @markUnread.
  ///
  /// In zh, this message translates to:
  /// **'标记为未读'**
  String get markUnread;

  /// No description provided for @markedUnread.
  ///
  /// In zh, this message translates to:
  /// **'已标记为未读'**
  String get markedUnread;

  /// No description provided for @deleteCard.
  ///
  /// In zh, this message translates to:
  /// **'删除卡片'**
  String get deleteCard;

  /// No description provided for @deleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这张卡片？'**
  String get deleteTitle;

  /// No description provided for @deleteBody.
  ///
  /// In zh, this message translates to:
  /// **'删除后不会再出现在信息流里，这一步不能撤回。'**
  String get deleteBody;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @deleted.
  ///
  /// In zh, this message translates to:
  /// **'卡片已删除'**
  String get deleted;

  /// No description provided for @deleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'没有删掉，请再试一次'**
  String get deleteFailed;

  /// No description provided for @sourceNote.
  ///
  /// In zh, this message translates to:
  /// **'已收录到你的日报'**
  String get sourceNote;

  /// No description provided for @openOriginal.
  ///
  /// In zh, this message translates to:
  /// **'打开原文'**
  String get openOriginal;

  /// No description provided for @preferences.
  ///
  /// In zh, this message translates to:
  /// **'偏好设置'**
  String get preferences;

  /// No description provided for @preferencesSub.
  ///
  /// In zh, this message translates to:
  /// **'主题、语言、未读与缓存'**
  String get preferencesSub;

  /// No description provided for @security.
  ///
  /// In zh, this message translates to:
  /// **'账号与安全'**
  String get security;

  /// No description provided for @securitySub.
  ///
  /// In zh, this message translates to:
  /// **'用户名与密码'**
  String get securitySub;

  /// No description provided for @cacheMode.
  ///
  /// In zh, this message translates to:
  /// **'消息缓存'**
  String get cacheMode;

  /// No description provided for @cacheNote.
  ///
  /// In zh, this message translates to:
  /// **'只影响这台设备上已经拉到的卡片。重装之后，已读和这些卡片不会回来。'**
  String get cacheNote;

  /// No description provided for @cache7d.
  ///
  /// In zh, this message translates to:
  /// **'7 天'**
  String get cache7d;

  /// No description provided for @cache1d.
  ///
  /// In zh, this message translates to:
  /// **'1 天'**
  String get cache1d;

  /// No description provided for @cacheAfterRead.
  ///
  /// In zh, this message translates to:
  /// **'阅后即删'**
  String get cacheAfterRead;

  /// No description provided for @account.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get account;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @usernameNote.
  ///
  /// In zh, this message translates to:
  /// **'这是登录名，不能和别人重复，之后可以修改。'**
  String get usernameNote;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get saved;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @currentPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get newPassword;

  /// No description provided for @passwordNote.
  ///
  /// In zh, this message translates to:
  /// **'新密码至少 8 个字符。'**
  String get passwordNote;

  /// No description provided for @passwordLead.
  ///
  /// In zh, this message translates to:
  /// **'修改成功后会退出当前登录。'**
  String get passwordLead;

  /// No description provided for @passwordPageSub.
  ///
  /// In zh, this message translates to:
  /// **'核对当前密码后设置新密码'**
  String get passwordPageSub;

  /// No description provided for @passwordHint.
  ///
  /// In zh, this message translates to:
  /// **'至少 8 个字符。'**
  String get passwordHint;

  /// No description provided for @passwordSection.
  ///
  /// In zh, this message translates to:
  /// **'修改密码'**
  String get passwordSection;

  /// No description provided for @bots.
  ///
  /// In zh, this message translates to:
  /// **'Bot 与接入'**
  String get bots;

  /// No description provided for @botsSub.
  ///
  /// In zh, this message translates to:
  /// **'已连接的 bot 与接入 token'**
  String get botsSub;

  /// No description provided for @tokenNote.
  ///
  /// In zh, this message translates to:
  /// **'复制到调用方的请求头里使用。轮换后旧 token 立即失效。'**
  String get tokenNote;

  /// No description provided for @statBots.
  ///
  /// In zh, this message translates to:
  /// **'Bot'**
  String get statBots;

  /// No description provided for @statUnread.
  ///
  /// In zh, this message translates to:
  /// **'未读'**
  String get statUnread;

  /// No description provided for @statCache.
  ///
  /// In zh, this message translates to:
  /// **'缓存'**
  String get statCache;

  /// No description provided for @profileEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑资料'**
  String get profileEdit;

  /// No description provided for @botsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有出现过的 bot。'**
  String get botsEmpty;

  /// No description provided for @botsNote.
  ///
  /// In zh, this message translates to:
  /// **'名称来自提交卡片时填写的 bot。删掉后，下次用同一名称推送会再出现。'**
  String get botsNote;

  /// No description provided for @botProfile.
  ///
  /// In zh, this message translates to:
  /// **'基本信息'**
  String get botProfile;

  /// No description provided for @botFirstSeen.
  ///
  /// In zh, this message translates to:
  /// **'首次出现'**
  String get botFirstSeen;

  /// No description provided for @botDesc.
  ///
  /// In zh, this message translates to:
  /// **'功能介绍'**
  String get botDesc;

  /// No description provided for @botDescEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有功能介绍。下次推送时会写上。'**
  String get botDescEmpty;

  /// No description provided for @botLatest.
  ///
  /// In zh, this message translates to:
  /// **'近期推送'**
  String get botLatest;

  /// No description provided for @botLatestEmpty.
  ///
  /// In zh, this message translates to:
  /// **'服务端没有这个 bot 还留着的消息。'**
  String get botLatestEmpty;

  /// No description provided for @botDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get botDelete;

  /// No description provided for @botDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这个 bot？'**
  String get botDeleteTitle;

  /// No description provided for @botDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'只从列表去掉这个名字。已经收到的卡片还在。下次用同一名称推送时，会再出现在这里。'**
  String get botDeleteBody;

  /// No description provided for @botMissing.
  ///
  /// In zh, this message translates to:
  /// **'这个 bot 已经不在列表里。'**
  String get botMissing;

  /// No description provided for @botToken.
  ///
  /// In zh, this message translates to:
  /// **'Bot token'**
  String get botToken;

  /// No description provided for @showToken.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get showToken;

  /// No description provided for @hideToken.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get hideToken;

  /// No description provided for @copyToken.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copyToken;

  /// No description provided for @copyMcpPrompt.
  ///
  /// In zh, this message translates to:
  /// **'复制 MCP 安装提示词'**
  String get copyMcpPrompt;

  /// No description provided for @mcpPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请在你当前使用的客户端里添加下面这个远程 MCP。你能自己添加就自己添加。必须由我手动填写时，把缺的那一项交给我，然后停。不要改服务器，不要自己生成 token，不要在本机另起服务。\n\n这是一个已经在运行的远程 MCP，协议是 Streamable HTTP。不是本地命令，不是 stdio，也不是目录里的插件。\n名称：Proclan。只是客户端里的显示名，服务不校验它。\nURL：{url}\n认证：静态请求头。名 Authorization，值 Bearer {token}。不是 OAuth。token 只放在这条连接里。\n\n加上之后列出工具，确认只有 submit_cards。每次写卡片先读 submit_cards 的 inputSchema，按当前 schema 填写，不要把字段写进提示词。校验失败就按这份 schema 改完再提交。列表失败时，运行下面的命令重试 initialize，不要改服务器。这个地址没有单独的 SSE 端点，结果是单个 JSON。'**
  String mcpPrompt(String url, String token);

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get copied;

  /// No description provided for @rotateToken.
  ///
  /// In zh, this message translates to:
  /// **'轮换'**
  String get rotateToken;

  /// No description provided for @rotateTitle.
  ///
  /// In zh, this message translates to:
  /// **'轮换 bot token？'**
  String get rotateTitle;

  /// No description provided for @rotateBody.
  ///
  /// In zh, this message translates to:
  /// **'轮换后，Grok 里的 Proclan 连接会断开，需要把新 token 重新贴进请求头。'**
  String get rotateBody;

  /// No description provided for @rotated.
  ///
  /// In zh, this message translates to:
  /// **'token 已轮换'**
  String get rotated;

  /// No description provided for @privacy.
  ///
  /// In zh, this message translates to:
  /// **'隐私'**
  String get privacy;

  /// No description provided for @privacySub.
  ///
  /// In zh, this message translates to:
  /// **'本地数据与可见范围'**
  String get privacySub;

  /// No description provided for @privacyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这里还没有可以调整的项目。'**
  String get privacyEmpty;

  /// No description provided for @privacyText.
  ///
  /// In zh, this message translates to:
  /// **'你的卡片和已读状态都保存在自己的服务与这台设备上。'**
  String get privacyText;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @logoutSub.
  ///
  /// In zh, this message translates to:
  /// **'回到登录页'**
  String get logoutSub;

  /// No description provided for @logoutTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录？'**
  String get logoutTitle;

  /// No description provided for @logoutBody.
  ///
  /// In zh, this message translates to:
  /// **'这台设备上的卡片还留着。下次登录仍是这个账号。'**
  String get logoutBody;

  /// No description provided for @loginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'登录后，只看属于你的日报。'**
  String get loginSubtitle;

  /// No description provided for @signIn.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get signIn;

  /// No description provided for @pleaseWait.
  ///
  /// In zh, this message translates to:
  /// **'请稍候'**
  String get pleaseWait;

  /// No description provided for @createAccount.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get createAccount;

  /// No description provided for @register.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get register;

  /// No description provided for @haveAccount.
  ///
  /// In zh, this message translates to:
  /// **'返回登录'**
  String get haveAccount;

  /// No description provided for @needAccount.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get needAccount;

  /// No description provided for @usernamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'1–32 个字符'**
  String get usernamePlaceholder;

  /// No description provided for @passwordPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'至少 8 个字符'**
  String get passwordPlaceholder;

  /// No description provided for @newPasswordPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'设置新密码'**
  String get newPasswordPlaceholder;

  /// No description provided for @invalidCredentials.
  ///
  /// In zh, this message translates to:
  /// **'用户名或密码不对'**
  String get invalidCredentials;

  /// No description provided for @usernameTaken.
  ///
  /// In zh, this message translates to:
  /// **'这个用户名已经有人使用'**
  String get usernameTaken;

  /// No description provided for @wrongPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码不对'**
  String get wrongPassword;

  /// No description provided for @retryLater.
  ///
  /// In zh, this message translates to:
  /// **'请稍后再试'**
  String get retryLater;

  /// No description provided for @invalidUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名需要 1 到 32 个字'**
  String get invalidUsername;

  /// No description provided for @invalidPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码需要 8 到 128 个字符'**
  String get invalidPassword;

  /// No description provided for @authFailed.
  ///
  /// In zh, this message translates to:
  /// **'没有完成，请再试一次'**
  String get authFailed;

  /// No description provided for @sessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录已失效，请重新登录'**
  String get sessionExpired;

  /// No description provided for @authHeadline1.
  ///
  /// In zh, this message translates to:
  /// **'把信息流，'**
  String get authHeadline1;

  /// No description provided for @authHeadline2.
  ///
  /// In zh, this message translates to:
  /// **'还给自己。'**
  String get authHeadline2;

  /// No description provided for @authVisualSub.
  ///
  /// In zh, this message translates to:
  /// **'只读你选的主题，只留下你想记住的。'**
  String get authVisualSub;

  /// No description provided for @authVisualFoot.
  ///
  /// In zh, this message translates to:
  /// **'只属于你的日报'**
  String get authVisualFoot;

  /// No description provided for @authFoot.
  ///
  /// In zh, this message translates to:
  /// **'你的卡片只属于你 · 不上推荐流'**
  String get authFoot;

  /// No description provided for @loginTitle.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来'**
  String get loginTitle;

  /// No description provided for @registerTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get registerTitle;

  /// No description provided for @registerSub.
  ///
  /// In zh, this message translates to:
  /// **'起一个用户名，建一份只属于你的日报。'**
  String get registerSub;

  /// No description provided for @mastheadNote.
  ///
  /// In zh, this message translates to:
  /// **'只读你选的主题，只留下你想记住的。'**
  String get mastheadNote;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外观主题'**
  String get appearance;

  /// No description provided for @appearanceNote.
  ///
  /// In zh, this message translates to:
  /// **'选择深色或浅色外观，立即生效。'**
  String get appearanceNote;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;
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
