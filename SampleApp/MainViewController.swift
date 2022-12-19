//
//  MainViewController.swift
//  SampleApp

import UIKit
import Combine

class MainViewController: UIViewController {

    var model: Model?

    @IBOutlet weak var bluetoothIcon: UIImageView?
    @IBOutlet weak var networkIconIcon: UIImageView?
    @IBOutlet weak var statusLabel: UILabel?

    private var cancellables: Set<AnyCancellable> = []

    override func loadView() {
        super.loadView()

        if model == nil {
            let model = Model()

            model.statusPublisher
                .receive(on: DispatchQueue.main)
                .sink {[unowned self] statusString in
                    statusLabel?.text = statusString
                }
                .store(in: &cancellables)

            model.connectionPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isConnected in
                    self?.handleConnectionStatus(isConnected)
                }
                .store(in: &cancellables)

            model.bleActivityPublisher
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: { [weak self] floatValue in
                    self?.handleBLEactivityValue(floatValue)
                })
                .store(in: &cancellables)

            model.permissionsPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] granted in
                    if granted {
                        self?.proceedWithBLEandNetworking()
                    }
                }
                .store(in: &cancellables)

            model.messageSentActionPubliosher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.blinkNetworkingIcon()
                }
                .store(in: &cancellables)

            self.model = model
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        model?.checkAndRequestSystemPermissions()
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

    private func proceedWithBLEandNetworking() {
        model?.prepare { [weak self] in
            guard let self, let model = self.model else {
                return
            }

            if model.canStart() {
                model.start()
            }
        }
    }

    private func blinkNetworkingIcon() {
        statusLabel?.text = "sent Tags Info at: \(Date())"

        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {[unowned self] in
            networkIconIcon?.alpha = 0.7

        } completion: {  _ in
            UIView.animate(withDuration: 0.2, delay: 0.1, animations: {[unowned self] in
                networkIconIcon?.alpha = 1.0
            }, completion: nil)

        }
    }

}
