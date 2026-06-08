import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? suffix;
  final Widget? prefix;
  final int maxLines;
  final bool required;
  final List<TextInputFormatter>? inputFormatters;
  final void Function(String)? onChanged;

  const CustomTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.readOnly = false,
    this.onTap,
    this.suffix,
    this.prefix,
    this.maxLines = 1,
    this.required = false,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      validator: validator ??
          (required
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '$label مطلوب';
                  }
                  return null;
                }
              : null),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        suffixIcon: suffix,
        prefixIcon: prefix,
      ),
    );
  }
}

class NumberTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool required;
  final String? unit;
  final void Function(String)? onChanged;

  const NumberTextField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.required = false,
    this.unit,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      validator: validator ??
          (required
              ? (value) {
                  if (value == null || value.trim().isEmpty) return '$label مطلوب';
                  if (double.tryParse(value) == null) return 'أدخل رقماً صحيحاً';
                  return null;
                }
              : null),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        suffixText: unit,
      ),
    );
  }
}

class DropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;
  final String? Function(T?)? validator;
  final bool required;

  const DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      validator: validator ??
          (required
              ? (value) {
                  if (value == null) return '$label مطلوب';
                  return null;
                }
              : null),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
      ),
    );
  }
}
