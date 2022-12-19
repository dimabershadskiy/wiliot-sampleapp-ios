//
//  MotionAccelerationService.swift

import Foundation

import CoreMotion

extension AccelerationData {
    init(_ acc: CMAcceleration) {
        x = acc.x
        y = acc.y
        z = acc.z
    }

    var isEmpty: Bool {
        x == 0 && y == 0 && z == 0
    }
}

class MotionAccelerationService {

    var currentAcceleration: AccelerationData {
        return AccelerationData(acceleration)
    }

    private(set) var accelerationUpdateInterval: TimeInterval = 0.5

    private var acceleration: CMAcceleration = .init()
    private lazy var motionManager = CMMotionManager()
    private lazy var motionManagerOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.wiliot.MotionManagerQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // MARK: -
    init(accelerationUpdateInterval: TimeInterval? = 0.5) {
        if let interval = accelerationUpdateInterval {
            self.accelerationUpdateInterval = interval
        }
    }

    deinit {
        print("+ MotionAccelerationService Deinit+")
    }

    func startUpdates() throws {
        if !motionManager.isAccelerometerAvailable {
            throw ValueReadingError.missingRequiredValue("MotionAccelerationService accelerometer is not available")
        }

        if motionManager.isAccelerometerActive {
            throw ValueReadingError.invalidValue("MotionAccelerationService accelerometer is already active")
        }

        motionManager.accelerometerUpdateInterval = accelerationUpdateInterval

        motionManager.startAccelerometerUpdates(to: motionManagerOperationQueue) { [weak self] data, error in
            guard let self else {
                return
            }

            if let accError = error {
                print("Acceleration Data Error: \(accError)")
                return
            }

            self.acceleration = data?.acceleration ?? .init()
        }
    }

    func stopUpdates() {
        print("MotionAccelerationService stopAccelerometerUpdates")
        motionManager.stopAccelerometerUpdates()
    }
}
