// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Personal Daily';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String unreadCount(int count) {
    return '$count unread';
  }

  @override
  String get allRead => 'All read';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get syncNow => 'Refresh';

  @override
  String get refreshDone => 'Synced just now';

  @override
  String get offline => 'Can\'t reach the inbox';

  @override
  String get retry => 'Retry';

  @override
  String get checkNetwork => 'Check the network and try again.';

  @override
  String get all => 'All';

  @override
  String get catTech => 'Tech';

  @override
  String get catMarkets => 'Markets';

  @override
  String get catWorld => 'World';

  @override
  String get catSociety => 'Society';

  @override
  String get catLife => 'Life';

  @override
  String get catOther => 'Other';

  @override
  String get emptyNoneTitle => 'No cards yet';

  @override
  String get emptyNoneBody => 'New stories will appear here.';

  @override
  String get emptyUnreadTitle => 'Nothing unread left';

  @override
  String get emptyUnreadBody =>
      'You have read every card in this view. Turn off unread only to read them again.';

  @override
  String get emptyCategoryTitle => 'No cards here yet';

  @override
  String get emptyCategoryBody =>
      'New stories will appear here. Try another category in the meantime.';

  @override
  String get showAll => 'Show all';

  @override
  String filterUnread(int count) {
    return 'Unread only · $count';
  }

  @override
  String get groupCountOne => '1 story';

  @override
  String groupCount(int count) {
    return '$count stories';
  }

  @override
  String endEdition(int count) {
    return 'End of edition · $count cards';
  }

  @override
  String get unreadOnly => 'Unread only';

  @override
  String get unreadNote => 'Hide cards you have already read.';

  @override
  String get read => 'Read';

  @override
  String minutesRead(int count) {
    return '$count min read';
  }

  @override
  String minutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String hoursMinutesAgo(int hours, int minutes) {
    return '${hours}h ${minutes}m ago';
  }

  @override
  String todayAt(String time) {
    return 'Today $time';
  }

  @override
  String yesterdayAt(String time) {
    return 'Yesterday $time';
  }

  @override
  String get settings => 'Settings';

  @override
  String get me => 'Me';

  @override
  String get reading => 'Reading';

  @override
  String get more => 'More';

  @override
  String get accountBack => 'Back';

  @override
  String get accountFoot =>
      'Read state and interface preferences stay on this device.';

  @override
  String get toTop => 'Back to top';

  @override
  String get settingsLabel => 'Settings and language';

  @override
  String get language => 'Language';

  @override
  String get languageNote =>
      'Card text stays in the language it was submitted in.';

  @override
  String get autoSync => 'Auto sync';

  @override
  String autoSyncNote(int seconds) {
    return 'Checks for new cards every $seconds seconds.';
  }

  @override
  String get running => 'Active';

  @override
  String get close => 'Close';

  @override
  String get readProgress => 'Reading progress';

  @override
  String get back => 'Back to feed';

  @override
  String get markUnread => 'Mark as unread';

  @override
  String get markedUnread => 'Marked as unread';

  @override
  String get deleteCard => 'Delete card';

  @override
  String get deleteTitle => 'Delete this card?';

  @override
  String get deleteBody =>
      'It will disappear from the feed. This cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get deleted => 'Card deleted';

  @override
  String get deleteFailed => 'Couldn\'t delete it. Try again.';

  @override
  String get sourceNote => 'Saved to your daily';

  @override
  String get openOriginal => 'Open source';

  @override
  String get preferences => 'Preferences';

  @override
  String get preferencesSub => 'Theme, language, unread, and cache';

  @override
  String get security => 'Account and security';

  @override
  String get securitySub => 'Username and password';

  @override
  String get cacheMode => 'Message cache';

  @override
  String get cacheNote =>
      'Applies only to cards already on this device. A reinstall does not bring read state or those cards back.';

  @override
  String get cache7d => '7 days';

  @override
  String get cache1d => '1 day';

  @override
  String get cacheAfterRead => 'After reading';

  @override
  String get account => 'Account';

  @override
  String get username => 'Username';

  @override
  String get usernameNote =>
      'This is your login name. It must be unique, and you can change it later.';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get password => 'Password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get passwordNote => 'New password must be at least 8 characters.';

  @override
  String get passwordLead => 'You are signed out when it succeeds.';

  @override
  String get passwordPageSub =>
      'Confirm your current password, then set a new one';

  @override
  String get passwordHint => 'At least 8 characters.';

  @override
  String get passwordSection => 'Change password';

  @override
  String get bots => 'Bots and access';

  @override
  String get botsSub => 'Connected bots and the access token';

  @override
  String get tokenNote =>
      'Paste it into the caller\'s header. The old token stops working when you rotate it.';

  @override
  String get statBots => 'Bots';

  @override
  String get statUnread => 'Unread';

  @override
  String get statCache => 'Cache';

  @override
  String get profileEdit => 'Edit';

  @override
  String get botsEmpty => 'No bots yet.';

  @override
  String get botsNote =>
      'Names come from the bot field on submitted cards. Delete one, and the same name returns on the next push.';

  @override
  String get botProfile => 'Basics';

  @override
  String get botFirstSeen => 'First seen';

  @override
  String get botDesc => 'What it does';

  @override
  String get botDescEmpty =>
      'No introduction yet. It arrives on the next push.';

  @override
  String get botLatest => 'Recent pushes';

  @override
  String get botLatestEmpty =>
      'No message from this bot is still on the server.';

  @override
  String get botDelete => 'Delete';

  @override
  String get botDeleteTitle => 'Delete this bot?';

  @override
  String get botDeleteBody =>
      'This only removes the name from the list. Cards you already have stay. The same name comes back the next time it pushes.';

  @override
  String get botMissing => 'This bot is no longer in the list.';

  @override
  String get botToken => 'Bot token';

  @override
  String get showToken => 'Show';

  @override
  String get hideToken => 'Hide';

  @override
  String get copyToken => 'Copy';

  @override
  String get copyMcpPrompt => 'Copy MCP install prompt';

  @override
  String mcpPrompt(String url, String token) {
    return 'Add the remote MCP server below in the client you are using. Add it yourself if you can. If I have to fill something in by hand, hand me that item and stop. Do not change the server, do not generate a token, and do not start another service locally.\n\nThis is a remote MCP that is already running, over Streamable HTTP. It is not a local command, not stdio, and not a catalog plugin.\nName: Proclan. That is only a label in the client. The server does not check it.\nURL: $url\nAuth: a static request header. Name Authorization, value Bearer $token. Not OAuth. Keep the token only on this connection.\n\nAfter it is connected, list the tools and confirm the only one is submit_cards. Each time you write cards, read the inputSchema of submit_cards and fill that schema. Do not copy the fields into your prompt. If a call is rejected, fix it against that schema and submit again. If listing fails, run the command below to retry initialize. Do not change the server. This URL has no separate SSE endpoint. The result is one JSON body.';
  }

  @override
  String get copied => 'Copied';

  @override
  String get rotateToken => 'Rotate';

  @override
  String get rotateTitle => 'Rotate the bot token?';

  @override
  String get rotateBody =>
      'The Proclan connection in Grok stops working until you paste the new token into its header.';

  @override
  String get rotated => 'Token rotated';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacySub => 'Local data and visibility';

  @override
  String get privacyEmpty => 'Nothing to change here yet.';

  @override
  String get privacyText =>
      'Your cards and read state stay on your server and this device.';

  @override
  String get logout => 'Log out';

  @override
  String get logoutSub => 'Return to sign in';

  @override
  String get logoutTitle => 'Log out?';

  @override
  String get logoutBody =>
      'Cards stay on this device. You can sign in again with this account.';

  @override
  String get loginSubtitle => 'Sign in to read your own daily.';

  @override
  String get signIn => 'Log in';

  @override
  String get pleaseWait => 'Please wait';

  @override
  String get createAccount => 'Create account';

  @override
  String get register => 'Register';

  @override
  String get haveAccount => 'Back to sign in';

  @override
  String get needAccount => 'Create account';

  @override
  String get usernamePlaceholder => '1–32 characters';

  @override
  String get passwordPlaceholder => 'At least 8 characters';

  @override
  String get newPasswordPlaceholder => 'Set a new password';

  @override
  String get invalidCredentials => 'Username or password is wrong';

  @override
  String get usernameTaken => 'That username is already taken';

  @override
  String get wrongPassword => 'Current password is wrong';

  @override
  String get retryLater => 'Try again later';

  @override
  String get invalidUsername => 'Username must be 1–32 characters';

  @override
  String get invalidPassword => 'Password must be 8–128 characters';

  @override
  String get authFailed => 'That didn\'t work. Try again.';

  @override
  String get sessionExpired => 'Session expired. Sign in again.';

  @override
  String get authHeadline1 => 'Your feed.';

  @override
  String get authHeadline2 => 'Your rules.';

  @override
  String get authVisualSub =>
      'Only what you chose. Only what you want to keep.';

  @override
  String get authVisualFoot => 'A daily edition of your own';

  @override
  String get authFoot => 'Your cards belong to you · no recommendation feed';

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerSub =>
      'Pick a username and build a daily that belongs only to you.';

  @override
  String get mastheadNote => 'Only what you chose. Only what you want to keep.';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceNote =>
      'Choose a dark or light appearance. It applies immediately.';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';
}
