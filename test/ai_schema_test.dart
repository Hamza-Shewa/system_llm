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

  test('toJsonSchema emits standard JSON Schema with every key required', () {
    expect(schema.toJsonSchema(), {
      'type': 'object',
      'description': 'Answer',
      'properties': {
        'ids': {
          'type': 'array',
          'description': 'IDs',
          'maxItems': 8,
          'items': {'type': 'integer'},
        },
        'message': {'type': 'string'},
        'ok': {'type': 'boolean'},
      },
      'required': ['ids', 'message', 'ok'],
      'additionalProperties': false,
    });
  });

  test('toJsonSchema nests objects inside arrays', () {
    const nested = AiSchema.object({
      'items': AiSchema.array(AiSchema.object({'name': AiSchema.string()})),
    });
    final items = (nested.toJsonSchema()['properties']! as Map)['items'] as Map;
    expect(items['items'], {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
      },
      'required': ['name'],
      'additionalProperties': false,
    });
  });
}
