/// Describes the JSON shape a model must answer with.
///
/// Every property of an object is required. On Apple platforms the schema
/// constrains decoding; on Android it is sent in the prompt and the answer is
/// validated, with one retry.
sealed class AiSchema {
  const AiSchema({this.description});

  /// An object with named, ordered [properties].
  const factory AiSchema.object(
    Map<String, AiSchema> properties, {
    String? description,
  }) = AiObjectSchema;

  /// A list of [items], optionally capped to [maxItems].
  const factory AiSchema.array(
    AiSchema items, {
    int? maxItems,
    String? description,
  }) = AiArraySchema;

  /// A text value.
  const factory AiSchema.string({String? description}) = AiStringSchema;

  /// A whole number.
  const factory AiSchema.integer({String? description}) = AiIntegerSchema;

  /// A true/false value.
  const factory AiSchema.boolean({String? description}) = AiBooleanSchema;

  /// Hint to the model about what this value means.
  final String? description;

  /// The structure sent over the platform channel.
  Map<String, Object?> toJson();

  /// Standard JSON Schema, as remote providers expect it: every object
  /// property is required and no other keys are allowed.
  Map<String, Object?> toJsonSchema();

  /// Whether [value], decoded from JSON, has the shape described here.
  ///
  /// Extra object keys are ignored and array lengths are not checked, so
  /// callers decide whether to truncate.
  bool matches(Object? value);
}

final class AiObjectSchema extends AiSchema {
  const AiObjectSchema(this.properties, {super.description});

  /// Insertion order is the order the model fills the fields in.
  final Map<String, AiSchema> properties;

  @override
  Map<String, Object?> toJson() => {
    'type': 'object',
    'description': ?description,
    'properties': [
      for (final entry in properties.entries)
        {'name': entry.key, ...entry.value.toJson()},
    ],
  };

  @override
  Map<String, Object?> toJsonSchema() => {
    'type': 'object',
    'description': ?description,
    'properties': {
      for (final entry in properties.entries)
        entry.key: entry.value.toJsonSchema(),
    },
    'required': [...properties.keys],
    'additionalProperties': false,
  };

  @override
  bool matches(Object? value) =>
      value is Map &&
      properties.entries.every(
        (entry) =>
            value.containsKey(entry.key) &&
            entry.value.matches(value[entry.key]),
      );
}

final class AiArraySchema extends AiSchema {
  const AiArraySchema(this.items, {this.maxItems, super.description});

  final AiSchema items;
  final int? maxItems;

  @override
  Map<String, Object?> toJson() => {
    'type': 'array',
    'description': ?description,
    'maxItems': ?maxItems,
    'items': items.toJson(),
  };

  @override
  Map<String, Object?> toJsonSchema() => {
    'type': 'array',
    'description': ?description,
    'maxItems': ?maxItems,
    'items': items.toJsonSchema(),
  };

  @override
  bool matches(Object? value) => value is List && value.every(items.matches);
}

final class AiStringSchema extends AiSchema {
  const AiStringSchema({super.description});

  @override
  Map<String, Object?> toJson() => {
    'type': 'string',
    'description': ?description,
  };

  @override
  Map<String, Object?> toJsonSchema() => toJson();

  @override
  bool matches(Object? value) => value is String;
}

final class AiIntegerSchema extends AiSchema {
  const AiIntegerSchema({super.description});

  @override
  Map<String, Object?> toJson() => {
    'type': 'integer',
    'description': ?description,
  };

  @override
  Map<String, Object?> toJsonSchema() => toJson();

  @override
  bool matches(Object? value) => value is int;
}

final class AiBooleanSchema extends AiSchema {
  const AiBooleanSchema({super.description});

  @override
  Map<String, Object?> toJson() => {
    'type': 'boolean',
    'description': ?description,
  };

  @override
  Map<String, Object?> toJsonSchema() => toJson();

  @override
  bool matches(Object? value) => value is bool;
}
