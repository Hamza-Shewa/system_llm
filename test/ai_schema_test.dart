import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/system_llm.dart';

void main() {
  const schema = AiSchema.object({
    'ids': AiSchema.array(AiSchema.integer(), maxItems: 8, description: 'IDs'),
    'message': AiSchema.string(),
    'ok': AiSchema.boolean(),
  }, description: 'Answer');

  test('serialises ordered properties with descriptions and limits', () {
    final json = schema.toJson();
    expect(json['type'], 'object');
    expect(json['description'], 'Answer');
    final properties = json['properties']! as List;
    expect(properties.map((p) => (p as Map)['name']), ['ids', 'message', 'ok']);
    final ids = properties.first as Map;
    expect(ids['type'], 'array');
    expect(ids['maxItems'], 8);
    expect(ids['description'], 'IDs');
    expect((ids['items'] as Map)['type'], 'integer');
    expect((properties[1] as Map).containsKey('description'), isFalse);
  });

  test('matches accepts a conforming value and ignores extra keys', () {
    expect(
      schema.matches({
        'ids': [1, 2],
        'message': 'hi',
        'ok': true,
        'extra': 1,
      }),
      isTrue,
    );
  });

  test('matches rejects wrong types, missing keys and non-objects', () {
    expect(
      schema.matches({
        'ids': ['1'],
        'message': 'x',
        'ok': true,
      }),
      isFalse,
    );
    expect(
      schema.matches({
        'ids': [1],
        'message': 'x',
      }),
      isFalse,
    );
    expect(schema.matches({'ids': 1.5, 'message': 'x', 'ok': true}), isFalse);
    expect(schema.matches([1]), isFalse);
    expect(schema.matches(null), isFalse);
  });
}
