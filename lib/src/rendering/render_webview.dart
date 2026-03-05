import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class RenderWebview extends LeafRenderObjectWidget {
  const RenderWebview({
    Key? key,
    required this.textureId,
    required this.filterQuality,
    required this.cursor,
    required this.onSizeChanged,
  }) : super(key: key);

  final int textureId;
  final FilterQuality filterQuality;
  final Stream<SystemMouseCursor> cursor;
  final void Function(Size) onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return WebviewBox(
        textureId: textureId,
        filterQuality: filterQuality,
        cursorStream: cursor,
        onSizeChanged: onSizeChanged);
  }

  @override
  void updateRenderObject(BuildContext context, WebviewBox renderObject) {
    renderObject.textureId = textureId;
    renderObject.filterQuality = filterQuality;
    renderObject.cursorStream = cursor;
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class WebviewBox extends RenderBox implements MouseTrackerAnnotation {
  WebviewBox({
    required int textureId,
    FilterQuality filterQuality = FilterQuality.low,
    required Stream<SystemMouseCursor> cursorStream,
    required this.onSizeChanged,
  })  : _textureId = textureId,
        _filterQuality = filterQuality,
        _cursorStream = cursorStream;

  Stream<SystemMouseCursor> _cursorStream;
  StreamSubscription<SystemMouseCursor>? _cursorSubscription;

  SystemMouseCursor _cursor = SystemMouseCursors.basic;
  bool _validForMouseTracker = false;

  void Function(Size) onSizeChanged;
  Size? _lastNotifiedSize;

  int get textureId => _textureId;
  int _textureId;
  set textureId(int value) {
    if (value != _textureId) {
      _textureId = value;
      markNeedsPaint();
    }
  }

  FilterQuality get filterQuality => _filterQuality;
  FilterQuality _filterQuality;
  set filterQuality(FilterQuality value) {
    if (value != _filterQuality) {
      _filterQuality = value;
      markNeedsPaint();
    }
  }

  Stream<SystemMouseCursor> get cursorStream => _cursorStream;
  set cursorStream(Stream<SystemMouseCursor> value) {
    if (value != _cursorStream) {
      _cursorStream = value;

      _cursorSubscription?.cancel();

      if (_cursorSubscription != null) {
        _cursorSubscription = value.listen(_onCursorChanged);
      }
    }
  }

  @override
  SystemMouseCursor get cursor => _cursor;

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get isRepaintBoundary => true;

  void _onCursorChanged(SystemMouseCursor cursor) {
    _cursor = cursor;

    // A repaint is needed in order to trigger a device update of
    // [MouseTracker] so that this new value can be found.
    markNeedsPaint();
  }

  @override
  @protected
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.biggest;
  }

  @override
  void performLayout() {
    if (_lastNotifiedSize != size) {
      _lastNotifiedSize = size;
      onSizeChanged(size);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.addLayer(
      TextureLayer(
        rect: Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
        textureId: _textureId,
        filterQuality: _filterQuality,
      ),
    );
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  @override
  bool get validForMouseTracker => _validForMouseTracker;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);

    _validForMouseTracker = true;

    _cursorSubscription = cursorStream.listen(_onCursorChanged);
  }

  @override
  void detach() {
    _cursorSubscription?.cancel();
    _cursorSubscription = null;

    _validForMouseTracker = false;

    super.detach();
  }
}
