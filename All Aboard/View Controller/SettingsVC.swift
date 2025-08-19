//
//  SettingsVC.swift
//  All Aboard
//
//  Created by Wiper on 26/07/21.
//  Updated by Meet on 05/27/2025.
//

import UIKit

class SettingsVC: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    // MARK: – Table setup
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            // Section 0 is now Bus Transit + Certainty
            return 2
        } else {
            // Section 1 is Add Bus Transit
            return 1
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Section 0: Detection (Bus Transit, Certainty)
        if indexPath.section == 0 {
            let cell: MenuTableViewCell
            if indexPath.row == 0 {
                // Bus Transit
                cell = MenuTableViewCell(style: .default, reuseIdentifier: "OtherCell")
                cell.titleLabel.text = "Bus Transit"
                let str = defaults.string(forKey: "selectedModel")
                cell.button.setTitle(str, for: .normal)
                cell.button.addTarget(self, action: #selector(setModel), for: .touchUpInside)
                if #available(iOS 13.0, *) {
                    cell.button.setImage(UIImage(systemName: "arrowtriangle.down.fill"), for: .normal)
                }
            } else {
                // Certainty
                cell = MenuTableViewCell(style: .default, reuseIdentifier: "OtherCell")
                cell.titleLabel.text = "Certainty"
                let val = defaults.value(forKey: "Certainty") == nil ? 0.7 : defaults.double(forKey: "Certainty")
                cell.button.setTitle(dict[val], for: .normal)
                cell.button.addTarget(self, action: #selector(setCertainty), for: .touchUpInside)
                if #available(iOS 13.0, *) {
                    cell.button.setImage(UIImage(systemName: "arrowtriangle.down.fill"), for: .normal)
                }
            }
            return cell
            
        // Section 1: Add Bus Transit
        } else {
            let cell = MenuTableViewCell(style: .default, reuseIdentifier: "AddTransitCell")
            cell.button.setTitle("Add Bus Transit", for: .normal)
            cell.button.addTarget(self, action: #selector(addTransit), for: .touchUpInside)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .white
        cell.textLabel?.textColor = .black
        cell.textLabel?.textAlignment = .center
        cell.textLabel?.text = titles[section]
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 40
    }
    
    // MARK: – Properties
    
    private let defaults = UserDefaults.standard
    private let dict: [Double: String] = [
        0.5: "50%",
        0.6: "60%",
        0.7: "Default - 70%",
        0.8: "80%",
        0.9: "90%"
    ]
    private let titles = ["Detection", ""]
    
    private var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .grouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    private var safeLayout = UILayoutGuide()
    
    // MARK: – Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "Settings"
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    }
    
    override func loadView() {
        super.loadView()
        if #available(iOS 11.0, *) {
            safeLayout = view.safeAreaLayoutGuide
        }
        setUpViews()
    }
    
    private func setUpViews() {
        tableView.register(MenuTableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorInset = .zero
        tableView.tableFooterView = UIView()
        tableView.backgroundColor = .white
        
        view.addSubview(tableView)
        if #available(iOS 11.0, *) {
            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: safeLayout.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: safeLayout.bottomAnchor),
                tableView.leadingAnchor.constraint(equalTo: safeLayout.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: safeLayout.trailingAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
    }
    
    // MARK: – Actions
    
    @objc private func addTransit() {
        if #available(iOS 13.0, *) {
            let vc = MenuTableVC()
            present(vc, animated: false, completion: nil)
        } else {
            print("required IOS version not available")
        }
    }
    
    @objc private func setCertainty() {
        let alertController = UIAlertController(title: "Certainty values:", message: "Select a value", preferredStyle: .alert)
        [("50%", 0.5), ("60%", 0.6), ("70%", 0.7), ("80%", 0.8), ("90%", 0.9)].forEach { title, value in
            alertController.addAction(UIAlertAction(title: title, style: .default) { _ in
                self.defaults.setValue(value, forKey: "Certainty")
                self.tableView.reloadData()
            })
        }
        present(alertController, animated: true)
    }
    
    @objc private func setModel() {
        let alertController = UIAlertController(title: "Select an installed model", message: nil, preferredStyle: .alert)
        if let dict = defaults.value(forKey: "modelPath") as? [String: String] {
            dict.keys.sorted().forEach { key in
                alertController.addAction(UIAlertAction(title: key, style: .default) { _ in
                    self.defaults.setValue(key, forKey: "selectedModel")
                    NotificationCenter.default.post(name: Notification.Name(rawValue: "modelDataHandler"), object: nil)
                    self.tableView.reloadData()
                })
            }
        }
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alertController, animated: true)
    }
}
