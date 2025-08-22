import 'package:flutter/material.dart';
import '../../../../data/api/api_service.dart';

class IdentificationTypeInput extends StatefulWidget {
  final String? selectedType;
  final ValueChanged<String?> onChanged;

  const IdentificationTypeInput({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  @override
  State<IdentificationTypeInput> createState() => _IdentificationTypeInputState();
}

class _IdentificationTypeInputState extends State<IdentificationTypeInput> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _types = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIdentificationTypes();
  }

  Future<void> _loadIdentificationTypes() async {
    try {
      final data = await _apiService.fetchIdentificationTypes();
      setState(() {
        _types = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Error al cargar tipos de identificación: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CircularProgressIndicator();
    }

    return DropdownButtonFormField<String>(
      value: widget.selectedType,
      decoration: const InputDecoration(
        labelText: 'Tipo de identificación',
        border: OutlineInputBorder(),
      ),
      items: _types.map((type) {
        return DropdownMenuItem<String>(
          value: type['id'].toString(),
          child: Text(
            type['name'],
            style: const TextStyle(color: Colors.black), // ✅ COLOR VISIBLE
          ),
        );
      }).toList(),
      onChanged: widget.onChanged,
    );
  }
}
