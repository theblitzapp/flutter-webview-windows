import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class RenderWebview extends SingleChildRenderObjectWidget {
  const RenderWebview({
    Key? key,
    required this.onSizeChanged,
    required Widget child,
  }) : super(key: key, child: child);

  final void Function(Size) onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return WebviewBox(onSizeChanged: onSizeChanged);
  }

  @override
  void updateRenderObject(BuildContext context, WebviewBox renderObject) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class WebviewBox extends RenderProxyBox {
  WebviewBox({
    required this.onSizeChanged,
  });

  void Function(Size) onSizeChanged;

  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();

    if (_lastSize != size) {
      _lastSize = size;

      onSizeChanged(size);
    }
  }
}
