#
# Be sure to run `pod lib lint NoMoreNetworkService.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name = "NoMoreNetworkService"
  s.version = "1.6.2"
  s.summary = "An extension of URLSession for network requesting."

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description = <<-DESC
No more needed NetworkService when we can use URLSession for almost of things.
                       DESC

  s.homepage = "https://github.com/congncif/no-more-network-service"
  s.license = { :type => "MIT", :file => "LICENSE" }
  s.author = { "congncif" => "congnc.if@gmail.com" }
  s.source = { :git => "https://github.com/congncif/no-more-network-service.git", :tag => s.version.to_s }
  s.social_media_url = "https://twitter.com/congncif"

  s.ios.deployment_target = "13.0"
  s.swift_version = "5"

  s.source_files = "NoMoreNetworkService/Classes/**/*"

  # s.resource_bundles = {
  #   'NoMoreNetworkService' => ['NoMoreNetworkService/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
