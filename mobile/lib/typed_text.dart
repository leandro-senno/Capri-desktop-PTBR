import 'dart:async';

import 'package:flutter/material.dart';

/// Texto que aparece letra por letra, como o efeito de digitação do original.
/// Com [animate] falso, mostra tudo de uma vez.
class TypedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool animate;
  const TypedText(this.text, {super.key, required this.style, this.animate = true});

  @override
  State<TypedText> createState() => _TypedTextState();
}

class _TypedTextState extends State<TypedText> {
  Timer? _timer;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(TypedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.animate != widget.animate) _start();
  }

  void _start() {
    _timer?.cancel();
    if (!widget.animate) {
      _shown = widget.text.length;
      return;
    }
    _shown = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 28), (timer) {
      if (!mounted) return;
      setState(() => _shown = (_shown + 2).clamp(0, widget.text.length).toInt());
      if (_shown >= widget.text.length) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.text.substring(0, _shown.clamp(0, widget.text.length).toInt()), style: widget.style);
}
