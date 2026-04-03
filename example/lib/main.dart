import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:webview_windows/webview_windows.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // For full-screen example
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(navigatorKey: navigatorKey, home: ExampleBrowser());
  }
}

class ExampleBrowser extends StatefulWidget {
  @override
  State<ExampleBrowser> createState() => _ExampleBrowser();
}

class _ExampleBrowser extends State<ExampleBrowser> {
  final _controller = WebviewController();
  final _textController = TextEditingController();
  bool _isWebviewSuspended = false;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    // Optionally initialize the webview environment using
    // a custom user data directory
    // and/or a custom browser executable directory
    // and/or custom chromium command line flags
    //await WebviewController.initializeEnvironment(
    //    additionalArguments: '--show-fps-counter');

    try {
      await _controller.initialize();

      Timer.periodic(Duration(seconds: 10), (_) async {
        print(
            'webview process ids: ${await WebviewController.getProcessIds()}');
      });

      _controller.onLoadError.listen(print);
      _controller.loadingState.addListener(() {
        print('Loading state: ${_controller.loadingState.value}');
      });

      _controller.url.addListener(_onUrlChanged);
      _controller.containsFullScreenElement
          .addListener(_onContainsFullScreenElementChanged);

      await _controller.setBackgroundColor(Colors.transparent);

      _controller.setNewWindowRequestedDelegate((url, isUserInitiated) async {
        print('New window requested: $url, isUserInitiated: $isUserInitiated');

        return NewWindowDecision.deny;
      });

      _controller.setNavigationStartingDelegate(
          (url, isUserInitiated, isRedirected) async {
        print('Navigation starting: $url, $isUserInitiated, $isRedirected');

        if (url.contains('test.local')) {
          await _controller.setTransparencyHitTestingEnabled(true);
        } else {
          await _controller.setTransparencyHitTestingEnabled(false);
        }

        return NavigationDecision.navigate;
      });

      final testAssetsPath = p.join(
          Directory(Platform.resolvedExecutable).parent.path, 'test_assets');
      await _controller.addVirtualHostNameMapping(
        'test.local',
        testAssetsPath,
        WebviewHostResourceAccessKind.allow,
      );

      await _controller.setDomainExtraHeaders('*://flutter.dev/*', {
        // 'Accept-Language': 'flutter',
        'X-Custom-Header1': 'example-value',
      });

      await _controller.loadUrl('https://flutter.dev', headers: {
        'X-Custom-Header2': 'example-value',
      });

      if (!mounted) return;
      setState(() {});
    } on PlatformException catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: Text('Error'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Code: ${e.code}'),
                      Text('Message: ${e.message}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      child: Text('Continue'),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                ));
      });
    }
  }

  void _onUrlChanged() {
    _textController.text = _controller.url.value ?? '';
  }

  void _onContainsFullScreenElementChanged() {
    debugPrint(
        'Contains fullscreen element: ${_controller.containsFullScreenElement.value}');
  }

  Widget compositeView() {
    if (!_controller.value.isInitialized) {
      return const Text(
        'Not Initialized',
        style: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              elevation: 0,
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'URL',
                      contentPadding: EdgeInsets.all(10.0),
                    ),
                    textAlignVertical: TextAlignVertical.center,
                    controller: _textController,
                    onSubmitted: (val) {
                      _controller.loadUrl(val);
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh),
                  splashRadius: 20,
                  onPressed: () {
                    _controller.reload();
                  },
                ),
                IconButton(
                  icon: Icon(Icons.developer_mode),
                  tooltip: 'Open DevTools',
                  splashRadius: 20,
                  onPressed: () {
                    _controller.openDevTools();
                  },
                )
              ]),
            ),
            Expanded(
              child: Card(
                color: Colors.transparent,
                elevation: 0,
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: Stack(
                  children: [
                    _buildFlutterContentBehindWebview(),
                    Webview(
                      controller: _controller,
                      permissionRequested: _onPermissionRequested,
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: WebviewSubregion(
                              controller: _controller,
                              subregion: Rect.fromLTWH(20, 80, 100, 100),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          )),
                    ),
                    ValueListenableBuilder<LoadingState>(
                      valueListenable: _controller.loadingState,
                      builder: (context, loadingState, _child) {
                        if (loadingState == LoadingState.loading) {
                          return LinearProgressIndicator();
                        } else {
                          return SizedBox();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  int _flutterClickCount = 0;

  Widget _buildFlutterContentBehindWebview() {
    return Positioned.fill(
      child: Center(child: StatefulBuilder(
        builder: (context, setLocalState) {
          return ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            label: Text(
              _flutterClickCount == 0
                  ? 'Click through transparent area to reach me!'
                  : 'Flutter click #$_flutterClickCount',
              style: TextStyle(fontSize: 16),
            ),
            onPressed: () {
              setLocalState(() => _flutterClickCount++);
            },
          );
        },
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: _isWebviewSuspended ? 'Resume webview' : 'Suspend webview',
        onPressed: () async {
          if (_isWebviewSuspended) {
            await _controller.resume();
          } else {
            await _controller.suspend();
          }
          setState(() {
            _isWebviewSuspended = !_isWebviewSuspended;
          });
        },
        child: Icon(_isWebviewSuspended ? Icons.play_arrow : Icons.pause),
      ),
      appBar: AppBar(
          title: ValueListenableBuilder<String?>(
        valueListenable: _controller.title,
        builder: (context, title, _child) {
          return Text(title ?? 'WebView (Windows) Example');
        },
      )),
      body: Center(
        child: compositeView(),
      ),
    );
  }

  Future<WebviewPermissionDecision> _onPermissionRequested(
      String url, WebviewPermissionKind kind, bool isUserInitiated) async {
    final decision = await showDialog<WebviewPermissionDecision>(
      context: navigatorKey.currentContext!,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('WebView permission requested'),
        content: Text('WebView has requested permission \'$kind\''),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.pop(context, WebviewPermissionDecision.deny),
            child: const Text('Deny'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, WebviewPermissionDecision.allow),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    return decision ?? WebviewPermissionDecision.none;
  }

  @override
  void dispose() {
    _controller.url.removeListener(_onUrlChanged);
    _controller.containsFullScreenElement
        .removeListener(_onContainsFullScreenElementChanged);

    _controller.dispose();

    super.dispose();
  }
}
