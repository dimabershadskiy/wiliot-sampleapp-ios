import Foundation
import Combine

import WiliotCore
import BLEUpstream

///plist value reading key
fileprivate let kAPPTokenKey = "app_token"
///plist value reading key
fileprivate let kOwnerIdKey = "owner_id"
fileprivate let kConstantsPlistFileName = "SampleAuthConstants"

@objc class Model:NSObject {
    
    private(set) lazy var permissions:Permissions = Permissions()
    
    private var bleUpstreamService:BLEUpstreamService?
    
    var permissionsPublisher:AnyPublisher<Bool, Never> {
        _permissionsPublisher.eraseToAnyPublisher()
    }

    var statusPublisher: AnyPublisher<String, Never> {
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
//    private var gatewayService:MobileGatewayService?
//    private var bleService:BLEService?
//    private var blePacketsmanager:BLEPacketsManager?
    private var networkService:NetworkService?
    private var locationService:LocationService?
    
    private var permissionsCompletionCancellable:AnyCancellable?
    private var gatewayServiceMessageCancellable:AnyCancellable?
    private var appBuildInfo:String = ""
    //MARK: -
    override init() {
        super.init()
        
        DispatchQueue.global(qos: .default).async {[weak self] in
            guard let self else { return }
            
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                self.appBuildInfo = "\(version) (build \(build))"
            }
        }
        
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
    
    private func prepare(completion: @escaping ((Error?) -> ())) {
        let token:String = self.appToken
        let ownerId:String = self.ownerId
        
        let gatewayAuthToken:NonEmptyCollectionContainer<String> = .init(token) ?? .init("<supply Gateway_Auth_token>")!
        
        let accountIdContainer = NonEmptyCollectionContainer<String>(ownerId) ?? NonEmptyCollectionContainer("SampleApp_Test")!
        let deviceIdStr:String = Device.deviceId
        let appVersionContainer = NonEmptyCollectionContainer(self.appBuildInfo) ?? NonEmptyCollectionContainer("<supply App Version here>")!
        let deviceIdContainer = NonEmptyCollectionContainer(deviceIdStr)!
        
        let receivers:BLEUExternalReceivers = BLEUExternalReceivers(bridgesUpdater: nil, //to listen to nearby bridges
                                                                    blePixelResolver: nil, //agent responsible for resolving pixel payload into pixel ID
                                                                    pixelsRSSIUpdater: nil, //to receive RSSI values updates per pixel
                                                                    resolvedPacketsInfoReceiver: nil) //to receive resolved pixel IDs
        
        let coordinatesContainer: any LocationCoordinatesContainer
        
        if let locService = self.locationService {
            coordinatesContainer = locService
        }
        else {
            let locService = LocationService()
            coordinatesContainer = WeakObject(locService)
            self.locationService = locService
        }
        
        
        
        let config:BLEUServiceConfiguration = BLEUServiceConfiguration(accountId: accountIdContainer,
                                                                       appVersion: appVersionContainer,
                                                                       endpoint: BLEUpstreamEndpoint.prod(),
                                                                       deviceId: deviceIdContainer,
                                                                       pacingEnabled: true,
                                                                       tagPayloadsLoggingEnabled: false,
                                                                       coordinatesContainer: coordinatesContainer,
                                                                       externalReceivers: receivers,
                                                                       externalLogger: nil)
        
        do {
            let upstreamService = try BLEUpstreamService(configuration: config)
            self.bleUpstreamService = upstreamService
            upstreamService.prepare(withToken: gatewayAuthToken)
            completion(nil)
        }
        catch {
            #if DEBUG
            print("BLEUpstream failed to prepare: \(error)")
            #endif
            completion(error)
        }
    }
    
    
    private func start() {
        _statusPublisher.send("Starting Connection..")
        startGateway()
    }

    // MARK: - PRIVATE
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
            prepare {[weak self] error in
                guard let weakModel = self else {
                    return
                }
                
                if let error = error {
                    
                }
                else {
                    weakModel.start()
                }
            }
        }
        
    }

    // MARK: -

    private func startGateway() {
        guard let upstreamService = self.bleUpstreamService else {
            return
        }
        
        do {
            try upstreamService.start()
        }
        catch {
            #if DEBUG
            print("Model Failed to start BLEUpstreamService: \(error)")
            #endif
        }
    }

}
