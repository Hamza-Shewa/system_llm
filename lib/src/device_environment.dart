/// Facts about the device that matter when deciding whether a larger model can
/// be downloaded and run.
class DeviceEnvironment {
  const DeviceEnvironment({
    required this.supported,
    this.directories = const {},
    this.freeBytes = 0,
    this.memoryBytes = 0,
  });

  /// Environment reported when the plugin is missing on this platform.
  static const unsupported = DeviceEnvironment(supported: false);

  /// Whether this process can run a 64-bit native inference runtime.
  final bool supported;

  /// Absolute paths of the requested directories, by name. They exist, and
  /// are excluded from cloud backup.
  final Map<String, String> directories;

  /// Free space on the volume holding [directories], in bytes.
  final int freeBytes;

  /// Total physical memory, in bytes.
  final int memoryBytes;

  factory DeviceEnvironment.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return unsupported;
    final directories = map['directories'];
    return DeviceEnvironment(
      supported: map['supported'] == true,
      directories: directories is Map
          ? {
              for (final entry in directories.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const {},
      freeBytes: (map['freeBytes'] as num?)?.toInt() ?? 0,
      memoryBytes: (map['memoryBytes'] as num?)?.toInt() ?? 0,
    );
  }
}
