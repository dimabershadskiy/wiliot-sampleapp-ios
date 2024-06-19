//
//  GatewayTagPacketsLogService.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 09.11.2022.
//

import Foundation
import WiliotCore


class BLEUTagPacketsPayloadsLogService {
    let logsSender: any TagPacketsPayloadLogSender
    let loggingTimeoutSeconds:Int
    
    private lazy var line1PayloadsAccumulator:[UUID: String] = [:]
    private lazy var line2PayloadsAccumulator:[UUID: String] = [:]
    private var isLine1:Bool = true
    
    private var currentAccumulator:[UUID:String] {
        isLine1 ? line1PayloadsAccumulator : line2PayloadsAccumulator
    }
    
    private var logsTimer:DispatchSourceTimer?
    private let logsTimerQueue = DispatchQueue(label: "com.wiliot.payloadLogsSender.Queue", qos:.utility)
    
    //MARK: - INIT
    init(logsSender: any TagPacketsPayloadLogSender, loggingTimeout:Int = 1) {
        //printDebug(" + GatewayTagPacketsLogService INIT -")
        self.logsSender = logsSender
        self.loggingTimeoutSeconds = loggingTimeout
        
        
    }
    
    deinit {
        //printDebug(" + GatewayTagPacketsLogService Deinit +")
        stopLogsTimer()
    }
    
   
    
    //MARK: -
    private func updateValues(from info: [UUID : String]) {
      
        info.forEach { (uid, payloadString) in
            if isLine1 {
                line1PayloadsAccumulator[uid] = payloadString
            }
            else {
                line2PayloadsAccumulator[uid] = payloadString
            }
        }
    }
    
    private func logsSendingEvent() {
        
        if line1PayloadsAccumulator.isEmpty && line2PayloadsAccumulator.isEmpty {
            return
        }
        
        let currentCource = currentAccumulator //prepare to use of current accumulator
       
        isLine1.toggle() //start acumulating payload packets to a different storage
        
        let values:[String] = currentCource.map({$0.value})
        
        //cleanup accumulator that is no more in use
        if isLine1 {
            line2PayloadsAccumulator.removeAll()
        }
        else {
            line1PayloadsAccumulator.removeAll()
        }
        
        //send data if any needed
        if let nonEmptyContainer = NonEmptyCollectionContainer(withArray: values) {
            logsSender.sendLogPayloads(nonEmptyContainer)
        }
        
    }
    
    private func startLogsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: logsTimerQueue)
        timer.schedule(deadline: .now() + .seconds(Int(loggingTimeoutSeconds)),
                       repeating: .seconds( Int(loggingTimeoutSeconds)),
                       leeway: .milliseconds(100))
        
        timer.setEventHandler(handler:{[weak self] in self?.logsSendingEvent() })
        self.logsTimer = timer
        timer.resume()
    }
    
    private func stopLogsTimer() {
        logsTimer?.setEventHandler(handler: {})
        logsTimer?.cancel()
        logsTimer = nil
    }
    
}

extension BLEUTagPacketsPayloadsLogService:TagPayloadByUUIDReceiver {
    
    func receiveTagPayloadsByUUID(_ pacingPackets: [UUID : String]) {
        self.updateValues(from: pacingPackets)
    }
    
    func startHandlingPayloads() {
        self.startLogsTimer()
    }
    
    func stopHandlihgPayloads() {
        self.stopLogsTimer()
    }
}
