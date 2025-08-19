//
//  ViewController.swift
//  All Aboard
//
//  Created by Wiper on 21/07/21.
//  Updated by Meet on 05/27/2025.
import UIKit
import AVFoundation
import CoreMotion
import CoreLocation
import MapKit
import Contacts
import AudioToolbox
import Vision
import TensorFlowLite
import Speech


@available(iOS 13.0, *)
class CameraViewController: UIViewController, UIActionSheetDelegate, CLLocationManagerDelegate {
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var overlayView: OverlayView!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var menuView: UIView!
    @IBOutlet weak var locationLabel: UILabel!
    @IBOutlet weak var currentLocationLabel: UILabel!
    @IBOutlet weak var readSignButton: UIButton!
    @IBOutlet weak var searchBar: UISearchBar!
    
    
    // Dictation
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) // Testing English for now...
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Mic icon and Done button
    private let micImageView = UIImageView(image: UIImage(systemName: "mic.fill"))
    let tooltipLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Tap and hold mic to speak"
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 15)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.alpha = 0 // Initially hidden
        return label
    }()
    
    
    // OCR
    var isCurrentlySearching = true // Keeps track of whether currently searching
    
    var isOCREnabled: Bool = false
    var textDetectionRequest: VNRecognizeTextRequest!
    var speechSynthesizer = AVSpeechSynthesizer()
    private var lastRecognizedText: String?
    private let motionManager = CMMotionManager()
    private var preSpeakText = ""
    private var maxLetters = 200
    private var maxTime = 1.0 // seconds
    private var lastAverageZ = 0.0
    private var currentAverageZ = 0.0
    private var maxAverageZChange = 2.0
    private var lastSpeakTime = Date()
        
    var speechQueue: [String] = []
    var isSpeakingLock = false
    
    private var latestPixelBuffer: CVPixelBuffer?
        
    // MARK: Constants
    private let displayFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
    private let edgeOffset: CGFloat = 2.0
    private let labelOffset: CGFloat = 10.0
    private let animationDuration = 0.5
    private let collapseTransitionThreshold: CGFloat = -30.0
    private let expandTransitionThreshold: CGFloat = 30.0
    private let delayBetweenInferencesMs: Double = 200
    // MARK: Instance Variables
    private var initialBottomSpace: CGFloat = 0.0
    // Holds the results at any time
    private var result: Result?
    private var previousInferenceTimeMs: TimeInterval = Date.distantPast.timeIntervalSince1970 * 1000
    // MARK: Controllers that manage functionality
    private lazy var cameraFeedManager = CameraFeedManager(previewView: previewView)

    private var modelDataHandler: ModelDataHandler?
    lazy var tiltActivated = Bool()
    
    var capturePhotoOutput = AVCapturePhotoOutput()
    var captureSession: AVCaptureSession!
    var ocrCaptureSession: AVCaptureSession!  // Dedicated session for OCR
    
    let sessionQueue = DispatchQueue(label: "session queue")
    var isCaptureSessionConfigured = false // Instance proprerty on this view controller class
    private var didConfigureAudioSession = false
    
    let defaults = UserDefaults.standard
    var distance_info = ""
    var sii = 0 // 0 -> no BEEP playing; 1 -> 0.5 rate; 2 -> 1 rate; 3 -> 1.5 rate; 4 -> 2 rate.
    var player: AVAudioPlayer?
    var sonarPlayer: AVAudioPlayer?
    var soundTrack = 1 // 0 -> SONAR, 1 -> BEEP
    private var manager: CMMotionManager?
    let locationManager = CLLocationManager()
    var timer: Timer?
    var convertedRectWidth: CGFloat?
    var verticalAngle = CGFloat(0.0)
    var locValues = ""
    var minValue = CGFloat()
    var maxValue = CGFloat()
    var labelMessage = ""
    var imageDetected = false
    
    // properties to manage speech queue
    private let speechQueueSyncQueue = DispatchQueue(label: "com.allaboard.speechQueueSyncQueue")
    
    
    // Properties declared at the class level
    
    private var hasCheckedCity = false
    
    // Model download properties
    private let modelsBaseURL = "https://vrt.partners.org/AllAboard_Android_Modelfiles/Models/"
    private let labelsURL = "https://vrt.partners.org/AllAboard_Android_Modelfiles/Labelmaps/"
    
   
    
    var tfliteArrayJSON = [String]() // Empty - will be populated from server
    private var tfliteArray = [String]()
    private var installedArr = [String]()
    private var installedPathArr = [String: String]()
    var downloadTask = URLSessionDownloadTask()
    var tfliteDict = [String : String]()
    var counter = 0
    
    var loadingIndicator: UIActivityIndicatorView  = {
        let a = UIActivityIndicatorView()
        a.translatesAutoresizingMaskIntoConstraints = false
        a.hidesWhenStopped = true
        a.tintColor = .black
        a.style = .gray
        return a
    }()
    let loadingView = UIView()
    let loadingLabel = UILabel()
    
    // Add flag to prevent multiple alert presentations
    private var isAlertPresented = false
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasCheckedCity = false
        AppUtility.lockOrientation(.portrait)
        
        // Check if we have valid installed models
        if let installedModels = defaults.array(forKey: "installed") as? [String],
           !installedModels.isEmpty,
           let selectedModel = defaults.string(forKey: "selectedModel"),
           let modelPath = (defaults.value(forKey: "modelPath") as? [String: String])?[selectedModel],
           FileManager.default.fileExists(atPath: modelPath) {
            // Valid model exists, load it
            loadModel()
        } else {
            // No valid model - clear old data and wait for server data
            print("🧹 Clearing old model data...")
            
            // Clear all old model references
            defaults.removeObject(forKey: "installed")
            defaults.removeObject(forKey: "selectedModel")
            defaults.removeObject(forKey: "selectedLabel")
            defaults.removeObject(forKey: "modelPath")
            defaults.removeObject(forKey: "installedPath")
            defaults.removeObject(forKey: "lastCity")  // ← ADD THIS LINE
            
            // Reset arrays
            installedArr.removeAll()
            installedPathArr.removeAll()
            
            // Wait for server data, then auto-install
            checkAndInstallModelIfNeeded()
        }
    }
    
    // Add these properties at the top of CameraViewController
    private var isServerDataLoaded = false

    // Add this function to CameraViewController
    private func fetchServerModelsData() {
        print("🌐 Fetching models from server...")
        
        let modelsListURL = "https://vrt.partners.org/AllAboard_Android_Modelfiles/Models/"
        guard let url = URL(string: modelsListURL) else {
            useFallbackAndAutoInstall()
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Error fetching models list: \(error)")
                self.useFallbackAndAutoInstall()
                return
            }
            
            guard let data = data,
                  let htmlString = String(data: data, encoding: .utf8) else {
                print("❌ Failed to parse models list response")
                self.useFallbackAndAutoInstall()
                return
            }

            let modelNames = self.parseModelNamesFromHTML(htmlString)

            if modelNames.isEmpty {
                print("❌ No models found in response, using fallback")
                self.useFallbackAndAutoInstall()
            } else {
                DispatchQueue.main.async {
                    self.setupModelsWithServerData(modelNames)
                }
            }
        }
        task.resume()
    }

    private func parseModelNamesFromHTML(_ htmlString: String) -> [String] {
        var modelNames: [String] = []
        let pattern = #"href="([^"]*\.tflite)""#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(
                in: htmlString,
                options: [],
                range: NSRange(location: 0, length: htmlString.count)
            )

            for match in matches {
                if let range = Range(match.range(at: 1), in: htmlString) {
                    let fileName = String(htmlString[range])
                    let modelName = fileName.replacingOccurrences(of: ".tflite", with: "")
                    if let decodedName = modelName.removingPercentEncoding {
                        if !modelNames.contains(decodedName) {
                            modelNames.append(decodedName)
                        }
                    }
                }
            }
        } catch {
            print("❌ Regex error: \(error)")
        }

        print("🔍 Parsed model names from server: \(modelNames)")
        return modelNames
    }

    private func setupModelsWithServerData(_ modelNames: [String]) {
        print("🔧 Setting up models with server data...")
        
        tfliteArrayJSON = modelNames
        
        // Now run string manipulation with server data
        stringManipulation()
        
        // Mark server data as loaded
        isServerDataLoaded = true
        
        print("✅ Server data loaded successfully!")
        
        // Now proceed with auto-installation
        proceedWithAutoInstall()
    }

    private func useFallbackAndAutoInstall() {
        print("📦 Using fallback model data")
        let fallbackNames = [
            "California_AC_Transit_500",
            "Chicago_CTA_350",
            "Germany_bus_and_tram_420",
            "London_bus_services_330",
            "Los_Angeles_Metro_615",
            "MBTA_Boston_330",
            "New_York_MTA_450",
            "Seattle_Metro_350",
            "Toronto_TTC_165",
            "Washington_DC_Metrobus_500"
        ]
        
        DispatchQueue.main.async {
            self.setupModelsWithServerData(fallbackNames)
        }
    }
    
    func presentModelInstallationSuggestion() {
        DispatchQueue.main.async {
            guard !self.isAlertPresented && self.presentedViewController == nil else { return }
            
            self.isAlertPresented = true
            let alert = UIAlertController(title: "Install Model", message: "No models are currently installed. Would you like to install one now?", preferredStyle: .alert)
            let installAction = UIAlertAction(title: "Install", style: .default) { [weak self] _ in
                self?.isAlertPresented = false
                self?.goToModelsList()
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.isAlertPresented = false
            }
            alert.addAction(installAction)
            alert.addAction(cancelAction)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func checkLocationServicesAndAuthorization() {
        guard CLLocationManager.locationServicesEnabled() else {
            showAlertToEnableLocation("Location Services Disabled", "Please enable location services in Settings.")
            return
        }
        
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .notDetermined:
            print("Requesting authorization")
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            showAlertToEnableLocation("Location Services Disabled", "Please enable location services in Settings.")
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            print("Location authorized - setup additional features")
        @unknown default:
            print("Unknown authorization status.")
        }
    }
    
    
    func showAlertToEnableLocation(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            guard !self.isAlertPresented && self.presentedViewController == nil else { return }
            
            self.isAlertPresented = true
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let settingsAction = UIAlertAction(title: "Settings", style: .default) { [weak self] (_) -> Void in
                self?.isAlertPresented = false
                guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                if UIApplication.shared.canOpenURL(settingsUrl) {
                    UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                        print("Settings opened: \(success)") // Prints true
                    })
                }
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .default) { [weak self] _ in
                self?.isAlertPresented = false
            }
            alertController.addAction(cancelAction)
            alertController.addAction(settingsAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    // Location Manager
    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
   
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update locValues here
        locValues = "\(location.coordinate.latitude), \(location.coordinate.longitude)"
        
        // Only do geocoding once, and only if we don't have a model installed
        if !hasCheckedCity {
            // Check if we need a model first
            let hasModel = defaults.array(forKey: "installed") as? [String] ?? []
            if hasModel.isEmpty {
                reverseGeocodeLocation(location)
            }
            hasCheckedCity = true
        }
        
        guard let locationStreet = manager.location else { return }
        locationStreet.placemark { [self] placemark, error in
            guard let placemark = placemark else {
                print("Error:", error ?? "nil")
                return
            }
            
            DispatchQueue.main.async {
                self.locationLabel.text = placemark.streetName ?? ""
            }
        }
    }
    
    func reverseGeocodeLocation(_ location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let error = error {
                print("Reverse geocoding failed: \(error)")
                return
            }
            if let placemark = placemarks?.first {
                let city = placemark.locality ?? ""
                let state = placemark.administrativeArea ?? ""
                let county = placemark.subAdministrativeArea ?? "" // Just add this line
                self.handleLocationUpdate(city: city, state: state, county: county) // Pass county too
            }
        }
    }
    
    //AUTO-DOWNLOAD FUNCTIONS
    
    // MARK: - Automatic Model Installation Functions
    // Add these functions to your CameraViewController class

    private func checkAndInstallModelIfNeeded() {
        // Check if any model is installed
        if let installedModels = defaults.array(forKey: "installed") as? [String],
           !installedModels.isEmpty {
            // Model exists, proceed to load it
            loadModel()
            return
        }
        
        // No model installed - wait for server data then use location-based auto-install
        waitForServerDataThenAutoInstall()
    }

    private func waitForServerDataThenAutoInstall() {
        print("⏳ Starting server data fetch...")
        
        // Start fetching server data
        fetchServerModelsData()
        
        // Set up timeout in case server fetch fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            guard let self = self else { return }
            if !self.isServerDataLoaded {
                print("⏰ Server fetch timeout, showing manual selection")
                self.presentModelInstallationSuggestion()
            }
        }
    }

    private func hasCurrentServerData() -> Bool {
        return isServerDataLoaded && !tfliteDict.isEmpty
    }

    private func proceedWithAutoInstall() {
        print("✅ Server data loaded, checking for location-based installation...")
        
        // Now that server data is loaded, trigger location-based installation
        // if we have a current location
        guard CLLocationManager.locationServicesEnabled() else {
            presentModelInstallationSuggestion()
            return
        }
        
        let authStatus = CLLocationManager.authorizationStatus()
        if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            // Get current location and install model
            if let location = locationManager.location {
                print("📍 Using current location for auto-installation")
                reverseGeocodeLocation(location)
            } else {
                print("📍 No current location, waiting for location update...")
                // Location update will come in via handleLocationUpdate
            }
        } else {
            presentModelInstallationSuggestion()
        }
    }
    
    private func fetchModelsAndAutoInstall() {
        // Wait for stringManipulation to complete, then try auto-install
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !self.tfliteDict.isEmpty {
                self.checkAndInstallModelIfNeeded()
            } else {
                // If still empty, show manual selection
                self.presentModelInstallationSuggestion()
            }
        }
    }

//    private func getCurrentLocationAndInstallModel() {
//        guard let location = locationManager.location else {
//            presentModelInstallationSuggestion()
//            return
//        }
//        
//        let geocoder = CLGeocoder()
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            guard let self = self else { return }
//            
//            if let error = error {
//                print("Reverse geocoding failed: \(error)")
//                self.presentModelInstallationSuggestion()
//                return
//            }
//            
//            guard let city = placemarks?.first?.locality else {
//                print("Could not determine city")
//                self.presentModelInstallationSuggestion()
//                return
//            }
//            
//            self.autoInstallModelForCity(city)
//        }
//    }
    
//    private func autoInstallModelForCity(_ city: String) {
//        print("Auto-installing model for city: \(city)")
//        
//        // DEBUG: Check what's in our mappings
//        debugModelMapping()
//        
//        // Get dynamic city mapping from server data
//        let cityMapping = getCityToModelMapping()
//        
//        // Clean city name and find corresponding model
//        let cleanedCity = city.components(separatedBy: CharacterSet.decimalDigits.union(.punctuationCharacters).union(.symbols)).joined()
//        
//        guard let modelFileName = cityMapping[cleanedCity] else {
//            print("No model available for city: \(city)")
//            print("Available cities: \(Array(cityMapping.keys))")
//            presentModelInstallationSuggestion()
//            return
//        }
//        
//        // Find the display name that corresponds to this model file
//        guard let displayName = tfliteDict.first(where: { $0.value == modelFileName })?.key else {
//            print("Display name not found for model: \(modelFileName)")
//            presentModelInstallationSuggestion()
//            return
//        }
//        
//        // Find the index of this model in our arrays
//        guard let modelIndex = tfliteArray.firstIndex(of: displayName) else {
//            print("Model not found in available models array: \(displayName)")
//            presentModelInstallationSuggestion()
//            return
//        }
//        
//        print("Found model for \(city): \(modelFileName) (display: \(displayName))")
//        
//        // Skip the confirmation dialog and go directly to installation
//        print("🚀 Starting automatic installation without confirmation...")
//        performAutoInstallation(modelIndex: modelIndex, cityName: cleanedCity, displayName: displayName)
//    }
    
    

//    private func getCityToModelMapping() -> [String: String] {
//        // Create mapping from current server data
//        var cityMapping: [String: String] = [:]
//        
//        for (displayName, modelFileName) in tfliteDict {
//            // Extract city from display name and map to model file name
//            if displayName.lowercased().contains("boston") {
//                cityMapping["Boston"] = modelFileName
//            } else if displayName.lowercased().contains("california") {
//                cityMapping["California"] = modelFileName
//            } else if displayName.lowercased().contains("chicago") {
//                cityMapping["Chicago"] = modelFileName
//            } else if displayName.lowercased().contains("germany") {
//                cityMapping["Germany"] = modelFileName
//            } else if displayName.lowercased().contains("london") {
//                cityMapping["London"] = modelFileName
//            } else if displayName.lowercased().contains("los angeles") {
//                cityMapping["Los Angeles"] = modelFileName
//            } else if displayName.lowercased().contains("new york") {
//                cityMapping["New York"] = modelFileName
//            } else if displayName.lowercased().contains("seattle") {
//                cityMapping["Seattle"] = modelFileName
//            } else if displayName.lowercased().contains("toronto") {
//                cityMapping["Toronto"] = modelFileName
//            } else if displayName.lowercased().contains("washington") {
//                cityMapping["Washington DC"] = modelFileName
//            }
//        }
//        
//        print("🗺️ Dynamic city mapping created:")
//        for (city, model) in cityMapping {
//            print("  \(city) → \(model)")
//        }
//        
//        return cityMapping
//    }
//    
    
    //Debugging function - DELETE LATER
    
//    private func debugModelMapping() {
//        print("🔍 DEBUG tfliteDict contents:")
//        for (key, value) in tfliteDict {
//            print("  '\(key)' → '\(value)'")
//        }
//        
//        let mapping = getCityToModelMapping()
//        print("🔍 DEBUG city mapping:")
//        for (city, model) in mapping {
//            print("  \(city) → \(model)")
//        }
//    }
    
    private func showAutoInstallationMessage(for cityName: String, completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard !self.isAlertPresented && self.presentedViewController == nil else {
                completion()
                return
            }
            
            self.isAlertPresented = true
            let alert = UIAlertController(
                title: "Welcome to All Aboard!",
                message: "We detected you're in \(cityName). We'll automatically install the best model for your location.",
                preferredStyle: .alert
            )
            
            let installAction = UIAlertAction(title: "Install Now", style: .default) { [weak self] _ in
                self?.isAlertPresented = false
                completion()
            }
            
            let chooseAction = UIAlertAction(title: "Choose Manually", style: .cancel) { [weak self] _ in
                self?.isAlertPresented = false
                self?.presentModelInstallationSuggestion()
            }
            
            alert.addAction(installAction)
            alert.addAction(chooseAction)
            self.present(alert, animated: true, completion: nil)
        }
    }

    private func performAutoInstallation(modelIndex: Int, cityName: String, displayName: String) {
        print("Starting automatic installation for \(cityName)")
        print("Model display name: \(displayName)")
        print("Model index: \(modelIndex)")
        
        DispatchQueue.main.async {
            self.setAutoInstallLoadingScreen(for: cityName)
        }
        
        // Call the enhanced download function with progress tracking
        downloadModelAutomatically(tag: modelIndex, cityName: cityName, displayName: displayName)
    }


    private func setAutoInstallLoadingScreen(for cityName: String) {
        loadingView.frame = CGRect(
            x: (view.bounds.width - 250) / 2,
            y: (view.bounds.height - 120) / 2,
            width: 250,
            height: 120
        )
        
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        loadingView.layer.cornerRadius = 15
        loadingView.clipsToBounds = true
        
        loadingLabel.frame = CGRect(x: 15, y: 15, width: 220, height: 70)
        loadingLabel.textColor = .white
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 0
        loadingLabel.text = "Installing model for \(cityName)...\n\nThis may take a few minutes.\nPlease keep the app open."
        loadingLabel.font = UIFont.systemFont(ofSize: 16)
        
        loadingIndicator.style = .whiteLarge
        loadingIndicator.frame = CGRect(x: 110, y: 85, width: 30, height: 30)
        loadingIndicator.startAnimating()
        
        loadingView.addSubview(loadingLabel)
        loadingView.addSubview(loadingIndicator)
        
        view.addSubview(loadingView)
        
        // Bring loading view to front
        view.bringSubviewToFront(loadingView)
    }
    
    
    // Enhanced download function specifically for auto-installation
    private func downloadModelAutomatically(tag: Int, cityName: String, displayName: String) {
        DispatchQueue.global(qos: .background).async { [self] in
            let category = displayName // Use the display name as category
            guard let modelFileName = tfliteDict[category] else {
                print("❌ Model file name not found for category: \(category)")
                DispatchQueue.main.async {
                    self.removeLoadingScreen()
                    self.showAutoInstallationFailure(for: cityName)
                }
                return
            }
            
            print("========")
            print("📥 Auto-downloading model for category: '\(category)'")
            print("📄 Model file name: '\(modelFileName)'")
            print("🏙️ City: \(cityName)")
            print("========")
            
            let documentsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelDestinationURL = documentsURL.appendingPathComponent(modelFileName + ".tflite")
            let labelsDestinationURL = documentsURL.appendingPathComponent(modelFileName + "_lb.txt")
            
            // Remove existing files if they exist
            try? FileManager.default.removeItem(at: modelDestinationURL)
            try? FileManager.default.removeItem(at: labelsDestinationURL)
            
            let downloadGroup = DispatchGroup()
            var modelDownloadSuccess = false
            var labelsDownloadSuccess = false
            var downloadError: String?
            var isTimedOut = false
            
            // Add timeout for downloads
            DispatchQueue.main.asyncAfter(deadline: .now() + 120.0) { // 2 minute timeout
                if !modelDownloadSuccess || !labelsDownloadSuccess {
                    print("⏰ Download timeout - cancelling")
                    isTimedOut = true
                    DispatchQueue.main.async {
                        if self.loadingView.superview != nil {
                            self.removeLoadingScreen()
                            self.showAutoInstallationFailure(for: cityName)
                        }
                    }
                }
            }
            
            // Download .tflite model file with progress updates
            let modelURLString = modelsBaseURL + modelFileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + ".tflite"
            print("🔗 Model URL: \(modelURLString)")
            
            if let modelURL = URL(string: modelURLString) {
                downloadGroup.enter()
                
                // Create download task with progress tracking
                let downloadTask = URLSession.shared.downloadTask(with: modelURL) { [weak self] tempURL, response, error in
                    defer { downloadGroup.leave() }
                    guard let self = self, !isTimedOut else { return }
                    
                    if let error = error {
                        print("❌ Failed to download model file: \(error)")
                        downloadError = "Model download failed: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let tempURL = tempURL else {
                        print("❌ No temporary URL for downloaded model")
                        downloadError = "No temporary download location"
                        return
                    }
                    
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: modelDestinationURL)
                        
                        // Verify file size to ensure it's actually downloaded
                        let fileSize = (try FileManager.default.attributesOfItem(atPath: modelDestinationURL.path)[.size] as? Int64) ?? 0
                        print("📊 Model file size: \(fileSize) bytes (\(fileSize / 1_000_000) MB)")
                        
                        if fileSize > 1_000_000 { // At least 1MB
                            print("✅ Model file downloaded successfully to: \(modelDestinationURL.path)")
                            modelDownloadSuccess = true
                        } else {
                            print("❌ Model file seems too small, might be invalid")
                            downloadError = "Downloaded model file is too small or corrupted"
                            try? FileManager.default.removeItem(at: modelDestinationURL)
                        }
                    } catch {
                        print("❌ Failed to move model file: \(error)")
                        downloadError = "Failed to save model file: \(error.localizedDescription)"
                    }
                }
                
                downloadTask.resume()
            }
            
            // Download labels file
            let labelsURLString = "https://vrt.partners.org/AllAboard_Android_Modelfiles/Labelmaps/" + modelFileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + "_lb.txt"
            print("🔗 Labels URL: \(labelsURLString)")
            
            if let labelsURL = URL(string: labelsURLString) {
                downloadGroup.enter()
                let downloadTask = URLSession.shared.downloadTask(with: labelsURL) { [weak self] tempURL, response, error in
                    defer { downloadGroup.leave() }
                    guard let self = self, !isTimedOut else { return }
                    
                    if let error = error {
                        print("❌ Failed to download labels file: \(error)")
                        downloadError = downloadError ?? "Labels download failed: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let tempURL = tempURL else {
                        print("❌ No temporary URL for downloaded labels")
                        downloadError = downloadError ?? "No temporary labels location"
                        return
                    }
                    
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: labelsDestinationURL)
                        
                        // Verify labels file content
                        let rawData = try Data(contentsOf: labelsDestinationURL)
                        if let content = String(data: rawData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            if content.hasPrefix("<") || content.contains("<!DOCTYPE") {
                                print("❌ Labels file contains HTML - download failed")
                                downloadError = downloadError ?? "Labels file download returned HTML error page"
                                try? FileManager.default.removeItem(at: labelsDestinationURL)
                            } else {
                                print("✅ Labels file downloaded successfully to: \(labelsDestinationURL.path)")
                                print("📄 Labels content preview: \(content.prefix(100))...")
                                labelsDownloadSuccess = true
                            }
                        }
                    } catch {
                        print("❌ Failed to move/validate labels file: \(error)")
                        downloadError = downloadError ?? "Failed to save labels file: \(error.localizedDescription)"
                    }
                }
                downloadTask.resume()
            }
            
            // Handle completion
            downloadGroup.notify(queue: .main) {
                guard !isTimedOut else { return }
                
                print("📋 Download completed - Model: \(modelDownloadSuccess), Labels: \(labelsDownloadSuccess)")
                
                if let error = downloadError {
                    print("❌ Download error: \(error)")
                }
                
                if modelDownloadSuccess && labelsDownloadSuccess {
                    // Save model path
                    var dict = [String: String]()
                    if let defaultDict = self.defaults.value(forKey: "modelPath") as? [String: String] {
                        dict = defaultDict
                    }
                    dict[category] = modelDestinationURL.path
                    self.defaults.setValue(dict, forKey: "modelPath")
                    self.defaults.setValue(category, forKey: "selectedModel")
                    
                    // Update installed array
                    self.installedArr.append(category)
                    self.defaults.setValue(self.installedArr, forKey: "installed")
                    
                    // Save labels path
                    let categoryLabel = category + "_lb.txt"
                    self.installedPathArr[categoryLabel] = labelsDestinationURL.path
                    self.defaults.setValue(categoryLabel, forKey: "selectedLabel")
                    self.defaults.setValue(self.installedPathArr, forKey: "installedPath")
                    
                    // Remove from available list
                    if let index = self.tfliteArray.firstIndex(of: category) {
                        self.tfliteArray.remove(at: index)
                    }
                    
                    print("✅ Auto-installation completed successfully!")
                    
                    // Remove loading screen and show success
                    self.removeLoadingScreen()
                    self.showAutoInstallationSuccess(for: cityName)
                    
                    // Load the model
                    self.loadModel()
                    
                } else {
                    print("❌ Auto-installation failed")
                    self.removeLoadingScreen()
                    self.showAutoInstallationFailure(for: cityName)
                }
            }
        }
    }

    private func showAutoInstallationSuccess(for cityName: String) {
        DispatchQueue.main.async {
            guard !self.isAlertPresented && self.presentedViewController == nil else { return }
            
            self.isAlertPresented = true
            let alert = UIAlertController(
                title: "Installation Complete! 🎉",
                message: "The \(cityName) model has been successfully installed. You're ready to use All Aboard!",
                preferredStyle: .alert
            )
            
            let okAction = UIAlertAction(title: "Get Started", style: .default) { [weak self] _ in
                self?.isAlertPresented = false
            }
            
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
    }


    private func showAutoInstallationFailure(for cityName: String) {
        DispatchQueue.main.async {
            guard !self.isAlertPresented && self.presentedViewController == nil else { return }
            
            self.isAlertPresented = true
            let alert = UIAlertController(
                title: "Installation Failed",
                message: "We couldn't install the \(cityName) model automatically. Please try selecting a model manually from the list.",
                preferredStyle: .alert
            )
            
            let retryAction = UIAlertAction(title: "Choose Model", style: .default) { [weak self] _ in
                self?.isAlertPresented = false
                self?.presentModelInstallationSuggestion()
            }
            
            alert.addAction(retryAction)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    private func handleLocationUpdate(city: String, state: String, county: String) {
        print("Location: \(city), \(county), \(state)")
        
        // Check if we already have a model installed
        if let installedModels = defaults.array(forKey: "installed") as? [String],
           !installedModels.isEmpty {
            print("✅ Model already installed: \(installedModels)")
            return
        }
        
        // Only proceed if server data is loaded
        guard isServerDataLoaded && !tfliteDict.isEmpty else {
            print("⏳ Server data not ready yet, will try later")
            return
        }
        
        // Check if we already processed this city
        if let lastCity = defaults.string(forKey: "lastCity"), lastCity == city {
            print("📍 Already processed city: \(city)")
            return
        }
        
        defaults.set(city, forKey: "lastCity")
        
        print("🔄 Triggering auto-installation for: \(city), \(county), \(state)")
        autoInstallModelForLocation(city: city, state: state, county: county)
    }
    
    private func autoInstallModelForLocation(city: String, state: String, county: String) {
        print("🔍 Finding model for: \(city), \(county), \(state)")
        print("🔍 tfliteDict contents: \(tfliteDict)")
        
        // Create search keywords - just add county to existing logic
        var keywords = [city.lowercased()]
        
        // Add county keywords
        if !county.isEmpty {
            keywords.append(county.lowercased())
            // Special case for California counties
            if county.lowercased().contains("alameda") || county.lowercased().contains("contra costa") {
                keywords.append("california")
                keywords.append("ac")
            }
        }
        
        // Add state-specific keywords (your existing logic)
        switch state.lowercased() {
        case "massachusetts": keywords.append("boston")
        case "california": keywords.append("california")
        case "illinois": keywords.append("chicago")
        case "washington": keywords.append("seattle")
        case "new york": keywords.append("new york")
        case "ontario": keywords.append("toronto")
        case "district of columbia": keywords.append("washington dc")
        default: keywords.append(state.lowercased())
        }
        
        print("🔎 Checking keywords: \(keywords)")
        
        // Find first model that matches any keyword (your existing logic unchanged)
        for keyword in keywords {
            print("🔍 Searching for keyword: '\(keyword)'")
            for (displayName, modelFileName) in tfliteDict {
                print("🔍 Checking '\(keyword)' in '\(displayName)'")
                if displayName.lowercased().contains(keyword) {
                    print("✅ Found: \(displayName)")
                    
                    guard let modelIndex = tfliteArray.firstIndex(of: displayName) else {
                        print("❌ Model index not found for: \(displayName)")
                        presentModelInstallationSuggestion()
                        return
                    }
                    
                    print("🚀 Starting installation with index: \(modelIndex)")
                    performAutoInstallation(modelIndex: modelIndex, cityName: city, displayName: displayName)
                    return
                }
            }
        }
        
        print("❌ No model found for keywords: \(keywords)")
        presentModelInstallationSuggestion()
    }
    
//    private func suggestModelDownloadBasedOn(city: String) {
//        let cleanedCity = city.components(separatedBy: CharacterSet.decimalDigits.union(.punctuationCharacters).union(.symbols)).joined()
//        
//        // Get dynamic city mapping from server data
//        let cityMapping = getCityToModelMapping()
//        
//        guard let modelFileName = cityMapping[cleanedCity] else {
//            print("No model available for city: \(city)")
//            print("Available cities: \(Array(cityMapping.keys))")
//            presentModelInstallationSuggestion()
//            return
//        }
//        
//        // Find the display name that corresponds to this model file
//        guard let displayName = tfliteDict.first(where: { $0.value == modelFileName })?.key else {
//            print("Display name not found for model: \(modelFileName)")
//            presentModelInstallationSuggestion()
//            return
//        }
//        
//        // Find the index of this model in our arrays
//        guard let modelIndex = tfliteArray.firstIndex(of: displayName) else {
//            print("Model not found in available models array: \(displayName)")
//            presentModelInstallationSuggestion()
//            return
//        }
//        
//        print("Found model for \(city): \(modelFileName) (display: \(displayName))")
//        presentModelSuggestionAlert(modelIndex: modelIndex)
//    }
    
    
    
    func stringManipulation() {
        // Clear old data
        tfliteArray.removeAll()
        tfliteDict.removeAll()
        
        // Only process if we have data from server
        guard !tfliteArrayJSON.isEmpty else {
            print("⚠️ No server data yet, skipping string manipulation")
            return
        }
        
        print("🔧 Processing server data...")
        for i in 0..<tfliteArrayJSON.count {
            var str = tfliteArrayJSON[i]
            str = str.replacingOccurrences(of: "_", with: " ")
            str = String(str.prefix(str.count - 4)) // Remove the _XXX part
            tfliteArray.append(str)
            tfliteDict[str] = tfliteArrayJSON[i]
            print("🔧 Model: '\(tfliteArrayJSON[i])' → Display: '\(str)'")
        }
        
        defaults.setValue(tfliteDict, forKey: "tfliteDict")
        
        if let installedModels = defaults.array(forKey: "installed") as? [String] {
            installedArr = installedModels
            var indexes = [String]()
            for i in 0..<tfliteArray.count {
                if !installedArr.contains(tfliteArray[i]) {
                    indexes.append(tfliteArray[i])
                }
            }
            tfliteArray = indexes
            if let dict = defaults.value(forKey: "installedPath") as? [String: String] {
                installedPathArr = dict
            }
        }
        
        print("🎯 Final tfliteDict after server data:")
        for (key, value) in tfliteDict {
            print("  '\(key)' → '\(value)'")
        }
    }
    
    func updateCounter() {
        counter+=1
        if (counter >= 2) {
            DispatchQueue.main.async {
                self.loadingIndicator.stopAnimating()
                self.removeLoadingScreen()
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "modelDataHandler"), object: nil)
            }
        }
    }
    
    func presentModelSuggestionAlert(modelIndex: Int) {
        DispatchQueue.main.async {
            guard !self.isAlertPresented && self.presentedViewController == nil else { return }
            
            self.isAlertPresented = true
            let alert = UIAlertController(title: "Configure App", message: "Based on your current location, install package for \(self.tfliteArray[modelIndex])?", preferredStyle: .alert)
            let downloadAction = UIAlertAction(title: "Install", style: .default) { [weak self] _ in
                self?.isAlertPresented = false
                self?.downloadModel(tag: modelIndex)
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.isAlertPresented = false
            }
            alert.addAction(downloadAction)
            alert.addAction(cancelAction)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func downloadModel(tag: Int) {
        DispatchQueue.main.async {
            self.setLoadingScreen()
        }
        
        DispatchQueue.global(qos: .background).async { [self] in
            let category = tfliteArray[tag]
            let modelFileName = tfliteDict[category]!
            
            print("========")
            print("Downloading model for category: \(category)")
            print("Model file name: \(modelFileName)")
            print("========")
            
            // Download .tflite model file
            let modelURLString = modelsBaseURL + modelFileName + ".tflite"
            
            if let modelURL = URL(string: modelURLString) {
                // Use URLSession for downloading with proper error handling
                let downloadTask = URLSession.shared.downloadTask(with: modelURL) { [weak self] tempURL, response, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Failed to download model file: \(error)")
                        DispatchQueue.main.async {
                            self.removeLoadingScreen()
                        }
                        return
                    }
                    
                    guard let tempURL = tempURL else {
                        print("No temporary URL for downloaded model")
                        DispatchQueue.main.async {
                            self.removeLoadingScreen()
                        }
                        return
                    }
                    
                    // Move file to documents directory
                    do {
                        let documentsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        let destinationURL = documentsURL.appendingPathComponent(modelFileName + ".tflite")
                        
                        // Remove existing file if it exists
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        
                        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                        
                        print("Model file downloaded to: \(destinationURL.path)")
                        
                        // Save model path
                        var dict = [String: String]()
                        if let defaultDict = self.defaults.value(forKey: "modelPath") as? [String: String] {
                            dict = defaultDict
                        }
                        dict[category] = destinationURL.path
                        self.defaults.setValue(dict, forKey: "modelPath")
                        self.defaults.setValue(category, forKey: "selectedModel")
                        
                        // Update installed array
                        self.installedArr.append(category)
                        self.defaults.setValue(self.installedArr, forKey: "installed")
                        
                        // Remove from available list
                        if let index = self.tfliteArray.firstIndex(of: category) {
                            self.tfliteArray.remove(at: index)
                        }
                        
                        self.updateCounter()
                        
                    } catch {
                        print("Failed to move model file: \(error)")
                        DispatchQueue.main.async {
                            self.removeLoadingScreen()
                        }
                    }
                }
                downloadTask.resume()
            }
            
            // Download labels file
            let labelsURLString = labelsURL + modelFileName + "_lb.txt"
            let categoryLabel = category + "_lb.txt"
            
            print("========")
            print("Downloading labels from: \(labelsURLString)")
            print("Category label: \(categoryLabel)")
            print("========")
            
            if let labelsURL = URL(string: labelsURLString) {
                let downloadTask = URLSession.shared.downloadTask(with: labelsURL) { [weak self] tempURL, response, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Failed to download labels file: \(error)")
                        return
                    }
                    
                    guard let tempURL = tempURL else {
                        print("No temporary URL for downloaded labels")
                        return
                    }
                    
                    // Move file to documents directory
                    do {
                        let documentsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        let destinationURL = documentsURL.appendingPathComponent(modelFileName + "_lb.txt")
                        
                        // Remove existing file if it exists
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        
                        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                        
                        print("Labels file downloaded to: \(destinationURL.path)")
                        self.installedPathArr[categoryLabel] = destinationURL.path
                        self.defaults.setValue(categoryLabel, forKey: "selectedLabel")
                        self.defaults.setValue(self.installedPathArr, forKey: "installedPath")
                        self.updateCounter()
                        
                    } catch {
                        print("Failed to move labels file: \(error)")
                    }
                }
                downloadTask.resume()
            }
        }
    }
    
    private func setLoadingScreen() {
        print("Setting up the loading screen...")
        loadingView.frame = CGRect(x: (view.bounds.width) / 2,
                                   y: (view.bounds.height) / 2,
                                   width: 150, height: 150)
        
        loadingView.clipsToBounds = true
        
        loadingIndicator.style = .whiteLarge
        loadingIndicator.frame = CGRect(x: (loadingView.bounds.width - loadingIndicator.bounds.width - 100) / 2,
                                        y: (loadingView.bounds.height - loadingIndicator.bounds.height - 50) / 2,
                                        width: loadingIndicator.bounds.width,
                                        height: loadingIndicator.bounds.height)
        loadingIndicator.startAnimating()
        
        loadingView.addSubview(loadingIndicator)
        
        DispatchQueue.main.async {
            self.view.addSubview(self.loadingView)
            print("Loading screen should now be visible.")
        }
    }
    
    
    private func removeLoadingScreen() {
        DispatchQueue.main.async {
            print("Attempting to remove the loading screen...")
            self.loadingIndicator.stopAnimating()
            self.loadingView.removeFromSuperview()
            print("Loading screen should now be removed.")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraFeedManager.checkCameraConfigurationAndStartSession()
        NotificationCenter.default.addObserver(self, selector: #selector(stopPlayer), name: NSNotification.Name(rawValue: "stopPlayer"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.loadModel), name: NSNotification.Name(rawValue: "modelDataHandler"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(beforeEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AppUtility.lockOrientation(.all)
        cameraFeedManager.stopSession()
        NotificationCenter.default.removeObserver(self)
        isAlertPresented = false // Reset flag when view disappears
    }
    
    // Extended text recognition configuration
    func configureTextRecognition() {
        textDetectionRequest = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], let strongSelf = self else { return }
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: " ")
            
            DispatchQueue.main.async {
                print("OCR Text Detected: \(recognizedText)") // Print detected text for debugging
                if strongSelf.shouldSpeakText(recognizedText) {
                    strongSelf.speakText(recognizedText)
                    strongSelf.preSpeakText = recognizedText
                    strongSelf.lastSpeakTime = Date()
                }
                strongSelf.handleRecognizedText(recognizedText) // Updated method to handle recognized text
            }
        }
        textDetectionRequest.recognitionLevel = .accurate
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // MARK: – Location & Model Preparation
        locationManager.delegate = self
        checkLocationServicesAndAuthorization()
        configureLocationManager()
        // Removed stringManipulation() - will run after server data loads
        
        // MARK: – OCR & Text Recognition Setup
        configureTextRecognition()
        setupTextDetection()
        
        // MARK: – Search Bar & Speech Authorization
        searchBar.delegate = self
        searchBar.isHidden = true
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    self.searchBar.setImage(nil, for: .bookmark, state: .normal)
                @unknown default:
                    break
                }
            }
        }
        
        // MARK: – Audio Session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("⚠️ Failed to configure AVAudioSession:", error)
        }
        
        // MARK: – Start CoreMotion updates for "upright" check

        // Replace your CoreMotion block in viewDidLoad with this:
        motionManager.deviceMotionUpdateInterval = 0.2  // Responsive motion detection
        var lastSonarCheck: Date = Date.distantPast

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self else { return }
            
            // Only call playSonar every 0.5 seconds to prevent spillage but keep responsiveness
            let now = Date()
            guard now.timeIntervalSince(lastSonarCheck) > 0.5 else { return }
            lastSonarCheck = now
            
            self.playSonar()
        }
        
        // initial sonar attempt
        playSonar()
        
        // MARK: – Mic Icon & Tooltip Setup
        micImageView.translatesAutoresizingMaskIntoConstraints = false
        micImageView.tintColor = .red
        micImageView.isHidden = true
        micImageView.contentMode = .scaleAspectFit
        micImageView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        micImageView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        micImageView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        micImageView.layer.cornerRadius = 25
        micImageView.clipsToBounds = true
        view.addSubview(micImageView)
        view.addSubview(tooltipLabel)
        
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleMicLongPress))
        searchBar.setImage(UIImage(systemName: "mic.fill"), for: .bookmark, state: .normal)
        searchBar.addGestureRecognizer(longPressRecognizer)
        
        NSLayoutConstraint.activate([
            micImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            tooltipLabel.centerXAnchor.constraint(equalTo: micImageView.centerXAnchor),
            tooltipLabel.bottomAnchor.constraint(equalTo: micImageView.topAnchor, constant: -10),
            tooltipLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            tooltipLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // MARK: – Search Bar Styling
        searchBar.transform = CGAffineTransform(scaleX: 1, y: 1.5)
        searchBar.searchTextField.font = searchBar.searchTextField.font?.withSize(18)
        
        // MARK: – Keyboard Notifications
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // MARK: – Settings & Read-Sign Button Styling
        settingsButton.addTarget(self, action: #selector(gotoSettings), for: .touchUpInside)
        settingsButton.semanticContentAttribute = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
            ? .forceLeftToRight
            : .forceRightToLeft
        settingsButton.setTitleColor(.black, for: .normal)
        settingsButton.backgroundColor = .clear
        settingsButton.layer.cornerRadius = 10
        settingsButton.layer.borderWidth = 1
        settingsButton.layer.borderColor = UIColor.black.cgColor
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        readSignButton.semanticContentAttribute = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
        readSignButton.setTitleColor(.white, for: .normal)
        readSignButton.backgroundColor = .black
        readSignButton.layer.cornerRadius = 10
        readSignButton.layer.borderWidth = 1
        readSignButton.layer.borderColor = UIColor.black.cgColor
        readSignButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        // MARK: – Camera Feed & Overlay
        cameraFeedManager.delegate = self
        overlayView.clearsContextBeforeDrawing = true
        
        // MARK: – Final Location Permissions
        locationManager.requestAlwaysAuthorization()
        locationManager.requestWhenInUseAuthorization()
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
        }
    }
    
    // Handle the long press gesture on the mic button
    @objc func handleMicLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            startListening()
        case .ended, .cancelled:
            stopListening()
        default:
            break
        }
    }
    
    func showTooltip() {
        UIView.animate(withDuration: 0.5, animations: {
            self.tooltipLabel.alpha = 1 // Show the tooltip
        }) { _ in
            // After 2 seconds, hide the tooltip
            UIView.animate(withDuration: 0.5, delay: 2.5, options: [], animations: {
                self.tooltipLabel.alpha = 0
            }, completion: nil)
        }
    }
    
    deinit {
      motionManager.stopDeviceMotionUpdates()
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
      NotificationCenter.default.removeObserver(self)
    }

    
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardHeight = keyboardFrame.cgRectValue.height
            self.view.frame.origin.y = -keyboardHeight // Adjust this value as needed
        }
    }
    @objc func keyboardWillHide(notification: NSNotification) {
        self.view.frame.origin.y = 0
    }
    
    private func setupTextDetection() {
        textDetectionRequest = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            
            DispatchQueue.main.async {
                self?.handleRecognizedText(recognizedText)
            }
        }
        textDetectionRequest.recognitionLevel = .accurate
    }
    
    // best version
    private func handleRecognizedText(_ text: String) {
        DispatchQueue.main.async {
            if text.isEmpty {
                
                print("Scanning...")
            } else {
                
                self.lastRecognizedText = text
                
                if let query = self.searchBar.text, !query.isEmpty, text.lowercased().contains(query.lowercased()) {
                    let foundMessage = "\(query) found."
                    self.enqueueTextForSpeaking(foundMessage)
                    self.isCurrentlySearching = false
                }
            }
        }
    }
    
    private func searchForQuery(_ text: String, query: String) {
        speechSynthesizer.stopSpeaking(at: .immediate)// Stop any ongoing speech immediately
        player?.stop()
        
        if text.lowercased().contains(query.lowercased()) {
            isCurrentlySearching = false  // Update search status to stop further searches
            
        } else {
            if isCurrentlySearching {
                print("Detected text (sFQ): \(text)")
                print("Searching...")
            }
        }
    }
    
    func radiansToDegrees(_ radians: Double) -> Double {
        return radians * (180.0 / Double.pi)
    }
    
    @objc func beforeEnterBackground() {
        let dict = defaults.value(forKey: "tfliteDict") as? [String: String]
        let selectedModel = defaults.string(forKey: "selectedModel") ?? ""
        let modelName: String = dict?[selectedModel] ?? ""
        if !(imageDetected) {
            labelMessage = "-99 - Max, -99 - Min, \(String(modelName.prefix(3))), \(locValues)"
        }
        if (modelName != "") {
            MobClick.beginEvent("distance", label: labelMessage)
            MobClick.endEvent("distance", label: labelMessage)
        }
    }
    
    @objc func applicationDidBecomeActive() {
        imageDetected = false
        minValue = CGFloat(10000.0)
        maxValue = CGFloat(0.0)
    }
    
    // Add this function to CameraViewController
    private func clearOldModelDataAndAutoInstall() {
        print("🧹 Clearing old model data...")
        
        // Clear all old model references
        defaults.removeObject(forKey: "installed")
        defaults.removeObject(forKey: "selectedModel")
        defaults.removeObject(forKey: "selectedLabel")
        defaults.removeObject(forKey: "modelPath")
        defaults.removeObject(forKey: "installedPath")
        
        // Reset arrays
        installedArr.removeAll()
        installedPathArr.removeAll()
        
        // Now trigger auto-installation
        checkAndInstallModelIfNeeded()
    }
    
    @objc func loadModel() {
        print("modelDataHandler - Loading model...")
        
        // Double-check we have valid model data
        guard let installedModels = defaults.array(forKey: "installed") as? [String],
              !installedModels.isEmpty,
              let selectedModel = defaults.string(forKey: "selectedModel"),
              let modelPath = (defaults.value(forKey: "modelPath") as? [String: String])?[selectedModel],
              FileManager.default.fileExists(atPath: modelPath) else {
            print("No valid models found, triggering auto-installation")
            clearOldModelDataAndAutoInstall()
            return
        }
        
        print("✅ Loading valid model: \(selectedModel) from \(modelPath)")
        modelDataHandler = ModelDataHandler(modelFileInfo: MobileNetSSD.modelInfo, labelsFileInfo: MobileNetSSD.labelsInfo)
        if (modelDataHandler == nil) {
            // Model file is corrupted, clear and reinstall
            clearOldModelDataAndAutoInstall()
        }
    }
    
    func displayAlert() {
        DispatchQueue.main.async {
            guard !self.isAlertPresented && self.presentedViewController == nil else { return }
            
            self.isAlertPresented = true
            let alertController = UIAlertController(
                title: "Model Loading Failed",
                message: "Let's install a model for your location.",
                preferredStyle: UIAlertController.Style.alert
            )
            let action = UIAlertAction(title: "Install Model", style: .default) { [weak self] action in
                self?.isAlertPresented = false
                self?.defaults.removeObject(forKey: "installed")
                self?.defaults.removeObject(forKey: "selectedModel")
                self?.checkAndInstallModelIfNeeded()
            }
            alertController.addAction(action)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func goToModelsList() {
        let vc = MenuTableVC()
        self.present(vc, animated: false, completion: nil)
    }
    
    @objc func stopPlayer() {
        player?.stop()
    }
    
    func defaultDevice() -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInDuoCamera,
                                                for: AVMediaType.video,
                                                position: .back) {
            return device // use dual camera on supported devices
        } else if let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,
                                                       for: AVMediaType.video,
                                                       position: .back) {
            return device // use default back facing camera otherwise
        } else {
            fatalError("All supported devices are expected to have at least one of the queried capture devices.")
        }
    }
    
    func configureCaptureSession(_ completionHandler: ((_ success: Bool) -> Void)) {
        var success = false
        defer { completionHandler(success) } // Ensure all exit paths call completion handler.
        
        // Get video input for the default camera.
        let videoCaptureDevice = defaultDevice()
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            print("Unable to obtain video input for default camera.")
            return
        }
        
        // Create and configure the photo output.
        let capturePhotoOutput = AVCapturePhotoOutput()
        capturePhotoOutput.isHighResolutionCaptureEnabled = true
        capturePhotoOutput.isLivePhotoCaptureEnabled = capturePhotoOutput.isLivePhotoCaptureSupported
        
        // Make sure inputs and output can be added to session.
        guard self.captureSession.canAddInput(videoInput) else { return }
        guard self.captureSession.canAddOutput(capturePhotoOutput) else { return }
        
        // Configure the session.
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = AVCaptureSession.Preset.photo
        self.captureSession.addInput(videoInput)
        self.captureSession.addOutput(capturePhotoOutput)
        self.captureSession.commitConfiguration()
        
        self.capturePhotoOutput = capturePhotoOutput
        success = true
    }
    
    func setZoom(toFactor vZoomFactor: CGFloat) {
        var device: AVCaptureDevice = defaultDevice()
        var error:NSError!
        do{
            try device.lockForConfiguration()
            defer {device.unlockForConfiguration()}
            if (vZoomFactor <= device.activeFormat.videoMaxZoomFactor && vZoomFactor >= 1.0){
                // device.ramp(toVideoZoomFactor: vZoomFactor, withRate: 1)
                device.videoZoomFactor = vZoomFactor
            }
            else if (vZoomFactor <= 1.0){ NSLog("Unable to set videoZoom: (max %f, asked %f)", device.activeFormat.videoMaxZoomFactor, vZoomFactor) }
            else{ NSLog("Unable to set videoZoom: (max %f, asked %f)", device.activeFormat.videoMaxZoomFactor, vZoomFactor) }
        }
        catch error as NSError{ NSLog("Unable to set videoZoom: %@", error.localizedDescription) }
        catch _{ NSLog("Unable to set videoZoom: %@", error.localizedDescription) }
    }
    
    func keepShowingCameraNeededAlert () {
        let alertController = UIAlertController(title: "Hey there!", message: "We need your camera permission to work.", preferredStyle: UIAlertController.Style.alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: {(alert: UIAlertAction!) in self.keepShowingCameraNeededAlert()}))
        self.present(alertController, animated: true, completion: nil)
    }
    
    func checkCameraAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            //The user has previously granted access to the camera.
            completionHandler(true)
            
        case .notDetermined:
            // The user has not yet been presented with the option to grant video access so request access.
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { success in
                completionHandler(success)
            })
            
        case .denied:
            // The user has previously denied access.
            completionHandler(false)
            
        case .restricted:
            // The user doesn't have the authority to request access e.g. parental restriction.
            completionHandler(false)
        @unknown default:
            fatalError()
        }
    }
    
    @objc func gotoSettings() {
        let vc = SettingsVC()
        self.present(vc, animated: false, completion: nil)
    }
   
    func getDistance(from actualWidth: CGFloat, bbWidth: CGFloat, viewWidth: CGFloat, angle: CGFloat) -> String {
        
        let alpha = (bbWidth * angle) / viewWidth / 2
        let alphaRad = deg2rad(Double(alpha))
        
        let distance = ( ( (actualWidth / 2) / tan(CGFloat(alphaRad)) ) / 100 ) // convert to m from cm
        
        if (distance > maxValue) {
            maxValue = distance
        }
        
        if (distance < minValue) {
            minValue = distance
        }
        
        let formattedSignDistance = String(format: "%.2f", distance)
        
        //        print("Current distance = \(formattedDistance)")
        return formattedSignDistance
    }
    
    func deg2rad(_ number: Double) -> Double {
        return number * .pi / 180
    }

    
    let beepRates: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0]
    let soundFlag = true

    // Determines the distance category
    func diffDistance() -> Int {
        guard let distance = Float(distance_info) else {
            print("Invalid distance_info value: \(distance_info)")
            return 0
        }
        
        if distance >= 10.0 {
            return 1
        } else if distance >= 7.0 {
            return 2
        } else if distance >= 3.0 {
            return 3
        } else {
            return 4
        }
    }

    // Adjusts beep rate and vibration based on distance

    // Function to play beep sound at a specific rate
    
    // MARK: Read Sign OCR Methods
    
    // Function to initiate speaking text
    // Handling text-to-speech
    private func speakText(_ text: String) {
        let utteranceText = text.count > maxLetters ? String(text.prefix(maxLetters)) : text
        let utterance = AVSpeechUtterance(string: utteranceText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(utterance)
    }
    
    private func shouldSpeakText(_ newText: String) -> Bool {
        let currentTime = Date()
        return newText != preSpeakText && currentTime.timeIntervalSince(lastSpeakTime) >= maxTime
    }
    
    func readAll(_ recognizedText: String) {
        let maxLetters = 200  // Limit the length of spoken text
        var textToSpeak = recognizedText
        if recognizedText.count > maxLetters {
            textToSpeak = String(recognizedText.prefix(maxLetters))
        }
        speakText(textToSpeak)
    }
    
    // Properties for managing speech
    var searchTimer: Timer?
    var lastSpokenQuery: String?
    
    
    func updateOverlayVisibility() {
        // Hide the overlay when OCR is enabled, show it otherwise
        overlayView.isHidden = isOCREnabled
    }
    
    @IBAction func readSignButtonTapped(_ sender: UIButton) {
        // Toggle the OCR enabled state
        isOCREnabled.toggle()
        updateUIForOCRState()
        
        speechSynthesizer.stopSpeaking(at: .immediate)
        searchBar.resignFirstResponder()
        searchBar.text = ""
        
        // Clear the overlayView and redraw
        //        overlayView.objectOverlays = []
        DispatchQueue.main.async {
            print("isOCREnabled = \(self.isOCREnabled.description)")
            self.overlayView.objectOverlays.removeAll()
            self.overlayView.layer.sublayers?.removeAll()
            self.overlayView.setNeedsDisplay()
            self.result = nil
        }
    }
    
    // 2) Your full updateUIForOCRState, now pausing/resuming sonar

    private func updateUIForOCRState() {
        // NEW: pause sonar on OCR, resume when OCR stops
        if isOCREnabled {
            sonarPlayer?.pause()
        } else {
            sonarPlayer?.play()
        }
        
        if isOCREnabled {
            showTooltip()
        }
        
        DispatchQueue.main.async {
            self.readSignButton.setTitle(self.isOCREnabled ? "Stop Reading" : "Read Sign", for: .normal)
            self.locationLabel.isHidden        = self.isOCREnabled
            self.currentLocationLabel.isHidden = self.isOCREnabled
            self.searchBar.isHidden            = !self.isOCREnabled
            self.settingsButton.isHidden       = self.isOCREnabled
        }
    }


       /// Returns true only when the device is held upright (portrait).
    private func isPhoneUpright() -> Bool {
      guard let gravity = motionManager.deviceMotion?.gravity else { return false }
      return abs(gravity.x) < 0.3
    }


    
    /// Returns true only when the device is held in portrait (physically)
    private func isPhonePortrait() -> Bool {
        guard let g = motionManager.deviceMotion?.gravity else { return false }
        // In portrait, gravity.y dominates; in landscape, gravity.x dominates
        return abs(g.y) > abs(g.x)
    }

    private func playSonar() {
        // 1️⃣ Never override a playing beep
        if player?.isPlaying == true {
            sonarPlayer?.stop()
            return
        }

        // 2️⃣ Get gravity values with stronger filtering
        guard let gravity = motionManager.deviceMotion?.gravity else { return }
        
        // More forgiving thresholds - allows reasonable angles
        let isReallyUpright = abs(gravity.z) < 0.5 && abs(gravity.y) > 0.5  // Allow more tilt
        let isReallyPortrait = abs(gravity.y) > abs(gravity.x)  // Just needs to be more vertical than horizontal
        
        // 3️⃣ Add condition to ensure phone is upright portrait (not reverse portrait)
        let isUprightPortrait = gravity.y < -0.5  // Negative y means top of phone points up
        
        let shouldPlay = isReallyUpright && isReallyPortrait && isUprightPortrait && !isOCREnabled
        
        if shouldPlay {
            // Only start if not already playing
            if sonarPlayer?.isPlaying != true {
                guard let sonarURL = Bundle.main.url(forResource: "sonar", withExtension: "mp3") else { return }
                
                do {
                    sonarPlayer?.stop()
                    sonarPlayer = try AVAudioPlayer(contentsOf: sonarURL)
                    sonarPlayer?.numberOfLoops = -1
                    sonarPlayer?.volume = 0.5
                    sonarPlayer?.prepareToPlay()
                    sonarPlayer?.play()
                } catch {
                    print("Failed to play sonar: \(error)")
                }
            }
        } else {
            // Immediately stop when conditions not met
            sonarPlayer?.stop()
            sonarPlayer = nil
        }
    }
    
    // 3) A new playBeepSound(named:) + delegate to keep sonar paused during beeps
    func playBeepSound(forOverlays overlays: [ObjectOverlay]) {
        let shouldPlay = !overlays.isEmpty

        DispatchQueue.main.async {
            // Configure AVAudioSession once
            if !self.didConfigureAudioSession {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, options: [.mixWithOthers])
                    try session.setActive(true)
                } catch {
                    print("⚠️ AudioSession setup error:", error)
                }
                self.didConfigureAudioSession = true
            }

            // Compute desired rate and beep file from distance_info
            let dist = Float(self.distance_info) ?? 0
            let desiredRate: Float
            let beepFileName: String
            
            switch dist {
            case ..<3.0:
                desiredRate = 2.0        // <3m: fastest
                beepFileName = "beep3"   // Highest pitch beep
            case 3.0..<7.0:
                desiredRate = 1.5        // 3–7m: medium-fast
                beepFileName = "beep2"   // Medium pitch beep
            case 7.0..<12.0:
                desiredRate = 1.0        // 7–12m: normal
                beepFileName = "beep"    // Normal pitch beep
            default:
                desiredRate = 0.5        // >12m: slow
                beepFileName = "beep"    // Normal pitch beep (slowest)
            }

            if shouldPlay {
                // Pause background sonar
                self.sonarPlayer?.pause()

                // If already playing, check if we need to change beep type or rate
                if let existingPlayer = self.player, existingPlayer.isPlaying {
                    // Stop and restart with new settings if rate changed significantly
                    if abs(existingPlayer.rate - desiredRate) > 0.01 {
                        existingPlayer.stop()
                        self.player = nil
                    }
                }
                
                // Create new beep player if not playing or settings changed
                if self.player?.isPlaying != true {
                    guard let url = Bundle.main.url(forResource: beepFileName, withExtension: "mp3") else {
                        print("⛔ \(beepFileName).mp3 not found")
                        return
                    }
                    do {
                        let p = try AVAudioPlayer(contentsOf: url)
                        p.delegate = self
                        p.enableRate = true
                        p.rate = desiredRate
                        p.numberOfLoops = -1
                        p.prepareToPlay()
                        p.play()
                        self.player = p
                    } catch {
                        print("🛑 Failed to start beep:", error)
                    }
                }
            } else {
                // No overlays: stop beep & resume sonar
                self.player?.stop()
                self.player = nil
                if !self.isOCREnabled {
                    self.sonarPlayer?.play()
                }
            }
        }
    }
    
    func didOutput(pixelBuffer: CVPixelBuffer) {
        
        self.latestPixelBuffer = pixelBuffer
        
        if isOCREnabled {
            player?.stop()
            //            performSearchOCR(on: pixelBuffer)
            if let query = searchBar.text, !query.isEmpty  {
                performSearchOCR(on: pixelBuffer)
            } else {
                performReadOCR(on: pixelBuffer)
            }
        } else {
            
            if (defaults.bool(forKey: "Upright") && tiltActivated) {
                
                speechSynthesizer.stopSpeaking(at: .immediate)
            } else {
                speechSynthesizer.stopSpeaking(at: .immediate)
                imageDetected = true
                
                // Fix the threading issue by checking UI state on main thread
                DispatchQueue.main.async {
                    if !self.currentLocationLabel.isHidden {
                        DispatchQueue.global(qos: .userInitiated).async {
                            self.runModel(onPixelBuffer: pixelBuffer)
                        }
                    }
                }
            }
        }
    }
    
    private var lastSpokenText: String?
    private let minimumSpeakInterval: TimeInterval = 3
    
    private func performReadOCR(on pixelBuffer: CVPixelBuffer) {
        player?.stop()
        let recognizeTextRequest = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async {
                    // No text detected, optionally clear any previous text or provide feedback
                    if self.speechSynthesizer.isSpeaking {
                        self.speechSynthesizer.stopSpeaking(at: .immediate)
                        
                    }
                }
                return
            }
            
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            
            // Speak the recognized text using the readAll method
            DispatchQueue.main.async {
                self.lastRecognizedText = recognizedText
                self.readAll(recognizedText)
            }
        }
        recognizeTextRequest.recognitionLevel = .accurate
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? requestHandler.perform([recognizeTextRequest])
    }
    
    
    // testing this performOCR for search. otherwise the above one is perfect.
    // -------------------------------
    // 1) Replace this method:
    // -------------------------------
    private func performSearchOCR(on pixelBuffer: CVPixelBuffer) {
        // Stop any previous speech queue
        DispatchQueue.main.async {
            self.speechQueue = []
        }

        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let strongSelf = self else { return }
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async {
                    print("Scanning (performSearchOCR)...")
                    self?.enqueueTextForSpeaking("scanning")
                    strongSelf.lastRecognizedText = "" // Clear last recognized text if no text is detected
                    // We no longer clear or draw any overlays here
                }
                return
            }

            // Combine all recognized strings into one text
            let recognizedText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")

            DispatchQueue.main.async {
                // Removed: strongSelf.highlightSearchedText(observations)
                strongSelf.handleRecognizedText(recognizedText)
            }
        }

        request.recognitionLevel = .accurate
        let requestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }

    
    private func highlightSearchedText(_ observations: [VNRecognizedTextObservation]) {
//        guard let searchedText = self.searchBar.text?.lowercased(), isOCREnabled else {
//            return
//        }
//        
//        // Clear existing overlays on main thread
//        DispatchQueue.main.async {
//            self.overlayView.layer.sublayers?.removeSubrange(0...)
//        }
//        
//        var drawnBoxes: [CGRect] = []
//        
//        for observation in observations {
//            for candidate in observation.topCandidates(1) {
//                // Split the candidate string into words and check against the search text
//                let words = candidate.string.lowercased().components(separatedBy: " ")
//                for word in words {
//                    if word == searchedText {
//                        let boundingBoxes = candidate.boundingBoxes(for: searchedText)
//                        for box in boundingBoxes {
//                            if !drawnBoxes.contains(box) {
//                                let transformedBox = transformBoundingBox(box)
//                                DispatchQueue.main.async {
//                                    self.drawBoundingBox(for: transformedBox)
//                                }
//                                drawnBoxes.append(box)
//                            }
//                        }
//                        break
//                    }
//                }
//            }
//        }
    }
    
    private func drawBoundingBox(for boundingBox: CGRect) {
        
        let increasedHeight: CGFloat = 20.0
        let increasedWidth: CGFloat = 20.0
        var adjustedBoundingBox = boundingBox
        adjustedBoundingBox.size.height += increasedHeight
        adjustedBoundingBox.size.width += increasedWidth
        
        adjustedBoundingBox.origin.y -= increasedHeight / 2
        adjustedBoundingBox.origin.x -= increasedWidth / 2
        
        let outline = CALayer()
        outline.frame = adjustedBoundingBox
        outline.borderWidth = 3.0
        outline.borderColor = UIColor.red.cgColor
        self.overlayView.layer.addSublayer(outline)
    }
    
    private func transformBoundingBox(_ boundingBox: CGRect) -> CGRect {
        let width = boundingBox.width * overlayView.bounds.size.width
        let height = boundingBox.height * overlayView.bounds.size.height
        let x = boundingBox.minX * overlayView.bounds.size.width
        let y = (1 - boundingBox.maxY) * overlayView.bounds.size.height - height
        
        // Adjustments to ensure the bounding box stays within the bounds of the overlayView
        var transformedBox = CGRect(x: x, y: y, width: width, height: height)
        
        // Adjust x and y coordinates if the bounding box is out of view bounds
        if transformedBox.origin.x < 0 {
            transformedBox.origin.x = self.edgeOffset
        }
        if transformedBox.origin.y < 0 {
            transformedBox.origin.y = self.edgeOffset
        }
        if transformedBox.maxY > self.overlayView.bounds.maxY {
            transformedBox.size.height = self.overlayView.bounds.maxY - transformedBox.origin.y - self.edgeOffset
        }
        if transformedBox.maxX > self.overlayView.bounds.maxX {
            transformedBox.size.width = self.overlayView.bounds.maxX - transformedBox.origin.x - self.edgeOffset
        }
        
        return transformedBox
    }
    
}
// MARK: CameraFeedManagerDelegate Methods
@available(iOS 13.0, *)
extension CameraViewController: CameraFeedManagerDelegate {
    
    // MARK: Session Handling Alerts
    func sessionRunTimeErrorOccurred() {
        // Handles session run time error by updating the UI and providing a button if session can be manually resumed.
        
    }
    func sessionWasInterrupted(canResumeManually resumeManually: Bool) {
        // Updates the UI when session is interrupted.self.cameraUnavailableLabel.isHidden = false
    }
    func sessionInterruptionEnded() {
        // Updates UI once session interruption has ended.
    }
    func presentVideoConfigurationErrorAlert() {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Configuration Failed", message: "Configuration of camera has failed.", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
            alertController.addAction(okAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    func presentCameraPermissionsDeniedAlert() {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Camera Permissions Denied", message: "Camera permissions have been denied for this app. You can change this by going to Settings", preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
            }
            alertController.addAction(cancelAction)
            alertController.addAction(settingsAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    /** This method runs the live camera pixelBuffer through tensorFlow to get the result.
     */
    @objc  func runModel(onPixelBuffer pixelBuffer: CVPixelBuffer) {
        
        guard !isOCREnabled else {
            print("OCR is enabled. Skipping model inference.")
            DispatchQueue.main.async {
                self.overlayView.objectOverlays.removeAll()
                self.overlayView.layer.sublayers?.removeAll()
                self.overlayView.setNeedsDisplay()
                self.result = nil
            }
            return
        }
        
        // Run the live camera pixelBuffer through tensorFlow to get the result
        let currentTimeMs = Date().timeIntervalSince1970 * 1000
        guard  (currentTimeMs - previousInferenceTimeMs) >= delayBetweenInferencesMs else {
            return
        }
        let horizontalAngle = defaultDevice().activeFormat.videoFieldOfView
        let deviceWidth = UIScreen.main.bounds.width * UIScreen.main.scale
        let deviceHeight = UIScreen.main.bounds.height * UIScreen.main.scale
        
      //  print(" horizontalAngle: \(horizontalAngle)°")
      //  print(" verticalAngle: \(verticalAngle)°")
        

        
        verticalAngle = (CGFloat((horizontalAngle)) / 4) * 3
        if (self.result?.inferences.count ?? 0 > 0) {
            if let detectionFrame = self.result?.inferences[0].rect {
                let bwidth: CGFloat = (detectionFrame.width) / UIScreen.main.bounds.width// * 480
                let dict = defaults.value(forKey: "tfliteDict") as? [String: String]
                let selectedModel = defaults.string(forKey: "selectedModel") ?? ""
                let modelName: String = dict?[selectedModel] ?? ""
                
                let viewWidth = UIScreen.main.bounds.width // added to get screen width
                
                ///ACTUAL WIDTH AND DISTANCE MEASURE
                print("Last 3")
                let last3 = String(modelName.suffix(3))
                print("last 3 digits: \(last3)")
                guard let n = NumberFormatter().number(from: last3) else { return }
//                guard let n = NumberFormatter().number(from: "310") else { return }
                let number = CGFloat(CGFloat(Int(truncating: n)) / 1000)
                print(number)
                distance_info = getDistance(from: number, bbWidth: bwidth, viewWidth: viewWidth ,angle: verticalAngle)
                print("bbWidth (normalized): \(bwidth)")
                print("viewWidth (pts): \(viewWidth)")
                print("🎯 distance_info (string): \(distance_info)m")
                
                let formatter = NumberFormatter()
                formatter.numberStyle = NumberFormatter.Style.decimal
                formatter.roundingMode = NumberFormatter.RoundingMode.ceiling
                formatter.maximumFractionDigits = 1
                
                labelMessage = "\(String(describing: maxValue).prefix(4)) : Max, \(String(describing: minValue).prefix(4)) : Min, \(String(modelName.prefix(3))), \(locValues)"
                print("Label Message: ---------xxx START xxx----------")
                print("LocValues: \(locValues)")
                print(labelMessage)
                print("Label Message: ---------xxx END xxx----------")
            }
        }
        previousInferenceTimeMs = currentTimeMs
        result = self.modelDataHandler?.runModel(onFrame: pixelBuffer)
        guard let displayResult = result else {
            return
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        DispatchQueue.main.async {
            if (self.isOCREnabled) { return }
           // print("Model inference produced results.")
            // Draws the bounding boxes and displays class names and confidence scores.
            self.drawAfterPerformingCalculations(onInferences: displayResult.inferences, withImageSize: CGSize(width: CGFloat(width), height: CGFloat(height)))
        }
    }
    /**
     This method takes the results, translates the bounding box rects to the current view, draws the bounding boxes, classNames and confidence scores of inferences.
     */
    // 1) Full replacement for your inference→draw pipeline:
    func drawAfterPerformingCalculations(onInferences inferences: [Inference], withImageSize imageSize: CGSize) {
        // Clear out any old overlays
        self.overlayView.objectOverlays = []
        self.overlayView.setNeedsDisplay()

        guard !inferences.isEmpty else {
           // print("No inferences to display.")
            // No overlays means no beep
            DispatchQueue.main.async {
                self.playBeepSound(forOverlays: [])
            }
            return
        }

        var objectOverlays: [ObjectOverlay] = []
        for inference in inferences {
            // scale the rect from model coords → view coords
            var convertedRect = inference.rect.applying(
                CGAffineTransform(
                    scaleX: overlayView.bounds.width / imageSize.width,
                    y: overlayView.bounds.height / imageSize.height
                )
            )

            // clamp to view bounds
            convertedRect.origin.x = max(edgeOffset, convertedRect.origin.x)
            convertedRect.origin.y = max(edgeOffset, convertedRect.origin.y)
            if convertedRect.maxX > overlayView.bounds.maxX {
                convertedRect.size.width = overlayView.bounds.maxX - convertedRect.origin.x - edgeOffset
            }
            if convertedRect.maxY > overlayView.bounds.maxY {
                convertedRect.size.height = overlayView.bounds.maxY - convertedRect.origin.y - edgeOffset
            }

            let confidencePct = Int(inference.confidence * 100.0)
            let labelText = "\(confidencePct)% \(distance_info)m"
            let labelSize = labelText.size(usingFont: displayFont)

            let overlay = ObjectOverlay(
                name: labelText,
                borderRect: convertedRect,
                nameStringSize: labelSize,
                color: UIColor.purple,
                font: displayFont
            )
            objectOverlays.append(overlay)
        }

        // Draw and beep on the main thread
        DispatchQueue.main.async {
            self.draw(objectOverlays: objectOverlays)
            self.playBeepSound(forOverlays: objectOverlays)
        }
    }

    // 2) Full replacement for your simple draw(...) method:
    func draw(objectOverlays: [ObjectOverlay]) {
        self.overlayView.objectOverlays = objectOverlays
        self.overlayView.setNeedsDisplay()
        // Ensure beep state matches overlay presence
        self.playBeepSound(forOverlays: objectOverlays)
    }

}

extension CLLocation {
    func placemark(completion: @escaping (_ placemark: CLPlacemark?, _ error: Error?) -> ()) {
        CLGeocoder().reverseGeocodeLocation(self) { completion($0?.first, $1) }
    }
}

extension CLPlacemark {
    /// street name, eg. Infinite Loop
    var streetName: String? { thoroughfare }
    /// // eg. 1
    var streetNumber: String? { subThoroughfare }
    /// city, eg. Cupertino
    var city: String? { locality }
    /// neighborhood, common name, eg. Mission District
    var neighborhood: String? { subLocality }
    /// state, eg. CA
    var state: String? { administrativeArea }
    /// county, eg. Santa Clara
    var county: String? { subAdministrativeArea }
    /// zip code, eg. 95014
    var zipCode: String? { postalCode }
    /// postal address formatted
    @available(iOS 11.0, *)
    var postalAddressFormatted: String? {
        guard let postalAddress = postalAddress else { return nil }
        return CNPostalAddressFormatter().string(from: postalAddress)
    }
}

@available(iOS 13.0, *)
extension CameraViewController: UISearchBarDelegate, AVSpeechSynthesizerDelegate {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        //        speechSynthesizer.stopSpeaking(at: .immediate)
        speechQueue = []
        if searchText.isEmpty {
            // No text in search bar, switch to reading mode
            isOCREnabled = true
            isCurrentlySearching = false
            print("Scanning (textDidChange)...")
            speechSynthesizer.stopSpeaking(at: .immediate)
        } else {
            // Text present, switch to search mode
            isOCREnabled = false
            isCurrentlySearching = true
        }
    }
    
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        speechSynthesizer.stopSpeaking(at: .immediate)
        print("stopped")
        speechQueue = []
        isOCREnabled = false
        return true
    }
    
    @objc func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        print("SEARCH CLICKEDDDDD")
        DispatchQueue.main.async {
            self.overlayView.layer.sublayers?.removeAll()
        }
        
        print("Dismissing keyboard.")
        searchBar.resignFirstResponder()
        
        //        speechSynthesizer.stopSpeaking(at: .immediate)
        speechQueue = []
        //        guard let searchText = searchBar.text, !searchText.isEmpty else {
        //            return
        //        }
        let searchText = searchBar.text ?? ""
        
        if (searchBar.text != "") {
            DispatchQueue.main.async {
                let lookingMessage = "Looking for \(searchText)."
                self.enqueueTextForSpeaking(lookingMessage)
            }
        }
        // Ensure OCR is active and ready to handle search
        if !isOCREnabled {
            isOCREnabled = true // A method to enable OCR if it's not already active
        }
        
        if let lastText = lastRecognizedText {
            searchForQuery(lastText, query: searchText)
        }
    }
    
    func startListening() {
        stopAudioLoop()
        isOCREnabled = false
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }
        
        // Show microphone icon and Done button when listening starts
        micImageView.isHidden = false
        
        // If there's an ongoing task, cancel it
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // Configure the audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Audio session properties weren't set because of an error.")
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create a recognition request.")
        }
        
        let inputNode = audioEngine.inputNode
        
        // Configure the request to handle partial results
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false  // Fallback to remote recognition if local is unavailable
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                // Update the search bar text with the speech transcription
                let transcription = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.searchBar.text = transcription
                }
            }
            
            if error != nil || result?.isFinal == true {
                // Stop listening when error occurs or final result is produced
                self.stopListening()
            }
        }
        
        // Start the audio engine
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine couldn't start because of an error.")
        }
    }
    
    @objc func stopListening() {
        print("Done Pressed...")
        audioEngine.stop()
        audioEngine.reset()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Hide the microphone icon and Done button when listening stops
        micImageView.isHidden = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // Adjust delay as needed
            let currentSearchTerm = self.searchBar.text
            
            if currentSearchTerm == "" {
                print("oops! kindly try again.")
            }
            
            if self.searchBar.text != "" {
                self.searchBarSearchButtonClicked(self.searchBar)
            }
        }
    }
    
    
    private func speakTextSearch(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(utterance)
    }
    
    // Utility to start looping audio
    func startLoopingAudio(withMessage message: String) {
        stopAudioLoop()  // Ensure to stop any previous looping audio
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.1  // Short delay between loops
        
        // Set a timer to keep speaking until found
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.speechSynthesizer.speak(utterance)
        }
    }
    
    // Utility to stop audio
    func stopAudio() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    func stopAudioLoop() {
        searchTimer?.invalidate()
        searchTimer = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeakingLock = false
        manageSpeechQueue()  // Trigger the next speech
    }
    
   
    func manageSpeechQueue() {
        speechQueueSyncQueue.async { [weak self] in
            guard let self = self else { return }

            // Ensure the synthesizer is not speaking and the queue is non-empty
            guard !self.speechSynthesizer.isSpeaking else { return }

            // Perform all array operations in the synchronized queue
            if !self.speechQueue.isEmpty {
                // Safely access and remove the first element
                let nextSpeech = self.speechQueue.removeFirst()

                // Speak the text in the background queue
                DispatchQueue.global(qos: .background).async {
                    self.speakText(nextSpeech)
                }
            }
        }
    }

    
    
    
    func enqueueTextForSpeaking(_ text: String) {
        speechQueueSyncQueue.async { [weak self] in
            self?.speechQueue.append(text)
            self?.manageSpeechQueue()
        }
    }
}


@available(iOS 13.0, *)
extension CameraViewController: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        
        do {
            let documentsURL = try
            FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
            let savedURL = documentsURL.appendingPathComponent(
                location.lastPathComponent)
            print("Saved URL")
            print(savedURL)
            try FileManager.default.moveItem(at: location, to: savedURL)
            
        } catch {
            // handle filesystem error
            print ("file error: \(error)")
        }
    }
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if downloadTask == self.downloadTask {
            let calculatedProgress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
            print(calculatedProgress)
        }
    }
}

@available(iOS 13.0, *)
extension CameraViewController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if !isOCREnabled {
            sonarPlayer?.play()
        }
    }
}

@available(iOS 13.0, *)
extension VNRecognizedText {
    func boundingBoxes(for substring: String) -> [CGRect] {
        var results = [CGRect]()
        let range = NSRange(self.string.startIndex..<self.string.endIndex, in: self.string)
        
        do {
            let regex = try NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: substring), options: .caseInsensitive)
            regex.enumerateMatches(in: self.string, options: [], range: range) { match, flags, stop in
                if let matchRange = match?.range {
                    if let stringRange = Range(matchRange, in: self.string) {
                        if let rectangleObservation = try? self.boundingBox(for: stringRange) {
                            results.append(rectangleObservation.boundingBox)
                        }
                    }
                }
            }
        } catch {
            print("Error finding bounding boxes: \(error)")
        }
        
        return results
    }
}
