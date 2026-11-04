## 0.1.1

* Android: stop requiring ML Kit's structured-output feature, which this plugin
  no longer uses, so phones without it can still generate.
* iOS: declare the disk space API in the privacy manifest, and weak-link
  Foundation Models under CocoaPods.

## 0.1.0

* Initial version: availability check, schema-constrained structured generation
  with the system language model, streamed free-text generation (`streamText`),
  on-device speech recognition, and a small device-environment helper.
