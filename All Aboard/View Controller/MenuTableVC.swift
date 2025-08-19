//
//  MenuTableVC.swift
//  All Aboard
//
//  Created by Wiper on 23/07/21.
//  Updated by Meet on 06/02/2025.

import UIKit

@available(iOS 13.0, *)
class MenuTableVC: UITableViewController, URLSessionDownloadDelegate {

    // Base URLs for model & label downloads
    let modelsBaseURL = "https://vrt.partners.org/AllAboard_Android_Modelfiles/Models/"
    let labelsBaseURL = "https://vrt.partners.org/AllAboard_Android_Modelfiles/Labelmaps/"

    var tfliteArrayJSON = [String]()
    var tfliteArray = [String]()
    let defaults = UserDefaults.standard
    var installedArr = [String]()
    var installedPathArr = [String: String]()
    var tfliteDict = [String : String]()

    // We’ll use this session for download‐delegate callbacks if needed
    private lazy var urlSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    // Loading indicator UI
    var loadingIndicator: UIActivityIndicatorView = {
        let a = UIActivityIndicatorView()
        a.translatesAutoresizingMaskIntoConstraints = false
        a.hidesWhenStopped = true
        a.tintColor = .black
        a.style = .gray
        return a
    }()
    let loadingView = UIView()
    let loadingLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchAvailableModels()
        self.tableView.register(MenuTableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.backgroundColor = .white
    }

    // MARK: – Loading Screen Helpers

    private func setLoadingScreen() {
        let width: CGFloat = 120
        let height: CGFloat = 30
        let x = (tableView.frame.width / 2) - (width / 2)
        let y = (tableView.frame.height / 2) - (height / 2)
        loadingView.frame = CGRect(x: x, y: y, width: width, height: height)

        loadingLabel.textColor = .systemBlue
        loadingLabel.textAlignment = .center
        loadingLabel.text = "Loading..."
        loadingLabel.frame = CGRect(x: 0, y: 0, width: 140, height: 30)

        loadingIndicator.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        loadingIndicator.startAnimating()

        loadingView.addSubview(loadingIndicator)
        loadingView.addSubview(loadingLabel)

        tableView.addSubview(loadingView)
    }

    private func removeLoadingScreen() {
        loadingIndicator.stopAnimating()
        loadingIndicator.isHidden = true
        loadingLabel.isHidden = true
    }

    // MARK: – Fetch & Parse Model List

    func fetchAvailableModels() {
        let modelsListURL = modelsBaseURL
        guard let url = URL(string: modelsListURL) else {
            useFallbackModelList()
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("Error fetching models list: \(error)")
                self.useFallbackModelList()
                return
            }
            guard let data = data,
                  let htmlString = String(data: data, encoding: .utf8) else {
                print("Failed to parse models list response")
                self.useFallbackModelList()
                return
            }

            let modelNames = self.parseModelNamesFromHTML(htmlString)

            if modelNames.isEmpty {
                print("No models found in response, using fallback")
                self.useFallbackModelList()
            } else {
                DispatchQueue.main.async {
                    self.setupModelsWithNames(modelNames)
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
            print("Regex error: \(error)")
        }

        print("🔍 AFTER URL DECODING: \(modelNames)")
        return modelNames
    }

    private func useFallbackModelList() {
        let fallbackNames = [
            "California AC Transit_500",
            "Chicago CTA_350",
            "Germany bus and tram_420",
            "London bus services_330",
            "Los Angeles Metro_615",
            "MBTA Boston_330",
            "New York MTA_450",
            "Seattle Metro_350",
            "Toronto TTC_165",
            "Washington DC Metrobus_500"
        ]
        DispatchQueue.main.async {
            self.setupModelsWithNames(fallbackNames)
        }
    }

    private func setupModelsWithNames(_ modelNames: [String]) {
        print("🔍 DEBUG: Raw model names from server:")
        for (index, name) in modelNames.enumerated() {
            print("  [\(index)] '\(name)'")
        }

        tfliteArrayJSON.removeAll()
        tfliteArray.removeAll()
        tfliteDict.removeAll()

        for modelName in modelNames {
            tfliteArrayJSON.append(modelName)

            var displayName = modelName.replacingOccurrences(
                of: "_\\d+$",
                with: "",
                options: .regularExpression
            )
            displayName = displayName.replacingOccurrences(of: "_", with: " ")
            tfliteArray.append(displayName)
            tfliteDict[displayName] = modelName

            print("🔧 Model: '\(modelName)' → Display: '\(displayName)'")
        }

        print("🎯 Final tfliteDict:")
        for (key, value) in tfliteDict {
            print("  '\(key)' → '\(value)'")
        }

        if let installedModels = defaults.array(forKey: "installed") as? [String] {
            installedArr = installedModels
            print("📦 Already installed: \(installedArr)")
            tfliteArray = tfliteArray.filter { !installedArr.contains($0) }
            if let dict = defaults.value(forKey: "installedPath") as? [String: String] {
                installedPathArr = dict
            }
        }

        print("📋 Available for download: \(tfliteArray)")

        defaults.setValue(tfliteDict, forKey: "tfliteDict")

        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    // MARK: – Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if defaults.value(forKey: "installed") != nil {
            if section == 0 {
                return defaults.array(forKey: "installed")!.count
            } else {
                return tfliteArray.count
            }
        } else {
            return section == 0 ? 0 : tfliteArray.count
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            as! MenuTableViewCell
        cell.contentView.isUserInteractionEnabled = false

        if indexPath.section == 0 {
            let txt = defaults.array(forKey: "installed")![indexPath.row] as? String
            cell.titleLabel.text = txt
            cell.checkBox.isChecked = true
        } else {
            cell.titleLabel.text = tfliteArray[indexPath.row]
            cell.checkBox.isChecked = false
        }
        cell.checkBox.tag = indexPath.row
        cell.checkBox.isUserInteractionEnabled = true
        cell.checkBox.addTarget(
            self,
            action: #selector(clickCheckBox(sender:)),
            for: .touchUpInside
        )

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "")
        cell.backgroundColor = .white
        cell.textLabel?.textColor = .black
        cell.textLabel?.text = section == 0 ? "Installed" : "Available"
        cell.textLabel?.textAlignment = .center
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        heightForFooterInSection section: Int
    ) -> CGFloat {
        return 40
    }

    // MARK: – Checkbox Tapped

    @objc func clickCheckBox(sender: CheckBox) {
        if !sender.isChecked {
            let alert = UIAlertController(
                title: "Install",
                message: "Click Agree to download \(tfliteArray[sender.tag])",
                preferredStyle: .alert
            )
            let agree = UIAlertAction(title: "Agree", style: .default) { _ in
                sender.isChecked = true
                self.download(tag: sender.tag)
            }
            let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alert.addAction(agree)
            alert.addAction(cancel)
            self.present(alert, animated: false, completion: nil)
        } else {
            let modelToDelete = installedArr[sender.tag]
            let alert = UIAlertController(
                title: "Delete",
                message: "Click Delete to remove \(modelToDelete)",
                preferredStyle: .alert
            )
            let delete = UIAlertAction(title: "Delete", style: .default) { _ in
                sender.isChecked = false
                self.delete(tag: sender.tag)
            }
            let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alert.addAction(delete)
            alert.addAction(cancel)
            self.present(alert, animated: false, completion: nil)
        }
    }

    // MARK: – Download & Install

    func download(tag: Int) {
        DispatchQueue.main.async {
            self.setLoadingScreen()
        }

        DispatchQueue.global(qos: .background).async { [self] in
            let category = tfliteArray[tag]
            guard let modelFileName = tfliteDict[category] else {
                print("❌ ERROR: No model file name found for category: \(category)")
                DispatchQueue.main.async { self.removeLoadingScreen() }
                return
            }

            print("========")
            print("📥 Downloading model for category: '\(category)'")
            print("📄 Model file name: '\(modelFileName)'")
            print("========")

            let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!
            let modelDestinationURL = documentsURL.appendingPathComponent(modelFileName + ".tflite")
            let labelsDestinationURL = documentsURL.appendingPathComponent(modelFileName + "_lb.txt")

            try? FileManager.default.removeItem(at: modelDestinationURL)
            try? FileManager.default.removeItem(at: labelsDestinationURL)

            let downloadGroup = DispatchGroup()
            var modelDownloadSuccess = false
            var labelsDownloadSuccess = false

            // 1) Download .tflite model file
            let modelURLString = modelsBaseURL
                + modelFileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                + ".tflite"
            print("🔗 Model URL: \(modelURLString)")

            if let modelURL = URL(string: modelURLString) {
                downloadGroup.enter()
                let downloadTask = URLSession.shared.downloadTask(with: modelURL) { tempURL, response, error in
                    defer { downloadGroup.leave() }
                    if let error = error {
                        print("❌ Failed to download model file: \(error)")
                        return
                    }
                    guard let tempURL = tempURL else {
                        print("❌ No temporary URL for downloaded model")
                        return
                    }

                    do {
                        try FileManager.default.moveItem(at: tempURL, to: modelDestinationURL)
                        print("✅ Model file downloaded successfully to: \(modelDestinationURL.path)")

                        let fileSize = (try FileManager.default
                            .attributesOfItem(atPath: modelDestinationURL.path)[.size] as? Int64) ?? 0
                        print("📊 Model file size: \(fileSize) bytes")
                        if fileSize > 1_000_000 {
                            modelDownloadSuccess = true
                        } else {
                            print("❌ Model file seems too small, might be corrupted")
                        }
                    } catch {
                        print("❌ Failed to move model file: \(error)")
                    }
                }
                downloadTask.resume()
            }

            // 2) Download labels from Labelmaps
            let labelsURLString = labelsBaseURL
                + modelFileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                + "_lb.txt"
            print("🔗 Labels URL: \(labelsURLString)")

            if let labelsURL = URL(string: labelsURLString) {
                downloadGroup.enter()
                let downloadTask = URLSession.shared.downloadTask(with: labelsURL) { tempURL, response, error in
                    defer { downloadGroup.leave() }
                    if let error = error {
                        print("❌ Failed to download labels file: \(error)")
                        return
                    }
                    guard let tempURL = tempURL else {
                        print("❌ No temporary URL for downloaded labels")
                        return
                    }

                    do {
                        try FileManager.default.moveItem(at: tempURL, to: labelsDestinationURL)
                        print("✅ Labels file downloaded successfully to: \(labelsDestinationURL.path)")

                        let rawData = try Data(contentsOf: labelsDestinationURL)
                        if let preview = String(data: rawData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           preview.hasPrefix("<") {
                            print("❌ Labels file contains HTML – download failed")
                            try? FileManager.default.removeItem(at: labelsDestinationURL)
                        } else {
                            labelsDownloadSuccess = true
                        }
                    } catch {
                        print("❌ Failed to move/validate labels file: \(error)")
                    }
                }
                downloadTask.resume()
            }

            // 3) After both downloads complete
            downloadGroup.notify(queue: .main) {
                if modelDownloadSuccess && labelsDownloadSuccess {
                    // Save model path
                    var dict = [String: String]()
                    if let defaultDict = self.defaults.value(
                        forKey: "modelPath"
                    ) as? [String: String] {
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

                    print("💾 Saved labels with key: '\(categoryLabel)' → '\(labelsDestinationURL.path)'")

                    // Remove from available list
                    if let index = self.tfliteArray.firstIndex(of: category) {
                        self.tfliteArray.remove(at: index)
                    }

                    print("✅ Both files downloaded successfully!")
                    self.removeLoadingScreen()
                    self.dismiss(animated: false) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name(rawValue: "modelDataHandler"),
                            object: nil
                        )
                    }
                    self.tableView.reloadData()
                } else {
                    print("❌ Download failed – Model: \(modelDownloadSuccess), Labels: \(labelsDownloadSuccess)")
                    self.removeLoadingScreen()
                }
            }
        }
    }

    // MARK: – Delete Installed Model

    func delete(tag: Int) {
        let modelName = installedArr[tag]
        if let currentModel = defaults.string(forKey: "selectedModel"),
           currentModel == modelName
        {
            defaults.removeObject(forKey: "selectedModel")
        }

        if let fileName = tfliteDict[modelName] {
            let documentsUrl = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!

            let modelUrl = documentsUrl.appendingPathComponent("\(fileName).tflite")
            let labelUrl = documentsUrl.appendingPathComponent("\(fileName)_lb.txt")

            removeFile(at: modelUrl)
            removeFile(at: labelUrl)

            installedArr.remove(at: tag)
            installedPathArr.removeValue(forKey: modelName + "_lb.txt")

            if var modelPaths =
                defaults.dictionary(forKey: "modelPath") as? [String: String]
            {
                modelPaths.removeValue(forKey: modelName)
                defaults.set(modelPaths, forKey: "modelPath")
            }

            tfliteArray.append(modelName)

            defaults.setValue(installedArr, forKey: "installed")
            defaults.setValue(installedPathArr, forKey: "installedPath")

            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        } else {
            print("Model name not found in dictionary.")
        }
    }

    func removeFile(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("Successfully removed: \(url.lastPathComponent)")
            } else {
                print("File does not exist at path: \(url.path)")
            }
        } catch {
            print("Could not remove file at \(url): \(error)")
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let currentCell = tableView.cellForRow(at: indexPath) as! MenuTableViewCell
        clickCheckBox(sender: currentCell.checkBox)
    }

    // MARK: – URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let savedURL = documentsURL.appendingPathComponent(location.lastPathComponent)
            print("Saved URL: \(savedURL)")
            try FileManager.default.moveItem(at: location, to: savedURL)
        } catch {
            print("😀 file error: \(error)")
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // We no longer compare to a non‐existent `self.downloadTask`.
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        print("Download progress for \(downloadTask): \(progress)")
    }
}
