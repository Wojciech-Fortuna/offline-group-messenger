Pod::Spec.new do |s|
  s.name             = 'offline_connectivity'
  s.version          = '0.1.0'
  s.summary          = 'Native connectivity for Offline Group Messenger.'
  s.description      = 'Private Kotlin and Swift connectivity bridge for the shared Flutter app.'
  s.homepage         = 'https://github.com/Wojciech-Fortuna/offline-group-messenger'
  s.license          = { :type => 'Proprietary' }
  s.author           = 'Offline Group Messenger contributors'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
