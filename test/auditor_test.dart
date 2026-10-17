// Oracle test (FAZ3a K12): auditor contract "every error -> null, the flow never
// breaks" (top comment of lib/io/auditor.dart). The lib/io HTTP body is OUTSIDE the
// coverage gate, so the contract can only be pinned with a MockClient test
// (google_tts_test / llm_discussion_test pattern).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/auditor.dart';

void main() {
  test('200 + valid verdict JSON -> returns the faithful bool', () async {
    final mock = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"sadik": true}'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final verdict = await auditClean(
      apiKey: 'k',
      raw: 'ham',
      clean: 'temiz',
      client: mock,
    );
    expect(verdict, isTrue);
  });

  // K12: an unexpected response shape (choices is NOT a list) today throws a
  // TypeError (an Error, not an Exception) from the unguarded cast chain -> breaks
  // the "every error -> null" contract. Expected: null, the flow is not broken.
  test('200 + unexpected shape (choices is not a list) -> null', () async {
    final mock = MockClient(
      (req) async => http.Response(
        jsonEncode({'choices': 'not-a-list'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final verdict = await auditClean(
      apiKey: 'k',
      raw: 'ham',
      clean: 'temiz',
      client: mock,
    );
    expect(verdict, isNull);
  });
}
