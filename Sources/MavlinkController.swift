//
//  MavlinkController.swift
//  MavlinkSwiftConnectDemo
//
//  Created by Michael Koukoullis on 5/10/2015.
//  Copyright © 2015 Michael Koukoullis. All rights reserved.
//

import Cocoa
import ORSSerial
import Mavlink

class MavlinkController: NSObject, ORSSerialPortDelegate, NSUserNotificationCenterDelegate {

    let serialPortManager = ORSSerialPortManager.sharedSerialPortManager()
	
    var serialPort: ORSSerialPort? {
        didSet {
            oldValue?.close()
            oldValue?.delegate = nil
            serialPort?.delegate = self
        }
    }
	
    @IBOutlet weak var openCloseButton: NSButton!
    @IBOutlet weak var clearTextViewButton: NSButton!
    @IBOutlet var receivedMessageTextView: NSTextView!
    
    override init() {
        super.init()
        
        let notificationCenter = NSNotificationCenter.defaultCenter()
        notificationCenter.addObserver(self, selector: "serialPortsWereConnected:", name: ORSSerialPortsWereConnectedNotification, object: nil)
        notificationCenter.addObserver(self, selector: "serialPortsWereDisconnected:", name: ORSSerialPortsWereDisconnectedNotification, object: nil)
        
        NSUserNotificationCenter.defaultUserNotificationCenter().delegate = self
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    // MARK: - Actions

    @IBAction func openOrClosePort(sender: AnyObject) {
        if let port = serialPort {
            if port.open {
                port.close()
            }
            else {
                self.clearTextView(self)
                
                // Configure port prior to opening
    			port.baudRate = 57600
    			port.numberOfStopBits = 1
    			port.parity = .None
                port.open()
                
                // Start a Mavlink session on the Pixhawk mini USB port
    			if let data = "mavlink start -d /dev/ttyACM0\n".dataUsingEncoding(NSUTF32LittleEndianStringEncoding) {
    				port.sendData(data)
    			}
            }
        }
    }
    
    @IBAction func clearTextView(sender: AnyObject) {
        self.receivedMessageTextView.textStorage?.mutableString.setString("")
    }

    // MARK: - ORSSerialPortDelegate Protocol

    func serialPortWasOpened(serialPort: ORSSerialPort) {
        self.openCloseButton.title = "Close"
    }
    
    func serialPortWasClosed(serialPort: ORSSerialPort) {
        self.openCloseButton.title = "Open"
    }
    
    func serialPortWasRemovedFromSystem(serialPort: ORSSerialPort) {
        self.serialPort = nil
        self.openCloseButton.title = "Open"
    }
    
    func serialPort(serialPort: ORSSerialPort, didReceiveData data: NSData) {
        var bytes = [UInt8](count: data.length, repeatedValue: 0)
		data.getBytes(&bytes, length: data.length)
        
        for byte in bytes {
            var message = mavlink_message_t()
            var status = mavlink_status_t()
            let channel = UInt8(mavlink_channel_t(MAVLINK_COMM_1.rawValue).rawValue)
            if mavlink_parse_char(channel, byte, &message, &status) != 0 {
                let messageDescription = self.descriptionForMavlinkMessage(message)
                self.receivedMessageTextView.textStorage?.mutableString.appendString(messageDescription)
    			self.receivedMessageTextView.needsDisplay = true
            }
        }
    }
    
    func serialPort(serialPort: ORSSerialPort, didEncounterError error: NSError) {
        print("SerialPort \(serialPort.name) encountered an error: \(error)")
    }
    
    // MARK: - Mavlink Message Decoding
    
    func descriptionForMavlinkMessage(var message: mavlink_message_t) -> String {
        var description: String
        switch message.msgid {
        case 0:
			var heartbeat = mavlink_heartbeat_t()
			mavlink_msg_heartbeat_decode(&message, &heartbeat);
            description = "HEARTBEAT mavlink_version: \(heartbeat.mavlink_version)"
        case 1:
            var sys_status = mavlink_sys_status_t()
            mavlink_msg_sys_status_decode(&message, &sys_status)
            description = "SYS_STATUS comms drop rate: \(sys_status.drop_rate_comm)%"
        case 30:
            var attitude = mavlink_attitude_t()
            mavlink_msg_attitude_decode(&message, &attitude)
            description = "ATTITUDE roll: \(attitude.roll) pitch: \(attitude.pitch) yaw: \(attitude.yaw)"
        case 32:
            description = "LOCAL_POSITION_NED"
        case 33:
            description = "GLOBAL_POSITION_INT"
        case 74:
            var vfr_hud = mavlink_vfr_hud_t()
            mavlink_msg_vfr_hud_decode(&message, &vfr_hud)
            description = "VFR_HUD heading: \(vfr_hud.heading) degrees"
        case 87:
            description = "POSITION_TARGET_GLOBAL_INT:"
        case 105:
            var highres_imu = mavlink_highres_imu_t()
            mavlink_msg_highres_imu_decode(&message, &highres_imu)
            description = "HIGHRES_IMU Pressure: \(highres_imu.abs_pressure) millibar"
        case 147:
            var battery_status = mavlink_battery_status_t()
            mavlink_msg_battery_status_decode(&message, &battery_status)
            description = "BATTERY_STATUS current consumed: \(battery_status.current_consumed) mAh"
        default:
            description = "OTHER Message id \(message.msgid) received"
        }
        
        return description + "\n"
    }
    
    // MARK: - Notifications
    
    func serialPortsWereConnected(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let connectedPorts = userInfo[ORSConnectedSerialPortsKey] as! [ORSSerialPort]
            print("Ports were connected: \(connectedPorts)")
            self.postUserNotificationForConnectedPorts(connectedPorts)
        }
    }
    
    func serialPortsWereDisconnected(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let disconnectedPorts: [ORSSerialPort] = userInfo[ORSDisconnectedSerialPortsKey] as! [ORSSerialPort]
            print("Ports were disconnected: \(disconnectedPorts)")
            self.postUserNotificationForDisconnectedPorts(disconnectedPorts)
        }
    }
    
    func postUserNotificationForConnectedPorts(connectedPorts: [ORSSerialPort]) {
        let unc = NSUserNotificationCenter.defaultUserNotificationCenter()
        for port in connectedPorts {
            let userNote = NSUserNotification()
            userNote.title = NSLocalizedString("Serial Port Connected", comment: "Serial Port Connected")
            userNote.informativeText = "Serial Port \(port.name) was connected to your Mac."
            userNote.soundName = nil;
            unc.deliverNotification(userNote)
        }
    }
    
    func postUserNotificationForDisconnectedPorts(disconnectedPorts: [ORSSerialPort]) {
        let unc = NSUserNotificationCenter.defaultUserNotificationCenter()
        for port in disconnectedPorts {
            let userNote = NSUserNotification()
            userNote.title = NSLocalizedString("Serial Port Disconnected", comment: "Serial Port Disconnected")
            userNote.informativeText = "Serial Port \(port.name) was disconnected from your Mac."
            userNote.soundName = nil;
            unc.deliverNotification(userNote)
        }
    }
    
    // MARK: - NSUserNotifcationCenterDelegate
    
    func userNotificationCenter(center: NSUserNotificationCenter, didDeliverNotification notification: NSUserNotification) {
        let popTime = dispatch_time(DISPATCH_TIME_NOW, Int64(3.0 * Double(NSEC_PER_SEC)))
        dispatch_after(popTime, dispatch_get_main_queue()) { () -> Void in
            center.removeDeliveredNotification(notification)
        }
    }
    
    func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
        return true
    }
}
