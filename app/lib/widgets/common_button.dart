import 'package:flutter/material.dart';

import 'hue_button.dart';

class CommonButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const CommonButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return HueButton(
      label: label,
      onPressed: onPressed,
      loading: loading,
      variant: HueButtonVariant.primary,
    );
  }
}
