# All Aboard - Accessible Bus Stop Detection App
<img width="1536" height="1024" alt="AllAboardCover" src="https://github.com/user-attachments/assets/6eedd8da-53cb-44f2-b9f0-f9da6ed59f8e" />


**All Aboard** is a comprehensive accessibility application designed to revolutionize public transportation navigation for visually impaired users. Leveraging  machine learning and computer vision, this app provides real-time bus stop detection, distance measurement, optical character recognition, and voice-controlled navigation assistance.

## 🌟 Features

### Core Accessibility Features
- **🚌 Intelligent Bus Stop Detection**: Real-time detection and recognition of bus stop signs using custom-trained TensorFlow Lite models optimized for mobile inference
- **📏 Precise Distance Measurement**: Advanced geometric calculations provide accurate distance measurements to detected bus stops with sub-meter precision
- **🔊 Multi-Modal Audio Feedback System**: 
  - Adaptive sonar-like audio guidance when device is held in portrait orientation
  - Dynamic beep rate modulation based on proximity (3 different pitch levels, 4 speed variations)
  - Spatial audio cues for directional guidance
- **📖 Advanced OCR Text Reading**: 
  - Real-time text recognition
  - Natural language processing for improved readability
- **🎤 Sophisticated Voice Search**: 
  - Voice-controlled search functionality with natural language processing
  - Real-time speech-to-text conversion
  - Context-aware search highlighting and audio feedback
  - Hands-free operation optimized for accessibility

### Advanced Machine Learning Features
- **🤖 Multi-City Transit System Support**: Pre-trained models for major global transit networks:
  - **Boston (MBTA)**
  - **New York (MTA)**
  - **Los Angeles Metro**
  - **Chicago (CTA)**
  - **San Francisco Bay Area (AC Transit)**
  - **Seattle Metro**
  - **Toronto (TTC)**
  - **Washington DC (Metrobus)**
  - **London Bus Services**
  - **Germany Bus and Tram**
    
- **📍 Intelligent Location-Based Model Selection**: 
  - GPS-based automatic model detection and installation
  - Fallback mechanisms for offline operation
  - Smart caching to minimize storage requirements
  - Background model updates and optimization

### User Experience & Interface
- **⚙️ Comprehensive Settings Management**: 
  - Custom model selection and management
  - Accessibility option customization
- **📱 Voice-First Interface Design**: 
  - Complete VoiceOver integration
  - Audio-first navigation paradigm
  - High contrast visual elements for low vision users

## 📋 System Requirements

### Minimum Requirements
- **iOS Version**: iOS 13.0 or later (iOS 15.0+ recommended for optimal performance)
- **Device Compatibility**: 
  - iPhone 7 or later (iPhone 12+ recommended for best ML performance)
  - iPad (6th generation) or later
  - Minimum 3GB RAM for smooth operation
- **Storage**: 
  - Base app: 50MB
  - Per model: 15-25MB (typical installation: 200-300MB total)
  - Recommended free space: 1GB for optimal performance
- **Network**: 
  - Initial setup: WiFi or cellular 
  - Ongoing usage: Optional (offline operation supported)

### Optimal Performance Requirements
- **Device**: iPhone 12 or later with A14 Bionic chip or equivalent
- **Storage**: 2GB+ free space for multiple model support
- **Network**: 5G or high-speed WiFi for rapid model downloads

### Required Permissions
- **Camera**: Essential for bus stop detection and OCR functionality
- **Microphone**: Required for voice search and speech recognition
- **Location Services**: Needed for automatic model selection and GPS-based features
- **Speech Recognition**: Required for voice command processing
- **Notifications**: Optional, for model update alerts and system messages

## 🚀 Installation & Setup Instructions

### Development Environment Setup

#### Prerequisites
1. **Xcode 14.0+** with iOS 13.0+ SDK deployment target
2. **macOS Monterey 12.0+** (recommended: macOS Ventura 13.0+)
3. **Apple Developer Account** (required for device deployment and push notifications)
4. **CocoaPods 1.11.0+** for dependency management

#### Initial Project Setup

1. **Clone the Repository**
   ```bash
   git clone https://github.com/yourusername/allaboard-app.git
   cd allaboard-app
   ```

2. **Install CocoaPods Dependencies**
   ```bash
   # Install CocoaPods if not already installed
   sudo gem install cocoapods
   
   # Install project dependencies
   pod install --repo-update
   
   # Ensure you have the latest pod specifications
   pod repo update
   ```
   
   ⚠️ **CRITICAL**: Always use `AllAboard.xcworkspace` and **NEVER** `AllAboard.xcodeproj` after running `pod install`. The workspace file contains the proper configuration for all CocoaPods dependencies.

3. **Open the Workspace** (Not the Project!)
   ```bash
   # Correct way to open the project
   open AllAboard.xcworkspace
   
   # ❌ WRONG - Do not use the .xcodeproj file
   # open AllAboard.xcodeproj
   ```

#### Google Cloud Services Configuration

⚠️ **MANDATORY: Google Cloud API Configuration**

The app requires Google Cloud services for enhanced OCR and speech recognition capabilities. You must configure your own API credentials:

1. **Create Google Cloud Project**
   - Visit [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select an existing one
   - Note your Project ID for later configuration

2. **Enable Required APIs**
   Navigate to "APIs & Services" → "Library" and enable:
   - **Cloud Vision API** (for enhanced OCR functionality)
   - **Cloud Speech-to-Text API** (for cloud-based speech recognition)
   - **Cloud Translation API** (optional, for multi-language support)

3. **Create API Credentials**
   - Go to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "API key"
   - Copy the generated API key
   - Restrict the API key:
     - Application restrictions: iOS apps
     - Bundle ID: Your app's bundle identifier
     - API restrictions: Select only the APIs you enabled above

4. **Configure GoogleInfo.plist**
   
   Create a `GoogleInfo.plist` file in your project root directory with the following structure:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>API_KEY</key>
       <string>YOUR_GOOGLE_CLOUD_API_KEY_HERE</string>
       <key>GCM_SENDER_ID</key>
       <string>YOUR_PROJECT_NUMBER</string>
       <key>PLIST_VERSION</key>
       <string>1</string>
       <key>BUNDLE_ID</key>
       <string>com.yourcompany.allaboard</string>
       <key>PROJECT_ID</key>
       <string>your-project-id</string>
       <key>STORAGE_BUCKET</key>
       <string>your-project-id.appspot.com</string>
       <key>IS_ADS_ENABLED</key>
       <false/>
       <key>IS_ANALYTICS_ENABLED</key>
       <false/>
       <key>IS_APPINVITE_ENABLED</key>
       <false/>
       <key>IS_GCM_ENABLED</key>
       <false/>
       <key>IS_SIGNIN_ENABLED</key>
       <false/>
       <key>GOOGLE_APP_ID</key>
       <string>1:YOUR_PROJECT_NUMBER:ios:YOUR_BUNDLE_ID_HASH</string>
   </dict>
   </plist>
   ```

5. **Add GoogleInfo.plist to Xcode**
   - Drag the `GoogleInfo.plist` file into your Xcode project
   - Ensure it's added to the target
   - Verify it appears in the "Copy Bundle Resources" build phase

#### Project Configuration

1. **Bundle Identifier & Signing**
   - Select the project root in Xcode navigator
   - Update Bundle Identifier to match your developer account
   - Configure "Signing & Capabilities":
     - Enable "Automatically manage signing"
     - Select your development team
     - Add required capabilities (see Capabilities section below)

2. **Required Info.plist Permissions**
   
   Add these usage descriptions to your `Info.plist`:
   ```xml
   <!-- Camera Permission -->
   <key>NSCameraUsageDescription</key>
   <string>All Aboard needs camera access to detect bus stops and read signs, providing essential navigation assistance for visually impaired users.</string>
   
   <!-- Microphone Permission -->
   <key>NSMicrophoneUsageDescription</key>
   <string>All Aboard needs microphone access to enable voice search functionality, allowing hands-free interaction with text recognition features.</string>
   
   <!-- Location Permission -->
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>All Aboard needs location access to automatically download the appropriate transit detection model for your city, ensuring accurate bus stop recognition.</string>
   
   <!-- Speech Recognition Permission -->
   <key>NSSpeechRecognitionUsageDescription</key>
   <string>All Aboard needs speech recognition to process voice commands for searching text in signs and providing voice-controlled navigation assistance.</string>
   
   <!-- Background Processing -->
   <key>UIBackgroundModes</key>
   <array>
       <string>audio</string>
       <string>background-processing</string>
   </array>
   ```

3. **Required Capabilities**
   
   In Xcode, go to "Signing & Capabilities" and add:
   - **Background Modes**: Audio, Background processing
   - **App Groups** (if planning multi-app features)
   - **Push Notifications** (for model update alerts)

4. **Build Settings Configuration**
   
   Ensure these build settings are properly configured:
   ```
   - Deployment Target: iOS 13.0
   - Swift Version: Swift 5.5+
   - Architectures: arm64, arm64e
   - Valid Architectures: arm64, arm64e
   - Build Active Architecture Only: No (for Release builds)
   ```

#### Dependencies & Frameworks

The project uses CocoaPods for dependency management. Key dependencies include:

```ruby
# Podfile
platform :ios, '13.0'
use_frameworks!

target 'AllAboard' do
  # TensorFlow Lite for machine learning
  pod 'TensorFlowLiteSwift', '~> 2.8.0'
  
  # Google ML Kit for enhanced OCR
  pod 'GoogleMLKit/TextRecognition', '~> 3.2.0'
  
  # Audio processing
  pod 'AudioKit', '~> 5.6.0'
  
  # Network and JSON handling
  pod 'Alamofire', '~> 5.6.0'
  pod 'SwiftyJSON', '~> 5.0.0'
  
  # Analytics (optional)
  pod 'UMCAnalytics', '~> 1.0.0'
end
```

### Building & Running

#### Debug Build (Development)
1. **Connect iOS Device**: Camera functionality requires a physical device
2. **Select Target Device**: Choose your connected iPhone/iPad
3. **Build and Run**: 
   ```
   ⌘ + R (or click the Play button in Xcode)
   ```

#### Release Build (App Store Distribution)
1. **Archive Build**:
   - Select "Any iOS Device (arm64)" as the run destination
   - Product → Archive
2. **Code Signing**: Ensure distribution certificate is properly configured
3. **Upload to App Store Connect**: Use Xcode Organizer or Application Loader

#### Common Build Issues & Solutions

**Issue: "No such module 'TensorFlowLite'"**
```bash
# Solution: Clean and reinstall pods
pod deintegrate
pod install
# Clean build folder in Xcode: ⌘ + Shift + K
```

**Issue: "GoogleInfo.plist not found"**
- Ensure the file is added to the target
- Check that the file is in the correct location
- Verify the file is included in "Copy Bundle Resources"

**Issue: "Signing certificate not found"**
- Check Apple Developer account status
- Refresh provisioning profiles
- Ensure bundle ID matches registered App ID

## 🛠️ Comprehensive Developer Notes

### Installation Issues

#### CocoaPods Problems
```bash
# Complete clean reinstall
sudo gem uninstall cocoapods
sudo gem install cocoapods
pod setup
cd your-project
pod deintegrate
pod clean
pod install
```

#### Xcode Issues
```bash
# Clear Xcode derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
# Clear Xcode caches
rm -rf ~/Library/Caches/com.apple.dt.Xcode
```

### Runtime Issues

#### Model Loading Failures
**Symptoms**: App crashes on startup, "Model not found" errors
**Solutions**:
1. Verify model files exist in app bundle
2. Check file permissions and paths
3. Validate model file integrity (not corrupted)
4. Ensure sufficient device memory

#### Audio System Problems
**Symptoms**: No speech output, beeps not playing
**Solutions**:
1. Check audio session configuration
2. Verify device is not in silent mode
3. Test with headphones connected
4. Check for audio interruptions from other apps

#### Camera Permission Issues
**Symptoms**: Black camera preview, permission denied errors
**Solutions**:
1. Reset privacy settings: Settings → General → Reset → Reset Location & Privacy
2. Manually enable in Settings → Privacy → Camera
3. Reinstall app to trigger permission prompt

#### Location Services Problems
**Symptoms**: Models not auto-downloading, location-based features not working
**Solutions**:
1. Enable location services in Settings → Privacy → Location Services
2. Set app permission to "While Using App"
3. Check for location services restrictions (parental controls)
