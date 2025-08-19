// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CoreImage
import TensorFlowLite
import UIKit
import Accelerate

/// Stores results for a particular frame that was successfully run through the `Interpreter`.
struct Result {
  let inferenceTime: Double
  let inferences: [Inference]
}

/// Stores one formatted inference.
struct Inference {
  let confidence: Float
  let className: String
  let rect: CGRect
  let displayColor: UIColor
}

/// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

/// Information about the MobileNet SSD model.
enum MobileNetSSD {
  static let modelInfo: FileInfo = (name: UserDefaults.standard.string(forKey: "selectedModel") ?? "MBTA Boston", extension: "tflite")
  static let labelsInfo: FileInfo = (name: UserDefaults.standard.string(forKey: "selectedLabel") ?? "MBTA Boston_lb.txt", extension: "txt")
}

/// This class handles all data preprocessing and makes calls to run inference on a given frame
/// by invoking the `Interpreter`. It then formats the inferences obtained and returns the top N
/// results for a successful inference.
///

class ModelDataHandler: NSObject {

  // MARK: - Internal Properties
  /// The current thread count used by the TensorFlow Lite Interpreter.
  let threadCount: Int
  let threadCountLimit = 10

  let threshold: Float = UserDefaults.standard.value(forKey: "Certainty") == nil ? 0.7 : Float(truncating: UserDefaults.standard.value(forKey: "Certainty") as! NSNumber)

  // MARK: Model parameters
  let batchSize = 1
  let inputChannels = 3
  let inputWidth = 300
  let inputHeight = 300

  // image mean and std for floating model, should be consistent with parameters used in model training
    let imageMean: Float = 128.0
    let imageStd:  Float = 128.0

  // MARK: Private properties
    var labels: [String] = []

  /// TensorFlow Lite `Interpreter` object for performing inference on a given model.
  private var interpreter: Interpreter
  
  /// Serial queue to prevent concurrent access to the interpreter
  private let interpreterQueue = DispatchQueue(label: "org.allaboard.interpreter", qos: .userInteractive)
  
  /// Flag to track if interpreter is currently being used
  private var isInferenceInProgress = false
  private let inferenceProgressLock = NSLock()

  private let bgraPixel = (channels: 4, alphaComponent: 3, lastBgrComponent: 2)
  private let rgbPixelChannels = 3
  private let colorStrideValue = 10
  private let colors = [
    UIColor.red,
    UIColor(displayP3Red: 90.0/255.0, green: 200.0/255.0, blue: 250.0/255.0, alpha: 1.0),
    UIColor.green,
    UIColor.orange,
    UIColor.blue,
    UIColor.purple,
    UIColor.magenta,
    UIColor.yellow,
    UIColor.cyan,
    UIColor.brown
  ]

  // MARK: - Initialization

  /// A failable initializer for `ModelDataHandler`. A new instance is created if the model and
  /// labels files are successfully loaded from the app's main bundle. Default `threadCount` is 1.
    init?(modelFileInfo: FileInfo, labelsFileInfo: FileInfo, threadCount: Int = 4) {
        let modelFilename = modelFileInfo.name
        
        // Specify the options for the `Interpreter`.
        self.threadCount = threadCount
        var options = Interpreter.Options()
        options.threadCount = threadCount
        do {
            let dict = UserDefaults.standard.value(forKey: "modelPath") as? [String: String]
            let downloadedModelPath = dict?[UserDefaults.standard.string(forKey: "selectedModel") ?? ""]
            
            print("🔍 Model path from UserDefaults: \(downloadedModelPath ?? "nil")")
            
            // Create the `Interpreter`.
            interpreter = try Interpreter(modelPath: downloadedModelPath ?? "", options: options)
            // Allocate memory for the model's input `Tensor`s.
            try interpreter.allocateTensors()
           
            
        } catch let error {
            print("❌ Failed to load model: \(error.localizedDescription)")
            return nil
        }
        
        super.init()
        
        // Load the classes listed in the labels file.
        loadLabels(fileInfo: labelsFileInfo)
    }

      /// Runs one frame through the interpreter with thread safety.
      /// Returns a Result (inference time + inferences) on success, or `nil` if anything failed.
      func runModel(onFrame pixelBuffer: CVPixelBuffer) -> Result? {
        // Check if inference is already in progress
        inferenceProgressLock.lock()
        if isInferenceInProgress {
            inferenceProgressLock.unlock()
            print("⚠️ [runModel] Inference already in progress, skipping frame")
            return nil
        }
        isInferenceInProgress = true
        inferenceProgressLock.unlock()
        
        defer {
            inferenceProgressLock.lock()
            isInferenceInProgress = false
            inferenceProgressLock.unlock()
        }
        
        // Run inference on serial queue to prevent concurrent access
        return interpreterQueue.sync { [weak self] in
            guard let self = self else { return nil }
            return self.performInference(on: pixelBuffer)
        }
      }
      
      /// Performs the actual inference work - called from within the serial queue
      private func performInference(on pixelBuffer: CVPixelBuffer) -> Result? {
        // 1) Resize the incoming CVPixelBuffer to the model's input size.
        let imageWidth  = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        guard pixelFormat == kCVPixelFormatType_32ARGB ||
              pixelFormat == kCVPixelFormatType_32BGRA ||
              pixelFormat == kCVPixelFormatType_32RGBA else {
            print("❌ [runModel] Unsupported pixel format: \(pixelFormat)")
            return nil
        }

        let targetSize = CGSize(width: inputWidth, height: inputHeight)
        guard let scaledBuffer = pixelBuffer.resized(to: targetSize) else {
          print("❌ [runModel] Failed to resize CVPixelBuffer to \(inputWidth)x\(inputHeight).")
          return nil
        }

        // 2) Get input tensor info first before allocating
        let inputTensor: Tensor
        do {
          inputTensor = try interpreter.input(at: 0)
        } catch {
          print("❌ [runModel] Unable to read input tensor metadata: \(error)")
          return nil
        }

        // 3) Only allocate if needed (check if tensors are already allocated)
        do {
          if inputTensor.data.count == 0 {
            try interpreter.allocateTensors()
            print("🔧 [runModel] Allocated tensors")
          }
        } catch {
          print("❌ [runModel] allocateTensors() failed: \(error)")
          return nil
        }

        // 4) Re-fetch input tensor after potential allocation
        let finalInputTensor: Tensor
        do {
          finalInputTensor = try interpreter.input(at: 0)
        } catch {
          print("❌ [runModel] Unable to read input tensor after allocation: \(error)")
          return nil
        }

        // 5) Determine if this model is quantized (UInt8) or float (Float32).
        let expectsQuantizedInput = (finalInputTensor.dataType == .uInt8)

        // 6) Ask TFLite exactly how many bytes its input tensor expects.
        let requiredByteCount = finalInputTensor.data.count
        guard requiredByteCount > 0 else {
          print("❌ [runModel] Input tensor has 0 bytes - allocation may have failed")
          return nil
        }

        // 7) Build exactly that many bytes of RGB (or normalized floats).
        guard let rgbData = rgbDataFromBuffer(
                scaledBuffer,
                byteCount: requiredByteCount,
                isModelQuantized: expectsQuantizedInput
              )
        else {
          print("❌ [runModel] rgbDataFromBuffer returned nil. Required byteCount = \(requiredByteCount), quantized=\(expectsQuantizedInput).")
          return nil
        }

        // 8) Copy our unified Data buffer into the interpreter's input tensor.
        do {
          _ = try interpreter.copy(rgbData, toInputAt: 0)
        } catch {
          print("❌ [runModel] Failed to copy data into input tensor: \(error)")
          return nil
        }

        // 9) Invoke the interpreter and measure inference time (in milliseconds).
        let inferenceTimeMs: Double
        do {
          let start = Date()
          try interpreter.invoke()
          inferenceTimeMs = Date().timeIntervalSince(start) * 1000
        } catch {
          print("❌ [runModel] interpreter.invoke() failed: \(error)")
          return nil
        }

        // 10) Fetch each of the four output tensors by index with error handling
        guard let outputTensors = safelyGetOutputTensors() else {
          print("❌ [runModel] Failed to fetch output tensors safely")
          return nil
        }

        // 11) Convert Data → [Float] with bounds checking
        let boxesArray   = Array<Float>(unsafeData: outputTensors.boxes.data)   ?? []
        let classesArray = Array<Float>(unsafeData: outputTensors.classes.data) ?? []
        let scoresArray  = Array<Float>(unsafeData: outputTensors.scores.data)  ?? []
        let countArray   = Array<Float>(unsafeData: outputTensors.count.data)   ?? [0]
        
        guard !boxesArray.isEmpty, !classesArray.isEmpty, !scoresArray.isEmpty else {
          print("❌ [runModel] One or more output arrays is empty")
          return nil
        }
        
        let detectionCount = min(Int(countArray.first ?? 0), scoresArray.count)
        guard detectionCount >= 0 else {
          print("❌ [runModel] Invalid detection count: \(detectionCount)")
          return nil
        }

        // 12) Format those raw arrays into [Inference] + CGRects in the original image space.
        let resultArray = formatResults(
          boundingBox:   boxesArray,
          outputClasses: classesArray,
          outputScores:  scoresArray,
          outputCount:   detectionCount,
          width:  CGFloat(imageWidth),
          height: CGFloat(imageHeight)
        )

        return Result(inferenceTime: inferenceTimeMs, inferences: resultArray)
      }
      
      /// Safely retrieves output tensors with proper error handling
      private func safelyGetOutputTensors() -> (boxes: Tensor, classes: Tensor, scores: Tensor, count: Tensor)? {
        do {
          let outputBoxes   = try interpreter.output(at: 0)
          let outputClasses = try interpreter.output(at: 1)
          let outputScores  = try interpreter.output(at: 2)
          let outputCount   = try interpreter.output(at: 3)
          
          // Verify tensors have data
          guard outputBoxes.data.count > 0,
                outputClasses.data.count > 0,
                outputScores.data.count > 0,
                outputCount.data.count > 0 else {
            print("❌ One or more output tensors is empty")
            return nil
          }
          
          return (boxes: outputBoxes, classes: outputClasses, scores: outputScores, count: outputCount)
        } catch {
          print("❌ Failed to fetch output tensors: \(error)")
          return nil
        }
      }

  /// Filters out all the results with confidence score < threshold and returns the top N results
  /// sorted in descending order.
    func formatResults(
      boundingBox: [Float],
      outputClasses: [Float],
      outputScores: [Float],
      outputCount: Int,
      width: CGFloat,
      height: CGFloat
    ) -> [Inference] {
      var resultsArray: [Inference] = []
      
      // Safety checks
      guard outputCount > 0,
            !outputScores.isEmpty,
            !outputClasses.isEmpty,
            !boundingBox.isEmpty,
            !labels.isEmpty else {
        return resultsArray
      }
      
      // Ensure we don't go beyond array bounds
      let safeCount = min(outputCount, outputScores.count, outputClasses.count, boundingBox.count / 4)

      for i in 0..<safeCount {
        // Bounds check for all arrays
        guard i < outputScores.count,
              i < outputClasses.count,
              (4 * i + 3) < boundingBox.count else {
          print("⚠️ Skipping index \(i) due to bounds check")
          continue
        }
        
        let score = outputScores[i]

        // Filter out low‐confidence boxes
        guard score >= threshold && score <= 1.0 else { continue }

        // *** NO +1 HERE *** — use the class index directly
        let outputClassIndex = Int(outputClasses[i])
        guard outputClassIndex >= 0 && outputClassIndex < labels.count else {
          print("❌ Class index \(outputClassIndex) out of bounds (labels.count=\(labels.count))")
          continue
        }
        let outputClass = labels[outputClassIndex]

        // Build CGRect from the raw [ymin, xmin, ymax, xmax] floats with bounds checking
        guard (4*i + 3) < boundingBox.count else {
          print("❌ Bounding box index out of bounds for detection \(i)")
          continue
        }
        
        var rect = CGRect.zero
        rect.origin.y = CGFloat(boundingBox[4*i])
        rect.origin.x = CGFloat(boundingBox[4*i + 1])
        rect.size.height = CGFloat(boundingBox[4*i + 2]) - rect.origin.y
        rect.size.width = CGFloat(boundingBox[4*i + 3]) - rect.origin.x
        
        // Validate rect values
        guard rect.origin.y.isFinite && rect.origin.x.isFinite &&
              rect.size.height.isFinite && rect.size.width.isFinite &&
              rect.size.height > 0 && rect.size.width > 0 else {
          print("⚠️ Invalid rect values for detection \(i)")
          continue
        }

        // Scale to actual image size
        let newRect = rect.applying(CGAffineTransform(scaleX: width, y: height))

        // Pick a color (also no +1 here)
        let colorToAssign = colorForClass(withIndex: outputClassIndex)
        let inference = Inference(
          confidence: score,
          className: outputClass,
          rect: newRect,
          displayColor: colorToAssign
        )
        resultsArray.append(inference)
      }

      // Sort descending by confidence
      resultsArray.sort { $0.confidence > $1.confidence }
      return resultsArray
    }

    private func loadLabels(fileInfo: FileInfo) {
        print("🔍 Loading labels with fileInfo: \(fileInfo)")

        // 1) Figure out which key we're supposed to look up in UserDefaults.
        guard let selectedLabelKey = UserDefaults.standard.string(forKey: "selectedLabel") else {
            print("❌ No selectedLabel found in UserDefaults")
            return
        }
        print("🔍 Using labelKey = '\(selectedLabelKey)'")

        // 2) Grab the dictionary we stored earlier that maps labelKey → full file path.
        guard let installedPaths = UserDefaults.standard.value(forKey: "installedPath") as? [String: String] else {
            print("❌ No installedPath found in UserDefaults")
            return
        }
        print("🔍 installedPaths keys: \(installedPaths.keys)")

        // 3) See if there's a value for our selectedLabelKey in that dictionary.
        guard let labelsFilePath = installedPaths[selectedLabelKey] else {
            print("❌ No path found for selectedLabel key: '\(selectedLabelKey)'")
            print("   Available keys: \(installedPaths.keys)")
            return
        }
        print("🔍 Found labels file at path: '\(labelsFilePath)'")

        // 4) Make sure the file is really on disk.
        guard FileManager.default.fileExists(atPath: labelsFilePath) else {
            print("❌ Labels file does not exist at path: '\(labelsFilePath)'")
            return
        }

        // 5) Read all of its bytes.
        let rawData: Data
        do {
            rawData = try Data(contentsOf: URL(fileURLWithPath: labelsFilePath))
        } catch {
            print("❌ Failed to read labels file data: \(error.localizedDescription)")
            return
        }

        // 6) Quick HTML‐sniff: if it starts with "<" then delete it and abort.
        if let firstLine = String(data: rawData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           firstLine.hasPrefix("<") {
            print("❌ Labels file contains HTML, expected plain text. Deleting and aborting.")
            do {
                try FileManager.default.removeItem(atPath: labelsFilePath)
                print("🗑 Deleted bad labels file at: \(labelsFilePath)")
            } catch {
                print("❌ Could not delete bad labels file: \(error)")
            }
            return
        }

        // 7) Try decoding as UTF-8 first:
        let contents: String
        if let utf8 = String(data: rawData, encoding: .utf8) {
            contents = utf8
        } else if let utf16 = String(data: rawData, encoding: .utf16) {
            print("🔍 UTF-8 decode failed; fell back to UTF-16.")
            contents = utf16
        } else {
            print("❌ Labels file could not be decoded as UTF-8 or UTF-16.")
            return
        }

        // 8) Split into non-empty lines
        let lines = contents
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            print("❌ Labels file is empty (or all lines blank).")
            return
        }

        // 9) Store them exactly as-is (no +1 shift)
        labels = lines
        print("✅ Successfully loaded \(labels.count) labels:")
        for (i, label) in labels.prefix(10).enumerated() {
            print("   [\(i)] \(label)")
        }
    }

  /// Returns the RGB data representation of the given image buffer with the specified `byteCount`.
  ///
  /// - Parameters
  ///   - buffer: The BGRA pixel buffer to convert to RGB data.
  ///   - byteCount: The expected byte count for the RGB data calculated using the values that the
  ///       model was trained on: `batchSize * imageWidth * imageHeight * componentsCount`.
  ///   - isModelQuantized: Whether the model is quantized (i.e. fixed point values rather than
  ///       floating point values).
  /// - Returns: The RGB data representation of the image buffer or `nil` if the buffer could not be
  ///     converted.
  private func rgbDataFromBuffer(
    _ buffer: CVPixelBuffer,
    byteCount: Int,
    isModelQuantized: Bool
  ) -> Data? {
    
    guard byteCount > 0 else {
      print("❌ Invalid byteCount: \(byteCount)")
      return nil
    }
    
    let lockResult = CVPixelBufferLockBaseAddress(buffer, .readOnly)
    guard lockResult == kCVReturnSuccess else {
      print("❌ Failed to lock pixel buffer")
      return nil
    }
    
    defer {
      CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    }
    
    guard let sourceData = CVPixelBufferGetBaseAddress(buffer) else {
      print("❌ Failed to get pixel buffer base address")
      return nil
    }
    
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let destinationChannelCount = 3
    let destinationBytesPerRow = destinationChannelCount * width
    
    var sourceBuffer = vImage_Buffer(data: sourceData,
                                     height: vImagePixelCount(height),
                                     width: vImagePixelCount(width),
                                     rowBytes: sourceBytesPerRow)
    
    guard let destinationData = malloc(height * destinationBytesPerRow) else {
      print("❌ Failed to allocate memory for destination buffer")
      return nil
    }
    
    defer {
      free(destinationData)
    }

    var destinationBuffer = vImage_Buffer(data: destinationData,
                                          height: vImagePixelCount(height),
                                          width: vImagePixelCount(width),
                                          rowBytes: destinationBytesPerRow)
    
    let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
    var conversionResult: vImage_Error = kvImageNoError
    
    switch pixelFormat {
    case kCVPixelFormatType_32BGRA:
      conversionResult = vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    case kCVPixelFormatType_32ARGB:
      conversionResult = vImageConvert_ARGB8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    case kCVPixelFormatType_32RGBA:
      conversionResult = vImageConvert_RGBA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    default:
      print("❌ Unsupported pixel format: \(pixelFormat)")
      return nil
    }
    
    guard conversionResult == kvImageNoError else {
      print("❌ vImage conversion failed with error: \(conversionResult)")
      return nil
    }

    let actualByteCount = destinationBuffer.rowBytes * height
    let byteData = Data(bytes: destinationBuffer.data, count: actualByteCount)
    
    if isModelQuantized {
      // For quantized models, return raw bytes but ensure correct size
      if byteData.count != byteCount {
        print("⚠️ Byte count mismatch: got \(byteData.count), expected \(byteCount)")
        // Resize if necessary
        if byteData.count > byteCount {
          return byteData.prefix(byteCount)
        }
      }
      return byteData
    }

    // Not quantized, convert to floats
    guard let bytes = Array<UInt8>(unsafeData: byteData) else {
      print("❌ Failed to convert Data to UInt8 array")
      return nil
    }
    
    var floats = [Float]()
    floats.reserveCapacity(bytes.count)
    
    for byte in bytes {
      let normalizedValue = (Float(byte) - imageMean) / imageStd
      guard normalizedValue.isFinite else {
        print("❌ Non-finite value during normalization: \(normalizedValue)")
        return nil
      }
      floats.append(normalizedValue)
    }
    
    let floatData = Data(copyingBufferOf: floats)
    
    // Verify the final size matches what TensorFlow expects
    if floatData.count != byteCount {
      print("⚠️ Float data size mismatch: got \(floatData.count), expected \(byteCount)")
    }
    
    return floatData
  }

  /// This assigns color for a particular class.
  private func colorForClass(withIndex index: Int) -> UIColor {

    // We have a set of colors and the depending upon a stride, it assigns variations to of the base
    // colors to each object based on its index.
    let baseColor = colors[index % colors.count]

    var colorToAssign = baseColor

    let percentage = CGFloat((colorStrideValue / 2 - index / colors.count) * colorStrideValue)

    if let modifiedColor = baseColor.getModified(byPercentage: percentage) {
      colorToAssign = modifiedColor
    }

    return colorToAssign
  }
}

// MARK: - Extensions

extension Data {
  /// Creates a new buffer by copying the buffer pointer of the given array.
  ///
  /// - Warning: The given array's element type `T` must be trivial in that it can be copied bit
  ///     for bit with no indirection or reference-counting operations; otherwise, reinterpreting
  ///     data from the resulting buffer has undefined behavior.
  /// - Parameter array: An array with elements of type `T`.
  init<T>(copyingBufferOf array: [T]) {
    self = array.withUnsafeBufferPointer(Data.init)
  }
}

extension Array {
  /// Creates a new array from the bytes of the given unsafe data.
  ///
  /// - Warning: The array's `Element` type must be trivial in that it can be copied bit for bit
  ///     with no indirection or reference-counting operations; otherwise, copying the raw bytes in
  ///     the `unsafeData`'s buffer to a new array returns an unsafe copy.
  /// - Note: Returns `nil` if `unsafeData.count` is not a multiple of
  ///     `MemoryLayout<Element>.stride`.
  /// - Parameter unsafeData: The data containing the bytes to turn into an array.
  init?(unsafeData: Data) {
    guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
    #if swift(>=5.0)
    self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
    #else
    self = unsafeData.withUnsafeBytes {
      .init(UnsafeBufferPointer<Element>(
        start: $0,
        count: unsafeData.count / MemoryLayout<Element>.stride
      ))
    }
    #endif  // swift(>=5.0)
  }
}
