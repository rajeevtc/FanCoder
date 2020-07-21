//
//  FanBroadcastStatusCallback.swift
//  FanclubStreamerApp
//
//  Created by Rajeev TC on 2020/07/20.
//  Copyright © 2020 Hivelocity. All rights reserved.
//

import Foundation

protocol FanBroadcastStatusCallback: class {
    func onFanCoderStatus(status: FanBroadcastState)
    func onFanCoderError(error: Error)
}

enum FanBroadcastState {
    case idle
    case ready
    case broadcasting
}
