//
//  MainViewController.swift
//  SampleApp

import UIKit
import Combine

class MainViewController: UIViewController {

    var model:Model?
    
    @IBOutlet private weak var bluetoothIcon:UIImageView?
    @IBOutlet private weak var networkIconIcon:UIImageView?
    @IBOutlet private weak var statusLabel:UILabel?
    
    @IBOutlet private weak var counterDidPublishMessageLabel:UILabel?
    @IBOutlet private weak var counterDidPingMessageLabel:UILabel?
    @IBOutlet private weak var counterDidReceivePongMessageLabel:UILabel?
    
    private var didPublishCounter:Int = 0 {
        didSet {
            counterDidPublishMessageLabel?.text = "\(didPublishCounter)"
        }
    }
    
    private var didPingCounter:Int = 0 {
        didSet {
            counterDidPingMessageLabel?.text = "\(didPingCounter)"
        }
    }
    
    private var didReceivePongCounter:Int = 0 {
        didSet {
            counterDidReceivePongMessageLabel?.text = "\(didReceivePongCounter)"
        }
    }
    
    private var cancellables:Set<AnyCancellable> = []
    
    override func loadView() {
        super.loadView()

        if model == nil {

            let model = Model()
            self.model = model
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        self.subscribeForModelUpdates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let model = self.model else {
            return
        }
        
        model.loadRequiredData()
    }
    
    private func subscribeForModelUpdates() {
        guard let model = self.model else {
            return
        }
        
        model.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink {[unowned self] statusString in
                statusLabel?.text = statusString
            }
            .store(in: &cancellables)
        
        model.connectionPublisher
            .receive(on:DispatchQueue.main)
            .sink {[weak self] isConnected in
                self?.handleConnectionStatus(isConnected)
            }
            .store(in: &cancellables)
        
        model.bleActivityPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: {[weak self] floatValue in
                self?.handleBLEactivityValue(floatValue)
            })
            .store(in: &cancellables)
        
        model.messageSentActionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eventMessageString in
                self?.blinkNetworkingIcon()
                self?.handleEventMessage(eventMessageString)
            }
            .store(in: &cancellables)
    }

    private func handleConnectionStatus(_ isConnected: Bool) {
        if isConnected {
            networkIconIcon?.image = UIImage(systemName: "icloud.and.arrow.up.fill")
            networkIconIcon?.tintColor = .systemGreen
            statusLabel?.text = "Connected"
        } else {
            networkIconIcon?.image = UIImage(systemName: "xmark.icloud")
            networkIconIcon?.tintColor = .lightGray
            statusLabel?.text = "Not connected"
        }
    }

    private func handleBLEactivityValue(_ value: Float) {
        if value > 0 {
            if #available(iOS 16.0, *) {
                bluetoothIcon?.image = UIImage(systemName: "antenna.radiowaves.left.and.right", variableValue: Double(value))
            } else {
                // Fallback on earlier versions
                bluetoothIcon?.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
            }
            bluetoothIcon?.tintColor = .systemBlue
        } else {
            bluetoothIcon?.image = UIImage(systemName: "antenna.radiowaves.left.and.right.slash")
            bluetoothIcon?.tintColor = .lightGray
        }
    }
    
    private func blinkNetworkingIcon() {
        statusLabel?.text = "sent Tags Info at: \(Date())"

        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {[unowned self] in
            networkIconIcon?.alpha = 0.7

        } completion: {  _ in
            UIView.animate(withDuration: 0.2, delay: 0.1, animations: {[unowned self] in
                networkIconIcon?.alpha = 1.0
            }, completion: nil )

        }
    }

    private func handleEventMessage(_ message:String) {
        switch message {
        case "didPublishMessage":
            self.didPublishCounter += 1
        case "didPing":
            self.didPingCounter += 1
        case "didReceivePong":
            self.didReceivePongCounter += 1
        default:
            break
        }
    }
}
