import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class WhatsAppInput extends StatelessWidget {
  final String label;
  final String selectedCountryCode;
  final TextEditingController controller;
  final ValueChanged<String?> onCountryCodeChanged;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool isDark;

  const WhatsAppInput({
    Key? key,
    required this.label,
    required this.selectedCountryCode,
    required this.controller,
    required this.onCountryCodeChanged,
    this.validator,
    this.enabled = true,
    this.isDark = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final fillColor = isDark ? const Color(0xFF071028) : Colors.grey[50];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Directionality(
          textDirection: ui.TextDirection.ltr,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: fillColor,
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCountryCode,
                      dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '+970',
                          child: Text('+970'),
                        ),
                        DropdownMenuItem(
                          value: '+972',
                          child: Text('+972'),
                        ),
                      ],
                      onChanged: enabled ? onCountryCodeChanged : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    enabled: enabled,
                    validator: validator,
                    textAlign: TextAlign.left,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(
                      color: isDark ? Colors.white : (enabled ? Colors.black : Colors.black54),
                    ),
                    decoration: InputDecoration(
                      labelText: label,
                      labelStyle: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                      prefixIcon: const Icon(Icons.chat_rounded, color: Color(0xFF0B74FF), size: 20),
                      filled: true,
                      fillColor: fillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF0B74FF), width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red, width: 1),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
