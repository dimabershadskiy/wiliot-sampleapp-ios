//
//  BLEUpstreamService.swift
//  BLEUpstream
//
//  Created by Ivan Yavorin on 08.02.2024.
//  Copyright © 2024 Wiliot. All rights reserved.
//

import Foundation
import Combine
import CoreBluetooth
import CoreLocation

import WiliotCore

public enum BLEUpstreamConnectionStatus {
    case inactive //idle
    case prepared
    case connecting //attempt to connect to the mqtt broker
    case connected // connected to the mqt broer and sending at least 'keepAlive' packets
    case failure(String) // failed to connect or was disconnected
}

public enum BLEUpstreamBluetoothAccessError:Error {
    case bleAuthUnknown
    case bleUnauthorized
    case bleRestricted
    case bleAuthUnhandled
}

public enum BLEUpstreamLocationAccessError:Error {
    case locationAuthUnknown
    case locationUnauthorized
    case locationRestricted
    case locationAuthUnhandled
}

public enum BLEUpstreamPermissionsError:Error {
    case bluetooth(BLEUpstreamBluetoothAccessError)
    case location(BLEUpstreamLocationAccessError)
}

fileprivate var logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUpstreamService")

public final class BLEUpstreamService {
    
    #if DEBUG
    private static var refCount:Int = 0 {
        didSet {
            logger.log("refCount: \(Self.refCount)")
        }
    }
    #endif
    
    public var statusPublisher:AnyPublisher<BLEUpstreamConnectionStatus, Never> {
        self._statusPasthrough.eraseToAnyPublisher()
    }
    
    public var bleSubsystemStatusPublisher:AnyPublisher<BLEUScanState, Never> {
        self._bleStatusPublisher.eraseToAnyPublisher()
    }

    public var connectableBridgeIdPublisher:AnyPublisher<String, Never> {
        self._connectableBridgesPassThrough.eraseToAnyPublisher()
    }
    
    public var bleIsListeningPublisher:AnyPublisher<Bool, Never> {
        self._bleIsListeningPassthrough.eraseToAnyPublisher()
    }
    
    private lazy var _statusPasthrough:PassthroughSubject<BLEUpstreamConnectionStatus, Never> = .init()
    private lazy var _bleStatusPublisher:PassthroughSubject<BLEUScanState, Never> = .init()
    private lazy var _connectableBridgesPassThrough:PassthroughSubject<String, Never> = .init()
    private lazy var _bleIsListeningPassthrough:PassthroughSubject<Bool, Never> = .init()
    
    
    private var config:BLEUServiceConfiguration
    
    //MARK: - init
    public init(configuration:BLEUServiceConfiguration) throws {
        #if DEBUG
        Self.refCount += 1
        
        logger.notice("Config: \(configuration.accountId.string),")
        #endif
        self.config = configuration
        
        let bleService = try BLEUCentralManagerService()
        self.bleService = bleService
    }
    //MARK: Deinit
    deinit {
        #if DEBUG
        Self.refCount -= 1
        #endif
    }
    
    //MARK: -
    private let bleService:BLEUCentralManagerService
    private var scanStateCancellable:AnyCancellable?
    private var connectableBridgesPassthroughCancellable:AnyCancellable?
    private var isBLEScanningCancellable:AnyCancellable?
    
    private var mqttGatewayService:BLEUMobileGatewayService?
    private var gatewayServiceConnectionCancellable:AnyCancellable?
    
    private var blePacketsRouter:BLEUPacketsRouter?
    private var blePacketsManager:BLEUPacketsManager?
    private var packetsPacingService:BLEUPacketsPacingService?
    
    private var stopCompletionCallback:(()->Void)?
    //MARK: -
    
    private var tempConnectionTokenContainer:NonEmptyCollectionContainer<String>?
    
    
    public func setScanningMode(inBackground: Bool) {
        self.bleService.setScanningMode(inBackground: inBackground)
    }
    
    public func getGatewayId() -> String {
        return self.config.deviceId.string
    }
    
    public func setPreferredConnectionType(_ connectionType:PreferredConnectionType) {
        guard let mqttGatewayService else {
            return
        }
        
        mqttGatewayService.setPreferredConnectionType(connectionType)
    }
    
    public func setTagsPayloadLoggingEnabled(_ isTagsLoggingEnabled:Bool) {
        if self.config.tagPayloadsLoggingEnabled != isTagsLoggingEnabled {
            self.config.setTagPayloadsLoggingEnabled(isTagsLoggingEnabled)
            
            guard let blePacketsRouter else {
                return
            }
            
            if isTagsLoggingEnabled , let weakService = self.createTagsPayloadLogService() {
                blePacketsRouter.setTagsPayloadsLogsSender(weakService)
            }
            else {
                blePacketsRouter.setTagsPayloadsLogsSender(nil)
            }
        }
        
        
    }
    
    public func prepare(withToken container:NonEmptyCollectionContainer<String>) {
        config.externalLogger?.logMessage("\(#function)")
        
        self.tempConnectionTokenContainer = container
        self._statusPasthrough.send(.prepared)
    }
    
    public func start() throws {
        config.externalLogger?.logMessage("\(#function)")
        try blePermissionCheck()
        
        try locationPermissionsCheck()
        
        logger.info("\(#function) required system permissions check passed")
        
        guard let container = self.tempConnectionTokenContainer else {
            throw ValueReadingError.missingRequiredValue("No Connection Token")
        }
        
        logger.info("\(#function) connection token is present")
        
        let gwConfig = BLEUMobileGatewayConfig(locationSource: self.config.coordinatesContainer,
                                               endpoint: config.endpoint,
                                               accountId: config.accountId,
                                               appVersion: config.appVersion,
                                               gatewayId: config.deviceId, 
                                               connectionToken: container)
        
        self.tempConnectionTokenContainer = nil
        let gatewayService = BLEUMobileGatewayService(config: gwConfig)
        
        self.mqttGatewayService = gatewayService

        
        var packetsPacing:PacketsPacing?
        if config.pacingEnabled {
            let pacingService = BLEUPacketsPacingService(with: WeakObjectContainer(gatewayService),
                                                         pacingInterval: BLEUMobileGatewayService.pacingInterval)
            
            self.packetsPacingService = pacingService
            packetsPacing = WeakObjectContainer(pacingService)
        }
        
        
        let packetsManager = BLEUPacketsManager(packetsSenderAgent: WeakObjectContainer(gatewayService),
                                                pacedPacketsReceiver: packetsPacing,
                                                externalLogger: self.config.externalLogger)
        
        self.blePacketsManager = packetsManager
        
        var logPayloadsSenderOrNil:TagPacketsPayloadLogSender?
        
        if config.tagPayloadsLoggingEnabled {
            logPayloadsSenderOrNil = self.createTagsPayloadLogService()
        }
        
        
        
        let routerConfig = BLEUPacketsRouterConfiguration(coordinatesContainer: config.coordinatesContainer,
                                                          tagPacketsReceiver: WeakObjectContainer(packetsManager), 
                                                          thirdPartyDataPacketsReceiver: WeakObjectContainer(packetsManager),
                                                          sideInfoPacketsReceiver: WeakObjectContainer(packetsManager),
                                                          combinedPacketsReceiver: WeakObjectContainer(packetsManager),
                                                          bridgeMessagesPacketsReceiver: WeakObjectContainer(packetsManager),
                                                          tagPacketsLogsSender: logPayloadsSenderOrNil,
                                                          externatOutputs: config.externalReceivers)
        
        let blePacketsRouter = BLEUPacketsRouter(routerConfiguration: routerConfig)
        self.blePacketsRouter = blePacketsRouter
        
        blePacketsRouter.subscribeToBLEpacketsFrom(publisher: bleService.blePacketsPublisher)
        
        //start connection and after that - listen to broadcasts
        
        self.gatewayServiceConnectionCancellable =
        gatewayService.connectionStatePublisher.sink { [weak self] connectionState in
            guard let self else { return }
            self.handleConnectionState(connectionState)
        }
        
        config.externalLogger?.logMessage("\(#function) gatewayService.startConnection()")
        try gatewayService.startConnection()
        
        config.externalLogger?.logMessage("\(#function) packetsManager.start()")
        try packetsManager.start()
        
        //start BLE
        
        self.scanStateCancellable =
        bleService.scanStatePublisher.sink {[weak self] state in
            guard let self else { return }
            logger.notice("BLEStatus: \(state.managerState.rawValue), StatusString: \(state.statusString)")
            self._bleStatusPublisher.send(state)
        }
        
        
        self.connectableBridgesPassthroughCancellable =
        bleService.connectableBridgeIdPublisher.sink {[weak self] connectableBridgeString in
            guard let self else { return }
            logger.notice("Connectable Bridge ID: '\(connectableBridgeString)'")
            self._connectableBridgesPassThrough.send(connectableBridgeString)
        }
        
        self.isBLEScanningCancellable =
        bleService.isBLEScanningPublisher.sink {[weak self] isScanning in
            guard let self else { return }
            logger.notice("Ble Is Listening Broadcasts: \(isScanning)")
            self._bleIsListeningPassthrough.send(isScanning)
        }
        config.externalLogger?.logMessage("\(#function) bleService.startListeningBroadcasts()")
        bleService.startListeningBroadcasts()
    }
    
    public func stop(completion: @escaping () -> Void ) {
        config.externalLogger?.logMessage("\(#function) \(self.self) blePacketsManager.stop()")
        
        self.stopCompletionCallback = completion
        config.externalLogger?.logMessage("\(#function) mqttGatewayService?.prepareToBeDeallocated()")
        self.mqttGatewayService?.prepareToBeDeallocated()
        config.externalLogger?.logMessage("\(#function) mqttGatewayService?.stop()")
        self.mqttGatewayService?.stop()
        
        config.externalLogger?.logMessage("\(#function) bleService.stopListeningBroadcasts()")
        
        bleService.stopListeningBroadcasts()
        
        connectableBridgesPassthroughCancellable?.cancel()
        connectableBridgesPassthroughCancellable = nil
        
        scanStateCancellable?.cancel()
        scanStateCancellable = nil
        
        isBLEScanningCancellable?.cancel()
        isBLEScanningCancellable = nil
        config.externalLogger?.logMessage("\(self.self) \(#function) blePacketsManager.stop()")
        blePacketsManager?.stop()
        
        defer {
            config.externalLogger?.logMessage("\(self.self) \(#function) DEFER statusPasthrough.send(.inactive)")
            self._statusPasthrough.send(.inactive)
        }
        
        self._bleIsListeningPassthrough.send(false)
        self._bleStatusPublisher.send(BLEUScanState(managerState: .poweredOn, statusString: "stopped"))
    }
    
    public func setConnectionToken(_ container:NonEmptyCollectionContainer<String>) {
        self.mqttGatewayService?.setNewGatewayAuthToken(container)
    }
    
    //MARK: -
    private func blePermissionCheck() throws {
        switch CBCentralManager.authorization {
        case .notDetermined:
            throw BLEUpstreamPermissionsError.bluetooth( .bleAuthUnknown)
        case .denied:
            throw BLEUpstreamPermissionsError.bluetooth( .bleUnauthorized)
        case .restricted:
            throw BLEUpstreamPermissionsError.bluetooth( .bleRestricted)
        case .allowedAlways:
            break
        @unknown default:
            throw BLEUpstreamPermissionsError.bluetooth( .bleAuthUnhandled)
        }
    }
    
    private func locationPermissionsCheck() throws {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            throw BLEUpstreamPermissionsError.location(.locationAuthUnknown)
        case .denied:
            throw BLEUpstreamPermissionsError.location(.locationUnauthorized)
        case .restricted:
            throw BLEUpstreamPermissionsError.location(.locationRestricted)
        @unknown default:
            throw BLEUpstreamPermissionsError.location(.locationAuthUnhandled)
        }
    }
    
    private func handleConnectionState(_ state:BLEUMobileGatewayConnectionState ) {
        switch state {
        
        case .disconnected:
//            if let stopCompletionCallback {
//                stopCompletionCallback()
//            }
            self._statusPasthrough.send(.inactive)
            if let stopCompletionCallback {
                stopCompletionCallback()
            }
        case .connecting, .disconnecting:
            self._statusPasthrough.send(BLEUpstreamConnectionStatus.connecting)
        case .connected:
            self._statusPasthrough.send(BLEUpstreamConnectionStatus.connected)
        case .disconnectedWithError(let string):
            self._statusPasthrough.send(BLEUpstreamConnectionStatus.failure(string))
        }
    }
    
    private func createTagsPayloadLogService() -> TagPacketsPayloadLogSender? {
        guard let mqttGatewayService else { return nil }
        
        return WeakObjectContainer(mqttGatewayService) as TagPacketsPayloadLogSender
    }
}
