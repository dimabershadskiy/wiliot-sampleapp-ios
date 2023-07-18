

import Foundation
import Combine

///plist value reading key
fileprivate let kAPPTokenKey = "app_token"
///plist value reading key
fileprivate let kOwnerIdKey = "owner_id"
fileprivate let kConstantsPlistFileName = "SampleAuthConstants"

@objc class Model:NSObject {
    
    private(set) lazy var permissions:Permissions = Permissions()
    
    var permissionsPublisher:AnyPublisher<Bool, Never> {
        _permissionsPublisher.eraseToAnyPublisher()
    }
    
    var statusPublisher:AnyPublisher<String,Never> {
        return _statusPublisher.eraseToAnyPublisher()
    }
    
    var connectionPublisher:AnyPublisher<Bool,Never> {
        return _mqttConnectionPublisher.eraseToAnyPublisher()
    }
    
    var bleActivityPublisher:AnyPublisher<Float, Never> {
        return _bleScannerPublisher.eraseToAnyPublisher()
    }
    
    //sends some text for better overall status understanding
    var messageSentActionPublisher:AnyPublisher<String,Never> {
        return _mqttSentMessagePublisher.eraseToAnyPublisher()
    }
    
    
    private let _statusPublisher:CurrentValueSubject<String, Never> = .init("")
    private let _mqttConnectionPublisher:CurrentValueSubject<Bool, Never> = .init(false)
    private let _bleScannerPublisher:CurrentValueSubject<Float, Never> = .init(0.0)
    private let _permissionsPublisher:PassthroughSubject<Bool, Never> = .init()
    private let _mqttSentMessagePublisher:PassthroughSubject<String,Never> = .init()
    
    private var appToken = ""
    private var ownerId = ""
    private var gatewayService:MobileGatewayService?
    private var bleService:BLEService?
    private var blePacketsmanager:BLEPacketsManager?
    private var networkService:NetworkService?
    private var locationService:LocationService?
    
    private var permissionsCompletionCancellable:AnyCancellable?
    private var gatewayServiceMessageCancellable:AnyCancellable?
    
    //MARK: -
    override init() {
        super.init()
    }
    
    func loadRequiredData() {
        do {
            try tryReadRequiredUserData()
            checkAndRequestSystemPermissions()
        }
        catch {
            _statusPublisher.send(error.localizedDescription)
        }
    }
    
    private func canPrepare() -> Bool {
        guard permissions.gatewayPermissionsGranted && !appToken.isEmpty && !ownerId.isEmpty else {
            return false
        }
        return true
    }
    
    private func prepare(completion: @escaping (() -> ())) {
        
        if gatewayService == nil {
            createGatewayServiceAndSubscribe()
        }
        
        guard let gwService = self.gatewayService else {
            return
        }
        
        gwService.authTokenCallback = {[weak self] optionalError in
            guard let self = self else {
                return
            }
            
            if let error = optionalError {
               
                if let badServerResp = error as? BadServerResponse {
                    self._statusPublisher.send("Token get callback Error: \(badServerResp.description)")
                }
                else if let valueReadingError = error as? ValueReadingError {
                    self._statusPublisher.send("Token get callback Error: \(valueReadingError.description)")
                }
                else {
                    self._statusPublisher.send("Token get callback Error: \(error.localizedDescription)")
                }
                
                completion()
                return
            }
            
            self._statusPublisher.send("Auth token received")
            
            completion()
        }
        
        gwService.obtainAuthToken()
    }
    
    private func createGatewayServiceAndSubscribe() {
        var nService:NetworkService?
        
        if let netService = self.networkService {
            nService = netService
        }
        else {
            let netService = NetworkService(appKey: appToken,
                                            ownerId: ownerId)
            self.networkService = netService
            nService = networkService
        }
        
        guard let netServ = nService else {
            return
        }
        
        let gwService = MobileGatewayService(ownerId: ownerId,
                                             authTokenRequester: WeakObject(netServ),
                                             gatewayRegistrator: WeakObject(netServ))
        
        gwService.didConnectCompletion = {[weak self] connected in
            self?._mqttConnectionPublisher.send(connected)
            if connected {
                self?.startBLE()
            }
        }
        
        gwService.didStopCompletion = {[weak self] in
            self?._mqttConnectionPublisher.send(false)
        }
        
        gatewayServiceMessageCancellable =
        gwService.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink {[weak self] message in
                guard let weakSelf = self else {
                    return
                }
                
                if let messageString = message {
                    weakSelf._statusPublisher.send(messageString)
                }
            }
        
        self.gatewayService = gwService
    }
    
    private func canStart() -> Bool {
        if self.gatewayService?.authToken != nil {
            return true
        }
        return false
    }
    
    private func start() {
        _statusPublisher.send("Starting Connection..")
        startGateway()
    }
    
    //MARK: - PRIVATE
    private func tryReadRequiredUserData() throws {
        _statusPublisher.send("Reading API Token and Owner ID")
        
        guard let plistPath = Bundle.main.path(forResource: kConstantsPlistFileName, ofType: "plist"),
              let dataXML = FileManager.default.contents(atPath: plistPath)else {
            #if DEBUG
            print("No required data found in app Bundle. No required'\(kConstantsPlistFileName)' file")
            #endif
            throw ValueReadingError.missingRequiredValue("No required data found in app Bundle")
        }
        
        do {
            var propertyListFormat =  PropertyListSerialization.PropertyListFormat.xml
            let anObject = try PropertyListSerialization.propertyList(from: dataXML, options: .mutableContainersAndLeaves, format: &propertyListFormat)
            
            guard let values = anObject as? [String:String] else {
                #if DEBUG
                print("The '\(kConstantsPlistFileName)' file has wrong format.")
                #endif
                throw ValueReadingError.missingRequiredValue("Wrong Required Data format.")
            }
            
            guard let lvAppToken = values[kAPPTokenKey],
                  let lvOwnerId = values[kOwnerIdKey],
                  !lvAppToken.isEmpty,
                  !lvOwnerId.isEmpty else {
                
                #if DEBUG
                print("The app needs Owner_Id and Api_Key to be supplied in the '\(kConstantsPlistFileName)' file")
                #endif
                
                throw ValueReadingError.missingRequiredValue("No APP Token or Owner ID. Please provide values in the project file named '\(kConstantsPlistFileName)'.")
            }
            
            appToken = lvAppToken
            ownerId = lvOwnerId
            _statusPublisher.send("plist values present. OwnerId: \(lvOwnerId)")
            
        }
        catch(let plistError) {
            throw plistError
        }
        
    }
    
    private func checkAndRequestSystemPermissions() {
        permissions.checkAuthStatus()
        
        if !permissions.gatewayPermissionsGranted {
            
            self.permissionsCompletionCancellable =
            permissions.gatewayPermissionsPublisher
                .sink {[weak self] granted in
                    if let weakSelf = self {
                        weakSelf.handlePermissionsRequestsCompletion(granted)
                    }
                }
            _statusPublisher.send("Requesting system permissions...")
            permissions.requestPermissions()
        }
        else {
            handlePermissionsRequestsCompletion(true)
        }
    }
    
    
    private func handlePermissionsRequestsCompletion(_ granted:Bool) {
       
        if !granted {
            _statusPublisher.send("No required BLE or Location permissions.")
            return
        }
        
        defer {
            permissionsCompletionCancellable = nil
        }
        _statusPublisher.send("Required BLE and Location permissions granted.")
        _permissionsPublisher.send(granted)
        
        if canPrepare() {
            prepare {[weak self] in
                guard let weakModel = self else {
                    return
                }
                if weakModel.canStart() {
                    weakModel.start()
                }
            }
        }
        
    }
    
    //MARK: -
    
    private func startGateway() {
        guard let gatewayService = self.gatewayService,
              let authToken = gatewayService.authToken else {
            return
        }
        
        gatewayService.gatewayTokensCallBack = {[weak self] optionalError in
            guard let self = self else { return }
            
            if let error = optionalError {
                self._statusPublisher.send("Error obtaining connectionTokens: \(error)")
                return
            }
            
            self._statusPublisher.send("Obtained connection tokens")
            if let gwService = self.gatewayService,
               let accessToken = gwService.gatewayAccessToken {
                
                let _ = gatewayService.startConnection(withGatewayToken: accessToken)
            }
            
        }
        
        gatewayService.registerAsGateway(userAuthToken: authToken, ownerId: ownerId)
        
    }
    
    private func startBLE() {
        
        _statusPublisher.send("Starting BLE scanning")
        _bleScannerPublisher.send(0.0)
        
        let locService = LocationService()
        self.locationService = locService
        locService.startLocationUpdates()
        locService.startRanging()
        
        
        let bleService = BLEService()
        self.bleService = bleService
        
        guard let gwService = self.gatewayService else {
            return
        }
        
        let pacingService = PacketsPacingService(with: WeakObject(gwService))
        let pacingObject:PacketsPacing = pacingService
        
        gwService.setSendEventSignal {[weak self] messageString in
            self?._mqttSentMessagePublisher.send((messageString))
        }
        gwService.locationSource = WeakObject(locService)
        
        let sideInfoHandler = SideInfoPacketsManager(packetsSenderAgent: WeakObject(gwService), pacingReceiver: pacingObject)
        
        let nearbyBridgesUpdater = NearbyBridgesUpdater(bridgePayloadsSender: WeakObject(sideInfoHandler))
        
        let bleManager = BLEPacketsManager(pacingReceiver: pacingObject,
                                           sideInfoPacketsHandler: sideInfoHandler,
                                           bridgesUpdater: nearbyBridgesUpdater,
                                           locationSource: WeakObject(locService))
        
        self.blePacketsmanager = bleManager
        bleManager.subscribeToBLEpacketsPublisher(publisher: bleService.packetPublisher)
        
        
        
        bleService.setScanningMode(inBackground: false)
        bleService.startListeningBroadcasts()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[unowned self] in
            _bleScannerPublisher.send(0.5)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[unowned self] in
            _bleScannerPublisher.send(1.0)
        }
    }
    
}
