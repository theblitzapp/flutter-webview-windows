import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class RenderWebview extends LeafRenderObjectWidget {
  const RenderWebview({
    Key? key,
    required this.textureId,
    required this.filterQuality,
    required this.frameSize,
    required this.onSizeChanged,
  }) : super(key: key);

  final int textureId;
  final FilterQuality filterQuality;
  final Stream<Size> frameSize;
  final void Function(Size) onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return WebviewBox(
        textureId: textureId,
        filterQuality: filterQuality,
        frameSize: frameSize,
        onSizeChanged: onSizeChanged);
  }

  @override
  void updateRenderObject(BuildContext context, WebviewBox renderObject) {
    renderObject.textureId = textureId;
    renderObject.filterQuality = filterQuality;
    renderObject.onSizeChanged = onSizeChanged;
    renderObject.frameSize = frameSize;
  }
}

class WebviewBox extends RenderBox {
  WebviewBox({
    required int textureId,
    FilterQuality filterQuality = FilterQuality.low,
    required Stream<Size> frameSize,
    required this.onSizeChanged,
  })  : _textureId = textureId,
        _filterQuality = filterQuality,
        _frameSize = frameSize;

  void Function(Size) onSizeChanged;

  Size? _lastNotifiedSize;

  Size? _currentFrameSize;
  StreamSubscription<Size>? _frameSizeSubscription;

  Stream<Size> get frameSize => _frameSize;
  Stream<Size> _frameSize;
  set frameSize(Stream<Size> value) {
    if (value != _frameSize) {
      _frameSize = value;

      if (_frameSizeSubscription != null) {
        _frameSizeSubscription?.cancel();

        _frameSizeSubscription = _frameSize.listen((size) {
          if (!attached) {
            return;
          }

          markNeedsPaint();
        });
      }
    }
  }

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

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get isRepaintBoundary => true;

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
    final paintSize = _currentFrameSize ?? size;
    context.addLayer(
      TextureLayer(
        rect: Rect.fromLTWH(
            offset.dx, offset.dy, paintSize.width, paintSize.height),
        textureId: _textureId,
        filterQuality: _filterQuality,
      ),
    );
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);

    _frameSizeSubscription = _frameSize.listen((physicalSize) {
      if (!attached) {
        return;
      }

      _currentFrameSize = physicalSize;
      markNeedsPaint();
    });
  }

  @override
  void detach() {
    super.detach();

    _frameSizeSubscription?.cancel();
    _frameSizeSubscription = null;
  }
}
