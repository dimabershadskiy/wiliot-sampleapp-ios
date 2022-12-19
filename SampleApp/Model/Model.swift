import Foundation
import Combine

/// plist value reading key
private let kAPPTokenKey = "app_token"
/// plist value reading key
private let kOwnerIdKey = "owner_id"

@objc class Model: NSObject {

    lazy var permissions: Permissions = {

        let permissionsObj = Permissions()
        return permissionsObj
    }()

    var permissionsPublisher: AnyPublisher<Bool, Never> {
        _permissionsPublisher.eraseToAnyPublisher()
    }

    var statusPublisher: AnyPublisher<String, Never> {
        return _statusPublisher.eraseToAnyPublisher()
    }
    var connectionPublisher: AnyPublisher<Bool, Never> {
        return _mqttConnectionPublisher.eraseToAnyPublisher()
    }
    var bleActivityPublisher: AnyPublisher<Float, Never> {
        return _bleScannerPublisher.eraseToAnyPublisher()
    }
    var messageSentActionPubliosher: AnyPublisher<Void, Never> {
        return _mqttSentMessagePublisher.eraseToAnyPublisher()
    }

    private let _statusPublisher: CurrentValueSubject<String, Never> = .init("")
    private let _mqttConnectionPublisher: CurrentValueSubject<Bool, Never> = .init(false)
    private let _bleScannerPublisher: CurrentValueSubject<Float, Never> = .init(0.0)
    private let _permissionsPublisher: PassthroughSubject<Bool, Never> = .init()
    private let _mqttSentMessagePublisher: PassthroughSubject<Void, Never> = .init()

    private var appToken = ""
    private var ownerId = ""
    private var gatewayService: MobileGatewayService?
    private var bleService: BLEService?
    private var blePacketsmanager: BLEPacketsManager?
    private var networkService: NetworkService?
    private var permissionsCompletionCancellable: AnyCancellable?

    // MARK: -
    override init() {
        super.init()

        do {
            try tryReadRequiredUserData()
        } catch {
            _statusPublisher.send(error.localizedDescription)
        }
    }

    func prepare(completion: @escaping (() -> Void)) {
        if gatewayService == nil {

            let netService = NetworkService(appKey: appToken,
                                            ownerId: ownerId)

            let gwService = MobileGatewayService(ownerId: ownerId,
                                                 authTokenRequester: netService,
                                                 gatewayRegistrator: netService)

            gwService.didConnectCompletion = {[weak self] connected in
                self?._mqttConnectionPublisher.send(connected)
            }

            gwService.didStopCompletion = {[weak self] in
                self?._mqttConnectionPublisher.send(false)
            }

            gwService.authTokenCallback = {[weak self] optionalError in
                guard let self = self else {
                    return
                }

                if let error = optionalError {
                    self._statusPublisher.send(error.localizedDescription)
                    completion()
                    return
                }
                self._statusPublisher.send("Auth token received")

                completion()
            }

            self.gatewayService = gwService
            gwService.obtainAuthToken()
        }
    }

    func canStart() -> Bool {
        if permissions.gatewayPermissionsGranted && !appToken.isEmpty && !ownerId.isEmpty && self.gatewayService?.authToken != nil {
            return true
        }
        return false
    }

    func start() {
        _statusPublisher.send("Starting Connection and BLE scan")
        startGateway()
        startBLE()
    }

    // MARK: - PRIVATE
    private func tryReadRequiredUserData() throws {

        guard let plistPath = Bundle.main.path(forResource: "SampleAuthConstants", ofType: "plist"),
              let dataXML = FileManager.default.contents(atPath: plistPath)else {
            throw ValueReadingError.missingRequiredValue("No required data found in app Bundle")
        }

        do {
            var propertyListFormat =  PropertyListSerialization.PropertyListFormat.xml
            let anObject = try PropertyListSerialization.propertyList(from: dataXML, options: .mutableContainersAndLeaves, format: &propertyListFormat)

            guard let values = anObject as? [String: String] else {
                throw ValueReadingError.missingRequiredValue("Wrong Required Data format.")
            }

            guard let lvAppToken = values[kAPPTokenKey],
                  let lvOwnerId = values[kOwnerIdKey] else {
                throw ValueReadingError.missingRequiredValue("No APP Token or Owner ID")
            }

            appToken = lvAppToken
            ownerId = lvOwnerId
            _statusPublisher.send("plist values present")

        } catch let plistError {
            throw plistError
        }

    }

    func checkAndRequestSystemPermissions() {
        if !permissions.gatewayPermissionsGranted {

            self.permissionsCompletionCancellable =
            permissions.$gatewayPermissionsGranted
                .sink {[weak self] granted in
                    if let weakSelf = self {
                        weakSelf.permissionsCompletionCancellable = nil
                        weakSelf.handlePermissionsRequestsCompletion(granted)
                    }

                }

            permissions.requestLocationAuth()
            permissions.requestBluetoothAuth()
        } else {
            handlePermissionsRequestsCompletion(true)
        }
    }

    private func handlePermissionsRequestsCompletion(_ granted: Bool) {
        if !granted {
            _statusPublisher.send("No required BLE or Location permissions.")
        }
        _permissionsPublisher.send(granted)
    }

    // MARK: -

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

                _ = gatewayService.startConnection(withGatewayToken: accessToken)
            }

        }

        gatewayService.registerAsGateway(userAuthToken: authToken, ownerId: ownerId)

    }

    private func startBLE() {

        _bleScannerPublisher.send(0.0)
        let bleService = BLEService()
        self.bleService = bleService

        var pacingObject: PacketsPacing?

        if let gwService = self.gatewayService {
            let pacingService = PacketsPacingService(with: WeakObject(gwService))
            pacingObject = pacingService

            gwService.setSendEventSignal {[weak self] in
                self?._mqttSentMessagePublisher.send(())
            }
        }

        let bleManager = BLEPacketsManager(pacingReceiver: pacingObject)

        self.blePacketsmanager = bleManager
        bleManager.subscribeToBLEpacketsPublisher(publisher: bleService.packetPublisher)
        bleManager.start()

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
