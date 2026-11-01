// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '个人日报';

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayTue => '周二';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayThu => '周四';

  @override
  String get weekdayFri => '周五';

  @override
  String get weekdaySat => '周六';

  @override
  String get weekdaySun => '周日';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String unreadCount(int count) {
    return '$count 条未读';
  }

  @override
  String get allRead => '全部已读';

  @override
  String get markAllRead => '全部已读';

  @override
  String get syncNow => '刷新';

  @override
  String get refreshDone => '已同步 · 刚刚';

  @override
  String get offline => '暂时连不上收件服务';

  @override
  String get retry => '重试';

  @override
  String get checkNetwork => '检查网络后再试一次。';

  @override
  String get all => '全部';

  @override
  String get catTech => '科技';

  @override
  String get catMarkets => '财经';

  @override
  String get catWorld => '国际';

  @override
  String get catSociety => '社会';

  @override
  String get catLife => '生活';

  @override
  String get catOther => '其他';

  @override
  String get emptyNoneTitle => '还没有卡片';

  @override
  String get emptyNoneBody => '有新内容时会出现在这里。';

  @override
  String get emptyUnreadTitle => '没有未读卡片了';

  @override
  String get emptyUnreadBody => '这一栏的卡片都读完了。关掉「只看未读」，可以再看一遍。';

  @override
  String get emptyCategoryTitle => '本栏还没有卡片';

  @override
  String get emptyCategoryBody => '有新内容时会出现在这里，或切回「全部」看看其他栏目。';

  @override
  String get showAll => '显示全部';

  @override
  String filterUnread(int count) {
    return '只看未读 · $count';
  }

  @override
  String get groupCountOne => '1 则';

  @override
  String groupCount(int count) {
    return '$count 则';
  }

  @override
  String endEdition(int count) {
    return '本期完 · 共 $count 则';
  }

  @override
  String get unreadOnly => '只看未读';

  @override
  String get unreadNote => '隐藏已经读过的卡片。';

  @override
  String get read => '已读';

  @override
  String minutesRead(int count) {
    return '读 $count 分钟';
  }

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String hoursMinutesAgo(int hours, int minutes) {
    return '$hours 小时 $minutes 分前';
  }

  @override
  String todayAt(String time) {
    return '今天 $time';
  }

  @override
  String yesterdayAt(String time) {
    return '昨天 $time';
  }

  @override
  String get settings => '设置';

  @override
  String get me => '我的';

  @override
  String get reading => '阅读';

  @override
  String get more => '更多';

  @override
  String get accountBack => '返回';

  @override
  String get accountFoot => '已读状态与界面偏好保存在这台设备上。';

  @override
  String get toTop => '回到顶部';

  @override
  String get settingsLabel => '设置与界面语言';

  @override
  String get language => '界面语言';

  @override
  String get languageNote => '卡片正文保持提交时的原文。';

  @override
  String get autoSync => '自动同步';

  @override
  String autoSyncNote(int seconds) {
    return '每 $seconds 秒检查一次新卡片。';
  }

  @override
  String get running => '运行中';

  @override
  String get close => '关闭';

  @override
  String get readProgress => '阅读进度';

  @override
  String get back => '返回信息流';

  @override
  String get markUnread => '标记为未读';

  @override
  String get markedUnread => '已标记为未读';

  @override
  String get deleteCard => '删除卡片';

  @override
  String get deleteTitle => '删除这张卡片？';

  @override
  String get deleteBody => '删除后不会再出现在信息流里，这一步不能撤回。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get deleted => '卡片已删除';

  @override
  String get deleteFailed => '没有删掉，请再试一次';

  @override
  String get sourceNote => '已收录到你的日报';

  @override
  String get openOriginal => '打开原文';

  @override
  String get preferences => '偏好设置';

  @override
  String get preferencesSub => '主题、语言、未读与缓存';

  @override
  String get security => '账号与安全';

  @override
  String get securitySub => '用户名与密码';

  @override
  String get cacheMode => '消息缓存';

  @override
  String get cacheNote => '只影响这台设备上已经拉到的卡片。重装之后，已读和这些卡片不会回来。';

  @override
  String get cache7d => '7 天';

  @override
  String get cache1d => '1 天';

  @override
  String get cacheAfterRead => '阅后即删';

  @override
  String get account => '账号';

  @override
  String get username => '用户名';

  @override
  String get usernameNote => '这是登录名，不能和别人重复，之后可以修改。';

  @override
  String get save => '保存';

  @override
  String get saved => '已保存';

  @override
  String get password => '密码';

  @override
  String get currentPassword => '当前密码';

  @override
  String get newPassword => '新密码';

  @override
  String get passwordNote => '新密码至少 8 个字符。';

  @override
  String get passwordLead => '修改成功后会退出当前登录。';

  @override
  String get passwordPageSub => '核对当前密码后设置新密码';

  @override
  String get passwordHint => '至少 8 个字符。';

  @override
  String get passwordSection => '修改密码';

  @override
  String get bots => 'Bot 与接入';

  @override
  String get botsSub => '已连接的 bot 与接入 token';

  @override
  String get tokenNote => '复制到调用方的请求头里使用。轮换后旧 token 立即失效。';

  @override
  String get statBots => 'Bot';

  @override
  String get statUnread => '未读';

  @override
  String get statCache => '缓存';

  @override
  String get profileEdit => '编辑资料';

  @override
  String get botsEmpty => '还没有出现过的 bot。';

  @override
  String get botsNote => '名称来自提交卡片时填写的 bot。删掉后，下次用同一名称推送会再出现。';

  @override
  String get botProfile => '基本信息';

  @override
  String get botFirstSeen => '首次出现';

  @override
  String get botDesc => '功能介绍';

  @override
  String get botDescEmpty => '还没有功能介绍。下次推送时会写上。';

  @override
  String get botLatest => '近期推送';

  @override
  String get botLatestEmpty => '服务端没有这个 bot 还留着的消息。';

  @override
  String get botDelete => '删除';

  @override
  String get botDeleteTitle => '删除这个 bot？';

  @override
  String get botDeleteBody => '只从列表去掉这个名字。已经收到的卡片还在。下次用同一名称推送时，会再出现在这里。';

  @override
  String get botMissing => '这个 bot 已经不在列表里。';

  @override
  String get botToken => 'Bot token';

  @override
  String get showToken => '显示';

  @override
  String get hideToken => '隐藏';

  @override
  String get copyToken => '复制';

  @override
  String get copyMcpPrompt => '复制 MCP 安装提示词';

  @override
  String mcpPrompt(String url, String token) {
    return '请在你当前使用的客户端里添加下面这个远程 MCP。你能自己添加就自己添加。必须由我手动填写时，把缺的那一项交给我，然后停。不要改服务器，不要自己生成 token，不要在本机另起服务。\n\n这是一个已经在运行的远程 MCP，协议是 Streamable HTTP。不是本地命令，不是 stdio，也不是目录里的插件。\n名称：Proclan。只是客户端里的显示名，服务不校验它。\nURL：$url\n认证：静态请求头。名 Authorization，值 Bearer $token。不是 OAuth。token 只放在这条连接里。\n\n加上之后列出工具，确认只有 submit_cards。每次写卡片先读 submit_cards 的 inputSchema，按当前 schema 填写，不要把字段写进提示词。校验失败就按这份 schema 改完再提交。列表失败时，运行下面的命令重试 initialize，不要改服务器。这个地址没有单独的 SSE 端点，结果是单个 JSON。';
  }

  @override
  String get copied => '已复制';

  @override
  String get rotateToken => '轮换';

  @override
  String get rotateTitle => '轮换 bot token？';

  @override
  String get rotateBody => '轮换后，Grok 里的 Proclan 连接会断开，需要把新 token 重新贴进请求头。';

  @override
  String get rotated => 'token 已轮换';

  @override
  String get privacy => '隐私';

  @override
  String get privacySub => '本地数据与可见范围';

  @override
  String get privacyEmpty => '这里还没有可以调整的项目。';

  @override
  String get privacyText => '你的卡片和已读状态都保存在自己的服务与这台设备上。';

  @override
  String get logout => '退出登录';

  @override
  String get logoutSub => '回到登录页';

  @override
  String get logoutTitle => '退出登录？';

  @override
  String get logoutBody => '这台设备上的卡片还留着。下次登录仍是这个账号。';

  @override
  String get loginSubtitle => '登录后，只看属于你的日报。';

  @override
  String get signIn => '登录';

  @override
  String get pleaseWait => '请稍候';

  @override
  String get createAccount => '注册';

  @override
  String get register => '注册';

  @override
  String get haveAccount => '返回登录';

  @override
  String get needAccount => '创建账号';

  @override
  String get usernamePlaceholder => '1–32 个字符';

  @override
  String get passwordPlaceholder => '至少 8 个字符';

  @override
  String get newPasswordPlaceholder => '设置新密码';

  @override
  String get invalidCredentials => '用户名或密码不对';

  @override
  String get usernameTaken => '这个用户名已经有人使用';

  @override
  String get wrongPassword => '当前密码不对';

  @override
  String get retryLater => '请稍后再试';

  @override
  String get invalidUsername => '用户名需要 1 到 32 个字';

  @override
  String get invalidPassword => '密码需要 8 到 128 个字符';

  @override
  String get authFailed => '没有完成，请再试一次';

  @override
  String get sessionExpired => '登录已失效，请重新登录';

  @override
  String get authHeadline1 => '把信息流，';

  @override
  String get authHeadline2 => '还给自己。';

  @override
  String get authVisualSub => '只读你选的主题，只留下你想记住的。';

  @override
  String get authVisualFoot => '只属于你的日报';

  @override
  String get authFoot => '你的卡片只属于你 · 不上推荐流';

  @override
  String get loginTitle => '欢迎回来';

  @override
  String get registerTitle => '创建账号';

  @override
  String get registerSub => '起一个用户名，建一份只属于你的日报。';

  @override
  String get mastheadNote => '只读你选的主题，只留下你想记住的。';

  @override
  String get appearance => '外观主题';

  @override
  String get appearanceNote => '选择深色或浅色外观，立即生效。';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';
}
