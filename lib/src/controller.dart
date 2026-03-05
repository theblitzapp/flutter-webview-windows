import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/src/models/cross_origin_request.dart';
import 'package:webview_windows/src/models/pointer.dart';
import 'package:webview_windows/src/models/download_event.dart';
import 'package:webview_windows/src/models/error_status.dart';
import 'package:webview_windows/src/models/history_changed.dart';
import 'package:webview_windows/src/models/loading_state.dart';
import 'package:webview_windows/src/models/permissions.dart';
import 'package:webview_windows/src/models/popup_policy.dart';
import 'package:webview_windows/src/models/script_id.dart';

import 'cursor.dart';

@immutable
class WebviewValue {
  @internal
  const WebviewValue({
    required this.isInitialized,
  });

  @internal
  WebviewValue.uninitialized() : this(isInitialized: false);

  final bool isInitialized;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WebviewValue && other.isInitialized == isInitialized;
  }

  @override
  int get hashCode => isInitialized.hashCode;
}

/// Controls a WebView and provides streams for various change events.
class WebviewController extends ValueNotifier<WebviewValue> {
  static const String _pluginChannelPrefix = 'io.jns.webview.win';
  static const MethodChannel _pluginChannel =
      MethodChannel(_pluginChannelPrefix);

  /// Explicitly initializes the underlying WebView environment
  /// using  an optional [browserExePath], an optional [userDataPath]
  /// and optional Chromium command line arguments [additionalArguments].
  ///
  /// The environment is shared between all WebviewController instances and
  /// can be initialized only once. Initialization must take place before any
  /// WebviewController is created/initialized.
  ///
  /// Throws [PlatformException] if the environment was initialized before.
  static Future<void> initializeEnvironment(
      {String? userDataPath,
      String? browserExePath,
      String? additionalArguments}) async {
    return _pluginChannel
        .invokeMethod('initializeEnvironment', <String, Object?>{
      'userDataPath': userDataPath,
      'browserExePath': browserExePath,
      'additionalArguments': additionalArguments
    });
  }

  /// Get the browser version info including channel name if it is not the
  /// WebView2 Runtime.
  /// Returns [null] if the webview2 runtime is not installed.
  static Future<String?> getWebViewVersion() async {
    return _pluginChannel.invokeMethod<String>('getWebViewVersion');
  }

  WebviewController() : super(WebviewValue.uninitialized());

  late Completer<void> _creatingCompleter;
  bool _isDisposed = false;

  bool get isReady => _creatingCompleter.isCompleted;
  Future<void> get ready => _creatingCompleter.future;

  PermissionRequestedDelegate? _permissionRequested;

  late MethodChannel _methodChannel;
  late EventChannel _eventChannel;
  StreamSubscription? _eventStreamSubscription;

  int _textureId = 0;

  /// The texture ID that was assigned to the webview surface by Flutter.
  int get textureId => _textureId;

  final StreamController<String> _urlStreamController =
      StreamController<String>();

  /// A stream reflecting the current URL.
  Stream<String> get url => _urlStreamController.stream;

  final StreamController<LoadingState> _loadingStateStreamController =
      StreamController<LoadingState>.broadcast();

  final StreamController<WebviewDownloadEvent> _downloadEventStreamController =
      StreamController<WebviewDownloadEvent>.broadcast();

  final StreamController<WebErrorStatus> _onLoadErrorStreamController =
      StreamController<WebErrorStatus>();

  /// A stream reflecting the current loading state.
  Stream<LoadingState> get loadingState => _loadingStateStreamController.stream;

  Stream<WebviewDownloadEvent> get onDownloadEvent =>
      _downloadEventStreamController.stream;

  /// A stream reflecting the navigation error when navigation completed with an error.
  Stream<WebErrorStatus> get onLoadError => _onLoadErrorStreamController.stream;

  final StreamController<HistoryChanged> _historyChangedStreamController =
      StreamController<HistoryChanged>();

  /// A stream reflecting the current history state.
  Stream<HistoryChanged> get historyChanged =>
      _historyChangedStreamController.stream;

  final StreamController<String> _securityStateChangedStreamController =
      StreamController<String>();

  /// A stream reflecting the current security state.
  Stream<String> get securityStateChanged =>
      _securityStateChangedStreamController.stream;

  final StreamController<String> _titleStreamController =
      StreamController<String>();

  /// A stream reflecting the current document title.
  Stream<String> get title => _titleStreamController.stream;

  final StreamController<SystemMouseCursor> _cursorStreamController =
      StreamController<SystemMouseCursor>.broadcast();

  /// A stream reflecting the current cursor style.
  Stream<SystemMouseCursor> get cursor => _cursorStreamController.stream;

  final StreamController<dynamic> _webMessageStreamController =
      StreamController<dynamic>();

  Stream<dynamic> get webMessage => _webMessageStreamController.stream;

  final StreamController<bool>
      _containsFullScreenElementChangedStreamController =
      StreamController<bool>.broadcast();

  /// A stream reflecting whether the document currently contains full-screen elements.
  Stream<bool> get containsFullScreenElementChanged =>
      _containsFullScreenElementChangedStreamController.stream;

  /// Initializes the underlying platform view.
  Future<void> initialize() async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    _creatingCompleter = Completer<void>();
    try {
      final reply =
          await _pluginChannel.invokeMapMethod<String, Object?>('initialize');

      if (reply == null) {
        throw PlatformException(
          code: 'initialize_failed',
          message: 'Unexpected response from the plugin',
        );
      }

      _textureId = reply['textureId'] as int;
      _methodChannel = MethodChannel('$_pluginChannelPrefix/$_textureId');
      _eventChannel = EventChannel('$_pluginChannelPrefix/$_textureId/events');

      _eventStreamSubscription =
          _eventChannel.receiveBroadcastStream().listen((event) {
        final map = event as Map<dynamic, dynamic>;

        switch (map['type']) {
          case 'urlChanged':
            _urlStreamController.add(map['value']);
            break;

          case 'onLoadError':
            _onLoadErrorStreamController.add(
              WebErrorStatus.values[map['value']],
            );

            break;

          case 'loadingStateChanged':
            _loadingStateStreamController.add(
              LoadingState.values[map['value']],
            );

            break;

          case 'downloadEvent':
            _downloadEventStreamController.add(
              WebviewDownloadEvent(
                WebviewDownloadEventKind.values[map['value']['kind']],
                map['value']['url'],
                map['value']['resultFilePath'],
                map['value']['bytesReceived'],
                map['value']['totalBytesToReceive'],
              ),
            );

            break;

          case 'historyChanged':
            _historyChangedStreamController.add(
              HistoryChanged(
                canGoBack: map['value']['canGoBack'],
                canGoForward: map['value']['canGoForward'],
              ),
            );

            break;

          case 'securityStateChanged':
            _securityStateChangedStreamController.add(
              map['value'],
            );
            break;

          case 'titleChanged':
            _titleStreamController.add(
              map['value'],
            );
            break;

          case 'cursorChanged':
            _cursorStreamController.add(
              getCursorByName(map['value']),
            );
            break;

          case 'webMessageReceived':
            try {
              final message = json.decode(map['value']);

              _webMessageStreamController.add(message);
            } catch (ex) {
              _webMessageStreamController.addError(ex);
            }

            break;

          case 'containsFullScreenElementChanged':
            _containsFullScreenElementChangedStreamController.add(
              map['value'],
            );

            break;
        }
      });

      _methodChannel.setMethodCallHandler((call) {
        if (call.method == 'permissionRequested') {
          return _onPermissionRequested(
              call.arguments as Map<dynamic, dynamic>);
        }

        throw MissingPluginException('Unknown method ${call.method}');
      });

      value = WebviewValue(isInitialized: true);

      _creatingCompleter.complete();
    } on PlatformException catch (e) {
      _creatingCompleter.completeError(e);
    }

    return _creatingCompleter.future;
  }

  @internal
  void setPermissionRequestedDelegate(
    PermissionRequestedDelegate? permissionRequested,
  ) {
    _permissionRequested = permissionRequested;
  }

  Future<bool?> _onPermissionRequested(Map<dynamic, dynamic> args) async {
    final permissionRequested = _permissionRequested;

    if (permissionRequested == null) {
      return null;
    }

    final url = args['url'] as String?;
    final permissionKindIndex = args['permissionKind'] as int?;
    final isUserInitiated = args['isUserInitiated'] as bool?;

    if (url != null && permissionKindIndex != null && isUserInitiated != null) {
      final permissionKind = WebviewPermissionKind.values[permissionKindIndex];
      final decision =
          await permissionRequested(url, permissionKind, isUserInitiated);

      switch (decision) {
        case WebviewPermissionDecision.allow:
          return true;

        case WebviewPermissionDecision.deny:
          return false;

        default:
          return null;
      }
    }

    return null;
  }

  @override
  Future<void> dispose() async {
    await _creatingCompleter.future;

    if (!_isDisposed) {
      _isDisposed = true;
      await _eventStreamSubscription?.cancel();
      await _pluginChannel.invokeMethod('dispose', _textureId);
    }

    super.dispose();
  }

  /// Loads the given [url].
  Future<void> loadUrl(String url) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('loadUrl', url);
  }

  /// Loads a document from the given string.
  Future<void> loadStringContent(String content) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('loadStringContent', content);
  }

  /// Reloads the current document.
  Future<void> reload() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('reload');
  }

  /// Stops all navigations and pending resource fetches.
  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('stop');
  }

  /// Navigates the WebView to the previous page in the navigation history.
  Future<void> goBack() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('goBack');
  }

  /// Navigates the WebView to the next page in the navigation history.
  Future<void> goForward() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('goForward');
  }

  /// Adds the provided JavaScript [script] to a list of scripts that should be run after the global
  /// object has been created, but before the HTML document has been parsed and before any
  /// other script included by the HTML document is run.
  ///
  /// Returns a [ScriptID] on success which can be used for [removeScriptToExecuteOnDocumentCreated].
  ///
  /// see https://docs.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2?view=webview2-1.0.1264.42#addscripttoexecuteondocumentcreated
  Future<ScriptID?> addScriptToExecuteOnDocumentCreated(String script) async {
    if (_isDisposed) {
      return null;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod<String?>(
        'addScriptToExecuteOnDocumentCreated', script);
  }

  /// Removes the script identified by [scriptId] from the list of registered scripts.
  ///
  /// see https://docs.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2?view=webview2-1.0.1264.42#removescripttoexecuteondocumentcreated
  Future<void> removeScriptToExecuteOnDocumentCreated(ScriptID scriptId) async {
    if (_isDisposed) {
      return null;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod(
        'removeScriptToExecuteOnDocumentCreated', scriptId);
  }

  /// Runs the JavaScript [script] in the current top-level document rendered in
  /// the WebView and returns its result.
  ///
  /// see https://docs.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2?view=webview2-1.0.1264.42#executescript
  Future<dynamic> executeScript(String script) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    final data = await _methodChannel.invokeMethod('executeScript', script);

    if (data == null) {
      return null;
    }

    return jsonDecode(data as String);
  }

  /// Posts the given JSON-formatted message to the current document.
  Future<void> postWebMessage(String message) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('postWebMessage', message);
  }

  /// Sets the user agent value.
  Future<void> setUserAgent(String userAgent) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('setUserAgent', userAgent);
  }

  /// Clears browser cookies.
  Future<void> clearCookies() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('clearCookies');
  }

  /// Clears browser cache.
  Future<void> clearCache() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('clearCache');
  }

  /// Toggles ignoring cache for each request. If true, cache will not be used.
  Future<void> setCacheDisabled(bool disabled) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('setCacheDisabled', disabled);
  }

  /// Opens the Browser DevTools in a separate window
  Future<void> openDevTools() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('openDevTools');
  }

  /// Sets the background color to the provided [color].
  ///
  /// Due to a limitation of the underlying WebView implementation,
  /// semi-transparent values are not supported.
  /// Any non-zero alpha value will be considered as opaque (0xff).
  Future<void> setBackgroundColor(Color color) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod(
        'setBackgroundColor', color.toARGB32().toSigned(32));
  }

  /// Sets the zoom factor.
  Future<void> setZoomFactor(double zoomFactor) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('setZoomFactor', zoomFactor);
  }

  /// Sets the [WebviewPopupWindowPolicy].
  Future<void> setPopupWindowPolicy(
    WebviewPopupWindowPolicy popupPolicy,
  ) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod(
        'setPopupWindowPolicy', popupPolicy.index);
  }

  /// Suspends the web view.
  Future<void> suspend() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('suspend');
  }

  /// Resumes the web view.
  Future<void> resume() async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('resume');
  }

  /// Adds a Virtual Host Name Mapping.
  ///
  /// Please refer to
  /// [Microsofts](https://docs.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2_3#setvirtualhostnametofoldermapping)
  /// documentation for more details.
  Future<void> addVirtualHostNameMapping(
    String hostName,
    String folderPath,
    WebviewHostResourceAccessKind accessKind,
  ) async {
    if (_isDisposed) {
      return;
    }

    return _methodChannel.invokeMethod(
        'setVirtualHostNameMapping', [hostName, folderPath, accessKind.index]);
  }

  /// Removes a Virtual Host Name Mapping.
  ///
  /// Please refer to
  /// [Microsofts](https://docs.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2_3#clearvirtualhostnametofoldermapping)
  /// documentation for more details.
  Future<void> removeVirtualHostNameMapping(String hostName) async {
    if (_isDisposed) {
      return;
    }

    return _methodChannel.invokeMethod('clearVirtualHostNameMapping', hostName);
  }

  /// Limits the number of frames per second to the given value.
  Future<void> setFpsLimit([int? maxFps = 0]) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('setFpsLimit', maxFps);
  }

  /// Sends a Pointer (Touch) update
  @internal
  Future<void> setPointerUpdate(
    WebviewPointerEventKind kind,
    int pointer,
    Offset position,
    double size,
    double pressure,
  ) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('setPointerUpdate',
        [pointer, kind.index, position.dx, position.dy, size, pressure]);
  }

  /// Moves the virtual cursor to [position].
  @internal
  Future<void> setCursorPos(Offset position) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel
        .invokeMethod('setCursorPos', [position.dx, position.dy]);
  }

  /// Indicates whether the specified [button] is currently down.
  @internal
  Future<void> setPointerButtonState(PointerButton button, bool isDown) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('setPointerButton',
        <String, dynamic>{'button': button.index, 'isDown': isDown});
  }

  /// Sets the horizontal and vertical scroll delta.
  @internal
  Future<void> setScrollDelta(double dx, double dy) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel.invokeMethod('setScrollDelta', [dx, dy]);
  }

  /// Sets the surface size to the provided [size].
  @internal
  Future<void> setSize(Size size, double scaleFactor) async {
    if (_isDisposed) {
      return;
    }

    assert(value.isInitialized);

    return _methodChannel
        .invokeMethod('setSize', [size.width, size.height, scaleFactor]);
  }
}
