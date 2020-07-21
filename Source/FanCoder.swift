//
//  FanCoder.swift
//  FanclubStreamerApp
//
//  Created by Rajeev TC on 2020/07/20.
//  Copyright © 2020 Hivelocity. All rights reserved.
//

import UIKit
import HaishinKit
import AVFoundation
import VideoToolbox

public class FanCoder: NSObject {

    static let shared = FanCoder()
    private var rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream?
    private var sharedObject: RTMPSharedObject?

    private var cameraPosition: AVCaptureDevice.Position = .back
    private var serverStatusRTMPClosure: ((Timer) -> Void) = { _ in }
    private var serverStatusTimerRTMP: Timer?

    public var cameraView: UIView?
    public var broadcastURL: String?

    public weak var delegate: FanBroadcastStatusCallback?

    public func initializeCamera() {
        let session = AVAudioSession.sharedInstance()
        do {
            if #available(iOS 10.0, *) {
                try session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetooth])
            } else {
                session.perform(NSSelectorFromString("setCategory:withOptions:error:"), with: AVAudioSession.Category.playAndRecord, with: [
                    AVAudioSession.CategoryOptions.allowBluetooth,
                    AVAudioSession.CategoryOptions.defaultToSpeaker]
                )
                try session.setMode(.videoChat)
            }
            try AVAudioSession.sharedInstance().setPreferredSampleRate(48000)
            try session.setActive(true)
        } catch {
            print(error)
        }
    }

    public func prepareFanCoderSettings() {
           rtmpStream = RTMPStream(connection: rtmpConnection)
           rtmpStream?.orientation = .landscapeLeft
           rtmpStream?.captureSettings = [
               .fps: 30,
               .sessionPreset: AVCaptureSession.Preset.high, // input video width/height
               .continuousAutofocus: true, // use camera autofocus mode
               .continuousExposure: true //  use camera exposure mode
               // .isVideoMirrored: false,
               //.preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.auto
           ]

           rtmpStream?.audioSettings = [
               .muted: false, // mute audio
               //.actualBitrate: 192 * 1000,
               .bitrate: 192 * 1000,
               .sampleRate: 48000
           ]

           rtmpStream?.videoSettings = [
               .width: 1920, // video output width
               .height: 1080, // video output height
               .bitrate: 1200 * 1000, // video output bitrate
               .profileLevel: kVTProfileLevel_H264_Baseline_4_1, // H264 Profile require "import VideoToolbox"
               .maxKeyFrameIntervalDuration: 2 // key frame / sec
           ]

           // "0" means the same of input
           if #available(iOS 11.0, *) {
               rtmpStream?.recorderSettings = [
                   AVMediaType.audio: [
                       AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                       AVSampleRateKey: 0,
                       AVNumberOfChannelsKey: 2,
                       AVEncoderBitRateKey: 0,
                       AVEncoderAudioQualityKey: AVAudioQuality.max
                   ],
                   AVMediaType.video: [
                       AVVideoCodecKey: AVVideoCodecType.h264,
                       AVVideoHeightKey: 0,
                       AVVideoWidthKey: 0,
                       AVVideoQualityKey: 1.0
                       /*
                        AVVideoCompressionPropertiesKey: [
                        AVVideoMaxKeyFrameIntervalDurationKey: 2,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264Baseline30,
                        AVVideoAverageBitRateKey: 512000
                        ]
                        */
                   ]
               ]
           } else {
               // Fallback on earlier versions
           }

        rtmpStream?.attachAudio(AVCaptureDevice.default(for: AVMediaType.audio), automaticallyConfiguresApplicationAudioSession: false)

        rtmpStream?.attachCamera(DeviceUtil.device(withPosition: cameraPosition)) { _ in
            // print(error)
        }
    }

    public func startCameraView() {
        guard let view = cameraView else { return }
        let hkView = HKView(frame: view.bounds)
        hkView.videoGravity = AVLayerVideoGravity.resizeAspectFill
        hkView.attachStream(rtmpStream)

        // add ViewController#view
        view.addSubview(hkView)
        perform(#selector(communicateForServerRTMPStatus), with: self, afterDelay: 20.0)
    }

    public func publishStream(streamName: String) {
        rtmpStream?.publish(streamName)
    }

    @objc func communicateForServerRTMPStatus() {
        serverStatusRTMPClosure = { [weak self] _ in
            self?.connectToStream()
        }
        serverStatusTimerRTMP = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true, block: serverStatusRTMPClosure)
    }

    @objc func connectToStream() {
        guard let url = broadcastURL else { return }
        rtmpConnection.close()
        rtmpConnection.connect(url)
        rtmpConnection.addEventListener(Event.Name.rtmpStatus, selector: #selector(FanCoder.rtmpStatusHandler(_:)), observer: self)
    }

    public func switchCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        rtmpStream?.attachCamera(DeviceUtil.device(withPosition: cameraPosition)) { _ in
        }
    }

    public func dispose() {
        rtmpStream?.close()
        rtmpStream?.dispose()
        rtmpConnection.removeEventListener(Event.Name.rtmpStatus, selector: #selector(FanCoder.rtmpStatusHandler(_:)), observer: self)
    }
}

extension FanCoder {
    @objc func rtmpStatusHandler(_ notification: Notification) {
        let e: Event = Event.from(notification)
        if let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String {
            switch code {
            case RTMPConnection.Code.connectSuccess.rawValue:
                print(code)
                DispatchQueue.main.async { [weak self] in
                    self?.serverStatusTimerRTMP?.invalidate()
                    self?.delegate?.onFanCoderStatus(status: .ready)
                }
            case RTMPConnection.Code.connectFailed.rawValue, RTMPConnection.Code.connectClosed.rawValue:
                DispatchQueue.main.async { [weak self] in
                    let error = NSError(domain: "Error", code: 200, userInfo: nil)
                    self?.delegate?.onFanCoderError(error: error)
                }
                print(code)
            case RTMPStream.Code.publishStart.rawValue:
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.onFanCoderStatus(status: .broadcasting)
                }
            default:
                print(code)
            }
        }
    }
}
