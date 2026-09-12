import 'package:flutter/material.dart';

/// The one button style every activity's expanded content uses — matching
/// §02's "one shared set of motion/visual primitives, no activity hand-rolls
/// its own."
class IslandButton extends StatelessWidget {
  const IslandButton({super.key, required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      // excludeSemantics hides the InkWell's own auto-generated tap
      // semantics too, so the activate action has to be re-declared here —
      // otherwise VoiceOver would read the label but have nothing to invoke.
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
