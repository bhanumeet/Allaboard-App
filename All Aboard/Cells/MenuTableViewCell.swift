//
//  MenuTableViewCell.swift
//  All Aboard
//
//  Created by Wiper on 23/07/21.
//

import UIKit

class MenuTableViewCell: UITableViewCell {

    var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    var checkBox: CheckBox = {
        let button = CheckBox()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    var switch1: UISwitch = {
        let button = UISwitch()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    var button: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        if (reuseIdentifier == "Cell") {
            setupViews()
        } else if (reuseIdentifier == "SettingsCell") {
            setupView1()
        } else if (reuseIdentifier == "AddTransitCell") {
            setupView2()
        } else if (reuseIdentifier == "OtherCell") {
            setupView3()
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setupViews() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(checkBox)
        
        backgroundColor = .white
        
        titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .left
        titleLabel.textColor = .black
        
        checkBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        checkBox.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
        checkBox.widthAnchor.constraint(equalToConstant: 30).isActive = true
        checkBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
        titleLabel.trailingAnchor.constraint(equalTo: checkBox.leadingAnchor, constant: -50).isActive = true
    }
    
    func setupView1() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(switch1)
        
        backgroundColor = .white
        
        titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .left
        titleLabel.textColor = .black
        
        switch1.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32).isActive = true
        switch1.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
        switch1.widthAnchor.constraint(equalToConstant: 30).isActive = true
        switch1.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
        //titleLabel.trailingAnchor.constraint(equalTo: switch1.leadingAnchor, constant: -50).isActive = true
    }
    
    func setupView2() {
        contentView.addSubview(button)
        
        backgroundColor = .white
        
        button.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        button.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        button.widthAnchor.constraint(equalToConstant: 150).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.black.cgColor
    }
    
    func setupView3() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(button)
        
        backgroundColor = .white
        
        titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .left
        titleLabel.textColor = .black
        
        button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 8).isActive = true
        button.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true
        button.widthAnchor.constraint(equalToConstant: 200).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.setTitleColor(.black, for: .normal)
        button.semanticContentAttribute = UIApplication.shared
            .userInterfaceLayoutDirection == .rightToLeft ? .forceLeftToRight : .forceRightToLeft
        button.tintColor = .black
    }
}
