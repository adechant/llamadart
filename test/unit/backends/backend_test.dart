import 'package:llamadart/src/backends/backend.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaBackend interface is available', () {
    expect(LlamaBackend, isNotNull);
  });

  test('BackendEmbeddings capability interface is available', () {
    expect(BackendEmbeddings, isNotNull);
  });

  test('BackendBatchEmbeddings capability interface is available', () {
    expect(BackendBatchEmbeddings, isNotNull);
  });
}
