import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_windows/src/controller.dart';
import 'package:webview_windows/src/models/pointer.dart';
import 'package:webview_windows/src/models/permissions.dart';
import 'package:webview_windows/src/rendering/render_webview.dart';

class Webview extends StatefulWidget {
  final WebviewController controller;
  final PermissionRequestedDelegate? permissionRequested;
  final double? width;
  final double? height;

  /// An optional scale factor. Defaults to [FlutterView.devicePixelRatio] for
  /// rendering in native resolution.
  /// Setting this to 1.0 will disable high-DPI support.
  /// This should only be needed to mimic old behavior before high-DPI support
  /// was available.
  final double? scaleFactor;

  /// The [FilterQuality] used for scaling the texture's contents.
  /// Defaults to [FilterQuality.none] as this renders in native resolution
  /// unless specifying a [scaleFactor].
  final FilterQuality filterQuality;

  const Webview({
    Key? key,
    required this.controller,
    this.width,
    this.height,
    this.permissionRequested,
    this.scaleFactor,
    this.filterQuality = FilterQuality.none,
  }) : super(key: key);

  @override
  _WebviewState createState() => _WebviewState();
}

class _WebviewState extends State<Webview> {
  final _downButtons = <int, PointerButton>{};

  PointerDeviceKind _pointerKind = PointerDeviceKind.unknown;

  WebviewController get _controller => widget.controller;

  int _updateSizeRequestId = 0;

  @override
  void initState() {
    super.initState();

    // TODO: Refactor callback and event handling and
    // remove this line
    _controller.setPermissionRequestedDelegate(widget.permissionRequested);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        child: _buildInner());
  }

  Widget _buildInner() {
    if (!_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Listener(
        onPointerHover: (ev) {
          // ev.kind is for whatever reason not set to touch
          // even on touch input
          if (_pointerKind == PointerDeviceKind.touch) {
            // Ignoring hover events on touch for now
            return;
          }
          _controller.setCursorPos(ev.localPosition);
        },
        onPointerDown: (ev) {
          _pointerKind = ev.kind;
          if (ev.kind == PointerDeviceKind.touch) {
            _controller.setPointerUpdate(WebviewPointerEventKind.down,
                ev.pointer, ev.localPosition, ev.size, ev.pressure);
            return;
          }
          final button = PointerButton.fromValue(ev.buttons);
          _downButtons[ev.pointer] = button;
          _controller.setPointerButtonState(button, true);
        },
        onPointerUp: (ev) {
          _pointerKind = ev.kind;
          if (ev.kind == PointerDeviceKind.touch) {
            _controller.setPointerUpdate(WebviewPointerEventKind.up, ev.pointer,
                ev.localPosition, ev.size, ev.pressure);
            return;
          }
          final button = _downButtons.remove(ev.pointer);
          if (button != null) {
            _controller.setPointerButtonState(button, false);
          }
        },
        onPointerCancel: (ev) {
          _pointerKind = ev.kind;
          final button = _downButtons.remove(ev.pointer);
          if (button != null) {
            _controller.setPointerButtonState(button, false);
          }
        },
        onPointerMove: (ev) {
          _pointerKind = ev.kind;
          if (ev.kind == PointerDeviceKind.touch) {
            _controller.setPointerUpdate(WebviewPointerEventKind.update,
                ev.pointer, ev.localPosition, ev.size, ev.pressure);
          } else {
            _controller.setCursorPos(ev.localPosition);
          }
        },
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            _controller.setScrollDelta(
                -signal.scrollDelta.dx, -signal.scrollDelta.dy);
          }
        },
        onPointerPanZoomUpdate: (signal) {
          if (signal.panDelta.dx.abs() > signal.panDelta.dy.abs()) {
            _controller.setScrollDelta(-signal.panDelta.dx, 0);
          } else {
            _controller.setScrollDelta(0, signal.panDelta.dy);
          }
        },
        child: RenderWebview(
          textureId: _controller.textureId,
          filterQuality: widget.filterQuality,
          cursor: _controller.cursor,
          onSizeChanged: _updateSurfaceSize,
        ));
  }

  void _updateSurfaceSize(Size size) {
    _updateSizeRequestId++;

    if (!_controller.isReady) {
      final requestId = _updateSizeRequestId;

      _controller.ready.then((_) {
        if (!mounted) {
          return;
        }

        if (requestId != _updateSizeRequestId) {
          return;
        }

        _updateSurfaceSize(size);
      });
    }

    _controller.setSize(
      size,
      widget.scaleFactor ?? window.devicePixelRatio,
    );
  }
}
