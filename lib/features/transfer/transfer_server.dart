import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// A file the page may show and download.
class SharedFile {
  const SharedFile({
    required this.path,
    required this.title,
    required this.kind,
    this.thumbnail,
  });

  final String path;

  /// Title of the download the file came from.
  final String title;

  /// `video`, `audio`, `image` or `other`.
  final String kind;

  /// Web address of a picture for the file, when it has one.
  final String? thumbnail;
}

/// The words on the page, so it speaks the app's language.
class TransferTexts {
  const TransferTexts({
    this.rtl = false,
    this.enterCode = 'Enter the code shown on the phone',
    this.open = 'Open',
    this.wrongCode = 'Wrong code. Check the phone and try again.',
    this.locked = 'Too many wrong codes. Restart the transfer on the phone.',
    this.onPhone = 'On the phone',
    this.empty = 'Nothing saved yet.',
    this.download = 'Download',
    this.send = 'Send files to the phone',
    this.sendHint = 'Choose files, or drop them here.',
    this.sent = 'Saved on the phone',
    this.failed = 'Could not be sent',
    this.all = 'All',
    this.videos = 'Videos',
    this.audio = 'Audio',
    this.photos = 'Photos',
  });

  final bool rtl;
  final String enterCode;
  final String open;
  final String wrongCode;
  final String locked;
  final String onPhone;
  final String empty;
  final String download;
  final String send;
  final String sendHint;
  final String sent;
  final String failed;
  final String all;
  final String videos;
  final String audio;
  final String photos;
}

/// Serves the Vault to browsers on the same Wi-Fi: a page that lists the
/// saved files, plays and downloads them, and accepts files sent back.
///
/// Nothing is reachable without the code shown on the phone, and only files
/// handed over by [files] can be read: the page refers to them by number,
/// never by path.
class TransferServer {
  TransferServer({
    required this.files,
    required this.uploadDirectory,
    required this.onUploaded,
    this.texts = const TransferTexts(),
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The files to share, asked for on every page load.
  final List<SharedFile> Function() files;

  /// Where files sent from the browser are written.
  final Future<String> Function() uploadDirectory;

  /// Called with the path of each file that arrived.
  final Future<void> Function(String path) onUploaded;
  final TransferTexts texts;
  final Random _random;

  HttpServer? _server;
  String _code = '';
  final _sessions = <String>{};
  int _wrongCodes = 0;

  // Numbers handed to the page instead of paths; stable for the session.
  final _idOf = <String, int>{};
  final _pathOf = <int, String>{};

  static const _maxWrongCodes = 8;
  static const _cookie = 'savekit';

  /// The four digits the browser has to enter.
  String get code => _code;
  int get port => _server?.port ?? 0;
  bool get running => _server != null;

  /// Starts listening. Tries [preferredPort] first, then any free port.
  Future<void> start({int preferredPort = 8080}) async {
    await stop();
    _code = (_random.nextInt(9000) + 1000).toString();
    _sessions.clear();
    _wrongCodes = 0;
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server = server;
    server.listen((request) {
      _handle(request).catchError((Object _) async {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {
          // The browser went away.
        }
      });
    });
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sessions.clear();
    await server?.close(force: true);
  }

  bool _signedIn(HttpRequest request) => request.cookies.any(
    (cookie) => cookie.name == _cookie && _sessions.contains(cookie.value),
  );

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer');
    final segments = request.uri.pathSegments;
    final first = segments.isEmpty ? '' : segments.first;

    // A scanned QR code carries the code along.
    final offered = request.uri.queryParameters['code'];
    if (first == '' && offered != null && !_signedIn(request)) {
      if (_tryCode(offered, response)) {
        await _redirect(response, '/');
        return;
      }
    }

    if (first == 'enter' && request.method == 'POST') {
      final body = await utf8.decoder.bind(request.take(64)).join();
      final entered = Uri.splitQueryString(body)['code'] ?? '';
      if (_tryCode(entered.trim(), response)) {
        await _redirect(response, '/');
      } else {
        await _html(response, _codePage(wrong: true), HttpStatus.forbidden);
      }
      return;
    }

    if (!_signedIn(request)) {
      if (first == '') {
        await _html(response, _codePage(wrong: false));
      } else {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
      }
      return;
    }

    switch (first) {
      case '':
        await _html(response, _mainPage());
      case 'api' when segments.length == 2 && segments[1] == 'files':
        await _json(response, _listing());
      case 'file' when segments.length == 2:
        await _sendFile(request, int.tryParse(segments[1]));
      case 'upload' when request.method == 'POST':
        await _receive(request);
      default:
        response.statusCode = HttpStatus.notFound;
        await response.close();
    }
  }

  /// Signs the browser in when [entered] is right; false otherwise.
  bool _tryCode(String entered, HttpResponse response) {
    if (_wrongCodes >= _maxWrongCodes) return false;
    if (entered != _code) {
      _wrongCodes++;
      return false;
    }
    final session = List.generate(
      24,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _sessions.add(session);
    response.cookies.add(
      Cookie(_cookie, session)
        ..httpOnly = true
        ..sameSite = SameSite.strict
        ..path = '/',
    );
    return true;
  }

  List<Map<String, Object?>> _listing() {
    final listing = <Map<String, Object?>>[];
    for (final file in files()) {
      final entry = File(file.path);
      if (!entry.existsSync()) continue;
      final id = _idOf.putIfAbsent(file.path, () {
        final next = _idOf.length + 1;
        _pathOf[next] = file.path;
        return next;
      });
      listing.add({
        'id': id,
        'name': p.basename(file.path),
        'title': file.title,
        'kind': file.kind,
        'size': entry.lengthSync(),
        'thumb': file.thumbnail,
      });
    }
    return listing;
  }

  Future<void> _sendFile(HttpRequest request, int? id) async {
    final response = request.response;
    final path = id == null ? null : _pathOf[id];
    final file = path == null ? null : File(path);
    if (file == null || !file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final length = file.lengthSync();
    final name = p.basename(file.path);
    response.headers
      ..contentType = ContentType.parse(_mimeOf(name))
      ..set('Accept-Ranges', 'bytes')
      ..set(
        'Content-Disposition',
        '${request.uri.queryParameters.containsKey('dl') ? 'attachment' : 'inline'}; '
            "filename*=UTF-8''${Uri.encodeComponent(name)}",
      );

    // "bytes=START-END", so videos can be played and skipped through.
    var start = 0;
    var end = length - 1;
    final range = RegExp(r'^bytes=(\d*)-(\d*)$')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range != null && length > 0) {
      final from = int.tryParse(range.group(1)!);
      final to = int.tryParse(range.group(2)!);
      if (from == null && to != null) {
        start = max(0, length - to);
      } else if (from != null) {
        start = from;
        if (to != null) end = min(to, length - 1);
      }
      if (start > end || start >= length) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set('Content-Range', 'bytes */$length');
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set('Content-Range', 'bytes $start-$end/$length');
    }
    response.contentLength = length == 0 ? 0 : end - start + 1;
    if (request.method == 'HEAD' || length == 0) {
      await response.close();
      return;
    }
    await response.addStream(file.openRead(start, end + 1));
    await response.close();
  }

  Future<void> _receive(HttpRequest request) async {
    final response = request.response;
    final name = _safeName(request.uri.queryParameters['name'] ?? '');
    final directory = Directory(await uploadDirectory());
    await directory.create(recursive: true);
    var target = File(p.join(directory.path, name));
    final base = p.basenameWithoutExtension(name);
    final extension = p.extension(name);
    for (var copy = 1; target.existsSync(); copy++) {
      target = File(p.join(directory.path, '$base ($copy)$extension'));
    }
    final part = File('${target.path}.part');
    try {
      await request.cast<List<int>>().pipe(part.openWrite());
      await part.rename(target.path);
    } catch (_) {
      if (part.existsSync()) part.deleteSync();
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
      return;
    }
    await onUploaded(target.path);
    await _json(response, {'ok': true, 'name': p.basename(target.path)});
  }

  /// A file name with nothing that could leave the folder or upset Android.
  static String _safeName(String raw) {
    var name = p.basename(raw.replaceAll('\\', '/'));
    name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_').trim();
    while (name.startsWith('.')) {
      name = name.substring(1);
    }
    if (name.isEmpty) name = 'file';
    if (name.length > 120) {
      final extension = p.extension(name);
      name =
          '${p.basenameWithoutExtension(name).substring(0, 120 - extension.length)}'
          '$extension';
    }
    return name;
  }

  static String _mimeOf(String name) =>
      switch (p.extension(name).toLowerCase()) {
        '.mp4' || '.m4v' => 'video/mp4',
        '.webm' => 'video/webm',
        '.mkv' => 'video/x-matroska',
        '.mov' => 'video/quicktime',
        '.mp3' => 'audio/mpeg',
        '.m4a' => 'audio/mp4',
        '.opus' || '.ogg' => 'audio/ogg',
        '.wav' => 'audio/wav',
        '.flac' => 'audio/flac',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.gif' => 'image/gif',
        '.srt' || '.vtt' || '.txt' => 'text/plain; charset=utf-8',
        _ => 'application/octet-stream',
      };

  Future<void> _redirect(HttpResponse response, String to) async {
    response.statusCode = HttpStatus.seeOther;
    response.headers.set(HttpHeaders.locationHeader, to);
    await response.close();
  }

  Future<void> _html(
    HttpResponse response,
    String page, [
    int status = HttpStatus.ok,
  ]) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.html;
    response.write(page);
    await response.close();
  }

  Future<void> _json(HttpResponse response, Object body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  static const _escape = HtmlEscape();

  String get _head =>
      '<!doctype html><html lang="${texts.rtl ? 'ar' : 'en'}" '
      'dir="${texts.rtl ? 'rtl' : 'ltr'}"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>SaveKit</title><style>$_style</style></head>';

  String _codePage({required bool wrong}) {
    final locked = _wrongCodes >= _maxWrongCodes;
    final note = locked
        ? texts.locked
        : wrong
        ? texts.wrongCode
        : '';
    return '$_head<body><main class="gate"><h1>SaveKit</h1>'
        '<p>${_escape.convert(texts.enterCode)}</p>'
        '<form method="post" action="/enter">'
        '<input name="code" inputmode="numeric" pattern="[0-9]*" maxlength="4" '
        'autocomplete="off" autofocus ${locked ? 'disabled' : ''}>'
        '<button ${locked ? 'disabled' : ''}>${_escape.convert(texts.open)}'
        '</button></form>'
        '<p class="warn">${_escape.convert(note)}</p></main></body></html>';
  }

  String _mainPage() {
    final words = jsonEncode({
      'empty': texts.empty,
      'download': texts.download,
      'sent': texts.sent,
      'failed': texts.failed,
    });
    String tab(String kind, String label) =>
        '<button data-kind="$kind">${_escape.convert(label)}</button>';
    return '$_head<body><main><h1>SaveKit</h1>'
        '<section class="drop" id="drop"><h2>${_escape.convert(texts.send)}</h2>'
        '<p>${_escape.convert(texts.sendHint)}</p>'
        '<input type="file" id="pick" multiple><ul id="sending"></ul></section>'
        '<h2>${_escape.convert(texts.onPhone)}</h2>'
        '<nav id="tabs">${tab('', texts.all)}${tab('video', texts.videos)}'
        '${tab('audio', texts.audio)}${tab('image', texts.photos)}</nav>'
        '<div id="list"></div></main>'
        '<script>const T=$words;$_script</script></body></html>';
  }

  static const _style = '''
:root{color-scheme:dark;--bg:#0f1115;--card:#181b21;--line:#2a2f38;--text:#f2f3f5;--muted:#9aa1ad;--accent:#ff6a2b}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:980px;margin:0 auto;padding:20px 16px 48px}
h1{font-size:24px;margin:8px 0 18px}
h2{font-size:16px;margin:26px 0 10px}
p{color:var(--muted);margin:4px 0 12px}
.gate{max-width:360px;text-align:center;padding-top:14vh}
.gate input{width:100%;font-size:32px;letter-spacing:.4em;text-align:center;padding:12px;border-radius:12px;border:1px solid var(--line);background:var(--card);color:var(--text)}
button{font:inherit;font-weight:700;border:0;border-radius:12px;padding:12px 18px;background:var(--accent);color:#16110d;cursor:pointer}
.gate button{width:100%;margin-top:12px}
button:disabled,input:disabled{opacity:.45;cursor:default}
.warn{color:#ffb86b;min-height:1.5em}
.drop{border:1px dashed var(--line);border-radius:14px;padding:4px 16px 14px;background:var(--card)}
.drop.over{border-color:var(--accent)}
.drop h2{margin-top:14px}
#sending{list-style:none;padding:0;margin:10px 0 0;color:var(--muted);font-size:14px}
#sending li{display:flex;gap:10px;justify-content:space-between;padding:4px 0}
#tabs{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px}
#tabs button{background:var(--card);color:var(--muted);border:1px solid var(--line);padding:8px 14px;font-weight:600}
#tabs button.on{color:var(--text);border-color:var(--accent)}
#list{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:12px}
.item{background:var(--card);border:1px solid var(--line);border-radius:14px;overflow:hidden;display:flex;flex-direction:column}
.item .pic{aspect-ratio:16/9;background:#0b0c0f center/cover no-repeat;display:flex;align-items:center;justify-content:center;color:var(--muted);font-size:13px;text-decoration:none}
.item .body{padding:10px 12px 12px;display:flex;flex-direction:column;gap:6px;flex:1}
.item .title{font-weight:700;font-size:14px;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow-wrap:anywhere}
.item .meta{color:var(--muted);font-size:12.5px;overflow-wrap:anywhere}
.item a.get{margin-top:auto;text-align:center;text-decoration:none;background:var(--accent);color:#16110d;font-weight:700;border-radius:10px;padding:8px}
''';

  static const _script = r'''
const size=b=>{const u=['B','KB','MB','GB'];let i=0;while(b>=1024&&i<3){b/=1024;i++}return(i&&b<100?b.toFixed(1):Math.round(b))+' '+u[i]};
const el=(t,c,x)=>{const e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e};
let all=[],kind='';
function draw(){
  const list=document.getElementById('list');list.textContent='';
  const shown=all.filter(f=>!kind||f.kind===kind);
  if(!shown.length){list.append(el('p','',T.empty));return}
  for(const f of shown){
    const item=el('div','item');
    const pic=el('a','pic',f.thumb||f.kind==='image'?'':f.kind.toUpperCase());
    pic.href='/file/'+f.id;pic.target='_blank';
    const art=f.kind==='image'?'/file/'+f.id:f.thumb;
    if(art)pic.style.backgroundImage='url("'+encodeURI(art)+'")';
    const body=el('div','body');
    body.append(el('div','title',f.title||f.name),el('div','meta',f.name+' · '+size(f.size)));
    const get=el('a','get',T.download);get.href='/file/'+f.id+'?dl';
    body.append(get);item.append(pic,body);list.append(item);
  }
}
async function load(){all=await(await fetch('/api/files')).json();draw()}
document.querySelectorAll('#tabs button').forEach(b=>{
  if(!b.dataset.kind)b.classList.add('on');
  b.onclick=()=>{kind=b.dataset.kind;document.querySelectorAll('#tabs button').forEach(o=>o.classList.toggle('on',o===b));draw()};
});
function send(file){
  const row=el('li'),state=el('span','','0%');row.append(el('span','',file.name),state);
  document.getElementById('sending').append(row);
  return new Promise(done=>{
    const x=new XMLHttpRequest();
    x.open('POST','/upload?name='+encodeURIComponent(file.name));
    x.upload.onprogress=e=>{if(e.lengthComputable)state.textContent=Math.round(e.loaded/e.total*100)+'%'};
    x.onload=()=>{state.textContent=x.status===200?T.sent:T.failed;done()};
    x.onerror=()=>{state.textContent=T.failed;done()};
    x.send(file);
  });
}
async function sendAll(files){for(const f of files)await send(f);load()}
const pick=document.getElementById('pick'),drop=document.getElementById('drop');
pick.onchange=()=>{sendAll([...pick.files]);pick.value=''};
drop.ondragover=e=>{e.preventDefault();drop.classList.add('over')};
drop.ondragleave=()=>drop.classList.remove('over');
drop.ondrop=e=>{e.preventDefault();drop.classList.remove('over');sendAll([...e.dataTransfer.files])};
load();
''';
}

/// The phone's addresses on the local network, most likely Wi-Fi first.
Future<List<String>> localAddresses() async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  } catch (_) {
    return const [];
  }
  bool private(String address) =>
      address.startsWith('192.168.') ||
      address.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(address);
  // Wi-Fi and hotspot interfaces before mobile data and VPNs.
  int rank(String name) =>
      name.startsWith('wlan') || name.startsWith('swlan') || name == 'ap0'
      ? 0
      : 1;
  final found = <(int, String)>[
    for (final interface in interfaces)
      for (final address in interface.addresses)
        if (!address.isLoopback && private(address.address))
          (rank(interface.name), address.address),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final entry in found) entry.$2];
}
