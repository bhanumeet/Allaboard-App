# Podfile
platform :ios, '11.0'
use_frameworks!

target 'All Aboard' do
  # Core OCR engine
  pod 'TensorFlowLiteSwift'
  # Firebase MLModelDownloader ≥ 10.22.0 (includes privacy manifest)
  pod 'Firebase/MLModelDownloader', '>= 10.22.0'

  target 'All AboardTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'All AboardUITests' do
    inherit! :search_paths
    # Pods for UI testing
  end
end
