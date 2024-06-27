platform :ios, '15.4'
inhibit_all_warnings!

target 'SampleApp' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!
  pod 'JWTDecode'
end

target 'MQTTClient' do
    use_frameworks!
    pod 'CocoaMQTT'
end

# post_install do |installer|
 # installer.pods_project.targets.each do |target|
  #  target.build_configurations.each do |config|
   #   config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
   # end
  # end
# end

post_install do |installer|
  installer.aggregate_targets.each do |target|
    target.xcconfigs.each do |variant, xcconfig|
      xcconfig_path = target.client_root + target.xcconfig_relative_path(variant)
      IO.write(xcconfig_path, IO.read(xcconfig_path).gsub("DT_TOOLCHAIN_DIR", "TOOLCHAIN_DIR"))
    end
  end
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
      if config.base_configuration_reference.is_a? Xcodeproj::Project::Object::PBXFileReference
        xcconfig_path = config.base_configuration_reference.real_path
        IO.write(xcconfig_path, IO.read(xcconfig_path).gsub("DT_TOOLCHAIN_DIR", "TOOLCHAIN_DIR"))
      end
    end
  end
end
