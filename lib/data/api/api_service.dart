import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../../domain/models/user.dart';

class ApiService {
  static const baseUrl = 'http://10.0.2.2:8000'; // Android emulator
  final Logger _logger = Logger();

  /// Ajusta la ruta al endpoint real de tu backend
  static const _registerPath = '/register';

  Future<bool> registerUser(User user) async {
    final url = Uri.parse('$baseUrl$_registerPath');
    final body = jsonEncode(user.toJson()); // incluye 'email'

    _logger.i('📤 POST $url');
    _logger.i('📦 BODY: $body');

    try {
      final response = await http
          .post(
            url,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      _logger.i('📥 STATUS: ${response.statusCode}');
      _logger.i('📥 BODY: ${response.body}');

      // Intenta extraer mensaje del backend
      Map<String, dynamic> json = {};
      try {
        json = jsonDecode(response.body.isEmpty ? '{}' : response.body)
            as Map<String, dynamic>;
      } catch (_) {}
      final backendMsg = (json['error'] ?? json['message'])?.toString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      }

      if (response.statusCode == 400 || response.statusCode == 409) {
        // 👉 Propaga el mensaje real (ej. "Código de referido inválido")
        throw ApiException(
          backendMsg ?? 'Solicitud inválida',
          statusCode: response.statusCode,
        );
      }

      throw ApiException(
        backendMsg ?? 'Error inesperado (${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow; // no envuelvas tu propia excepción
    } on http.ClientException catch (e, st) {
      _logger.e('❌ ClientException', error: e, stackTrace: st);
      throw ApiException('Error de conexión con el servidor');
    } on FormatException catch (e, st) {
      _logger.e('❌ Respuesta no válida', error: e, stackTrace: st);
      throw ApiException('Respuesta inválida del servidor');
    } on Exception catch (e, st) {
      _logger.e('❌ Excepción al registrar', error: e, stackTrace: st);
      throw ApiException('Error inesperado al registrar');
    }
  }

  Future<List<Map<String, dynamic>>> fetchIdentificationTypes() async {
    final url = Uri.parse('$baseUrl/identification-types');
    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final List<dynamic> json = jsonDecode(utf8.decode(response.bodyBytes));
      return json.map((e) => e as Map<String, dynamic>).toList();
    } else {
      _logger.e('❌ Error: ${response.statusCode} - ${response.body}');
      throw Exception('Error al obtener tipos de identificación');
    }
  }
}
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException(${statusCode ?? '-'}) $message';
}
