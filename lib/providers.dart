/// Third-party and local model providers behind the same [LanguageModel]
/// interface as the on-device model.
///
/// Importing this library lets an app send prompts off the device, to the
/// provider the user configured. Everything from `system_llm.dart` is
/// re-exported, so one import is enough.
library;

import 'system_llm.dart';

export 'system_llm.dart';
export 'src/providers/provider_config.dart';
export 'src/remote/remote_model.dart'
    show RemoteLanguageModel, OpenAiCompatibleModel;
