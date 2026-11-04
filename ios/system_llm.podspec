#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint system_llm.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'system_llm'
  s.version          = '0.1.1'
  s.summary          = 'Flutter bridge to the OS built-in language model and on-device speech.'
  s.description      = <<-DESC
Structured and streamed generation with Apple Foundation Models, plus on-device speech recognition.
                       DESC
  s.homepage         = 'https://github.com/Hamza-Shewa/system_llm'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hamza Shewa' => '42789638+Hamza-Shewa@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'system_llm/Sources/system_llm/**/*'
  s.dependency 'Flutter'
  # Older iOS versions have no Foundation Models; the code checks availability.
  s.weak_frameworks = 'FoundationModels'
  s.resource_bundles = { 'system_llm_privacy' => ['system_llm/Sources/system_llm/PrivacyInfo.xcprivacy'] }
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'system_llm_privacy' => ['system_llm/Sources/system_llm/PrivacyInfo.xcprivacy']}
end
