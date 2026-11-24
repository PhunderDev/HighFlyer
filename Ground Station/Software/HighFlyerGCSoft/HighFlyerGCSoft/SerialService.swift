import Foundation
import Observation
import Darwin
internal import Combine

@Observable
@MainActor
final class SerialService {
    
    var isConnected = false
    var status = 0 // -1 - Error, 0 - Disconnected, 1 - Connecting, 2 - Connected
    private var receivedData = ""
    private var lineBuffer = ""
    private var availablePorts: [String] = []
    private let baudRate = 115200
    
    private var groundpressure = 0
    
    var currentData = Telemetry()
    var allData:[Telemetry] = []
    var crashDataBatch:[Telemetry] = []
    
    @ObservationIgnored private var port: SerialPort?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    
    private let Storage = TelemetryStorage()

    init() {
        // Restore previous data
        allData = Storage.Load()
        print("Restored \(allData.count) measurements")
    }
    
    func startScanning() {
        guard scanTask == nil else { return }
        
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                
                refreshPorts()
                
                if !isConnected, port == nil,
                   let device = availablePorts.first {
                    print(device)
                    print("connecting", isConnected, port == nil)
                    connect(to: device)
                }
                
                do {
                    try await Task.sleep(
                        for: .seconds(2)
                    )
                } catch {
                    break
                }
            }
        }
    }
    
    func refreshPorts() {
        do {
            let devices = try FileManager.default.contentsOfDirectory(
                atPath: "/dev"
            )
            
            availablePorts = devices
                .filter {
                    $0.hasPrefix("cu.") &&
                    $0.localizedCaseInsensitiveContains("usb")
                }
                .sorted()
                .map { "/dev/" + $0 }
            
            
            if !isConnected && port == nil {
                status = availablePorts.isEmpty
                ? 0
                : 1
            }
        } catch {
            status = -1
        }
    }
    
    
    func connect(to path: String) {
        guard port == nil else { return }
        
        status = 1
        
        let newPort = SerialPort(
            path: path,
            baudRate: baudRate,
            onConnected: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isConnected = true
                    self.status = 2
                }
            },
            onText: { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    
                    self.receivedData += text
                    self.lineBuffer += text
                    
                    let lines = self.lineBuffer.components(separatedBy: "\n")
                    
                    self.lineBuffer = lines.last ?? ""
                    
                    for rawLine in lines.dropLast() {
                        let line = rawLine.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        
                        guard !line.isEmpty else { continue }
                        
                        self.processSerialLine(line)
                    }
                }
            },
            
            onDisconnected: { [weak self] reason in
                print("Serial disconnected: \(reason)")
                
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    
                    self.port = nil
                    self.isConnected = false
                    self.status = -1
                }
            }
            
        )
        
        port = newPort
        newPort.start()
    }
    
    func processSerialLine(_ line: String) {
        
        let values = line.split(separator: ",")
        
        for (index, value) in values.enumerated() {
            
            switch index {
            case 0:
                currentData.Timestamp = Int(value) ?? -1
                
            case 1:
                currentData.Status = Int(value) ?? 0
                
            case 2:
                let components = Int(value) ?? 1
                currentData.Connection_Accelerometer = (components % 2 == 0)
                currentData.Connection_Barometer = (components % 3 == 0)
                currentData.Connection_Radio = (components % 5 == 0)
                currentData.Connection_GPS = (components % 7 == 0)
                
            case 3:
                currentData.Acceleration_X = (Double(value) ?? 0)/1000
                
            case 4:
                currentData.Acceleration_Y = (Double(value) ?? 0)/1000
                
            case 5:
                currentData.Acceleration_Z = (Double(value) ?? 0)/1000
                
            case 6:
                currentData.AngularVelocity_X = (Double(value) ?? 0)/1000
                
            case 7:
                currentData.AngularVelocity_Y = (Double(value) ?? 0)/1000
                
            case 8:
                currentData.AngularVelocity_Z = (Double(value) ?? 0)/1000
                
            case 9:
                currentData.Pressure = Int(value) ?? 0
                if(groundpressure == 0) { groundpressure = currentData.Pressure }
                
            case 10:
                currentData.Temperature = Double(value) ?? 0
                
            case 11:
                currentData.Satelites = Int(value) ?? 0
                
            case 12:
                currentData.Latitude = (Double(value) ?? 0)/1000
                
            case 13:
                currentData.Longitude = (Double(value) ?? 0)/1000
                
            default:
                break
            }
            
        }
        
        if (allData.count > 0) {
            currentData.Velocity_X = allData[allData.count - 1].Velocity_X + (Double(currentData.Timestamp - allData[allData.count - 1].Timestamp)/1000 * currentData.Acceleration_X)
            
            currentData.Velocity_Y = allData[allData.count - 1].Velocity_Y + (Double(currentData.Timestamp - allData[allData.count - 1].Timestamp)/1000 * currentData.Acceleration_Y)
            
            currentData.Velocity_Z = allData[allData.count - 1].Velocity_Z + (Double(currentData.Timestamp - allData[allData.count - 1].Timestamp)/1000 * currentData.Acceleration_Z)
            
            currentData.Rotation_X = allData[allData.count - 1].Rotation_X + (Double(currentData.Timestamp - allData[allData.count - 1].Timestamp)/1000 * currentData.AngularVelocity_X)
            
            currentData.Rotation_Y = allData[allData.count - 1].Rotation_Y + (Double(currentData.Timestamp - allData[allData.count - 1].Timestamp)/1000 * currentData.AngularVelocity_Y)
            
            currentData.Rotation_Z = allData[allData.count - 1].Rotation_Z + (Double(currentData.Timestamp - allData[allData.count - 1].Timestamp)/1000 * currentData.AngularVelocity_Z)
            
            print(currentData.Rotation_X, currentData.Rotation_Y, currentData.Rotation_Z)
        }
        
        if(groundpressure != 0) {
            currentData.Altitude = 287.058/9.80665*(currentData.Temperature + 273.15)*log(Double(currentData.Pressure)/Double(groundpressure))
        }
        
        allData.append(currentData)
        crashDataBatch.append(currentData)
        
        // Save the last 20 every 20th packet
        if(crashDataBatch.count == 20 || (allData.count > 0 && allData[allData.count - 1].Status == 7)) {
            Storage.Save(crashDataBatch)
            crashDataBatch = []
        }
    }
    
    func sendCommand(_ command: String) {
        guard isConnected, let port else {
            print("Cannot send: Arduino is not connected")
            return
        }
        
        port.send(command)
    }
    
    
    func disconnect() {
        port?.stop()
        port = nil
        isConnected = false
        status = 0
    }
    
    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        disconnect()
    }
    
    func resetSensors() {
        currentData.Velocity_X = 0
        currentData.Velocity_Y = 0
        currentData.Velocity_Z = 0
        currentData.Rotation_X = 0
        currentData.Rotation_Y = 0
        currentData.Rotation_Z = 0
        groundpressure = currentData.Pressure
        currentData.Altitude = 0
        allData = []
    }
    
    func GenerateCSV() -> String {

        var csv = """
        Timestamp,Status,Connection_Accelerometer,Connection_Barometer,Connection_Radio,Connection_GPS,Acceleration_X,Acceleration_Y,Acceleration_Z,AngularVelocity_X,AngularVelocity_Y,AngularVelocity_Z,Pressure,Temperature,Satelites,Latitude,Longitude,Velocity_X,Velocity_Y,Velocity_Z,Rotation_X,Rotation_Y,Rotation_Z,Altitude
        """

        for point in allData {
            
            let row = [
                "\(point.Timestamp)",
                "\(point.Status)",
                "\(point.Connection_Accelerometer ? 1 : 0)",
                "\(point.Connection_Barometer ? 1 : 0)",
                "\(point.Connection_Radio ? 1 : 0)",
                "\(point.Connection_GPS ? 1 : 0)",
                "\(point.Acceleration_X)",
                "\(point.Acceleration_Y)",
                "\(point.Acceleration_Z)",
                "\(point.AngularVelocity_X)",
                "\(point.AngularVelocity_Y)",
                "\(point.AngularVelocity_Z)",
                "\(point.Pressure)",
                "\(point.Temperature)",
                "\(point.Satelites)",
                "\(point.Latitude)",
                "\(point.Longitude)",
                "\(point.Velocity_X)",
                "\(point.Velocity_Y)",
                "\(point.Velocity_Z)",
                "\(point.Rotation_X)",
                "\(point.Rotation_Y)",
                "\(point.Rotation_Z)",
                "\(point.Altitude)"
            ].joined(separator: ",")

            csv += "\n" + row
        }

        return csv
    }
}

struct Telemetry:Codable {
    public var Timestamp:Int = 0
    
    public var Status:Int = -1
    
    // Reported Data
    public var Connection_Accelerometer:Bool = false
    public var Connection_Barometer:Bool = false
    public var Connection_Radio:Bool = false
    public var Connection_GPS:Bool = false
    
    public var Acceleration_X:Double = 0.0
    public var Acceleration_Y:Double = 0.0
    public var Acceleration_Z:Double = 0.0
    
    public var AngularVelocity_X:Double = 0.0
    public var AngularVelocity_Y:Double = 0.0
    public var AngularVelocity_Z:Double = 0.0
    
    public var Pressure:Int = 0
    public var Temperature:Double = 0.0
    
    public var Satelites:Int = 0
    public var Latitude:Double = 0.0
    public var Longitude:Double = 0.0
    
    // Derived Data
    
    public var Velocity_X:Double = 0.0
    public var Velocity_Y:Double = 0.0
    public var Velocity_Z:Double = 0.0
    
    public var Rotation_X:Double = 0.0
    public var Rotation_Y:Double = 0.0
    public var Rotation_Z:Double = 0.0
    
    public var Altitude:Double = 0.0
}












private final class SerialPort: @unchecked Sendable {
    private let path: String
    private let baudRate: Int
    private let queue = DispatchQueue(label: "ArduinoSerialPort")

    private let onConnected: @Sendable () -> Void
    private let onText: @Sendable (String) -> Void
    private let onDisconnected: @Sendable (String) -> Void

    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?

    init(
        path: String,
        baudRate: Int,
        onConnected: @escaping @Sendable () -> Void,
        onText: @escaping @Sendable (String) -> Void,
        onDisconnected: @escaping @Sendable (String) -> Void
    ) {
        self.path = path
        self.baudRate = baudRate
        self.onConnected = onConnected
        self.onText = onText
        self.onDisconnected = onDisconnected
    }

    func start() {
        queue.async { [self] in
            openPort()
        }
    }

    func stop() {
        queue.async { [self] in
            closePort()
        }
    }

    private func openPort() {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)

        guard fd >= 0 else {
            let code = errno
            let message = String(cString: strerror(code))

            print("Failed to open: \(path)")
            print("errno: \(code), reason: \(message)")

            onDisconnected("Could not open \(path): \(message)")
            return
        }

        var settings = termios()

        guard tcgetattr(fd, &settings) == 0 else {
            Darwin.close(fd)
            onDisconnected("Could not configure \(path)")
            return
        }

        cfmakeraw(&settings)

        let speed: speed_t
        switch baudRate {
        case 9600:   speed = speed_t(B9600)
        case 19200:  speed = speed_t(B19200)
        case 38400:  speed = speed_t(B38400)
        case 57600:  speed = speed_t(B57600)
        case 115200: speed = speed_t(B115200)
        default:
            Darwin.close(fd)
            onDisconnected("Unsupported baud rate: \(baudRate)")
            return
        }

        guard cfsetispeed(&settings, speed) == 0,
              cfsetospeed(&settings, speed) == 0 else {
            Darwin.close(fd)
            onDisconnected("Could not set baud rate")
            return
        }

        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(CSIZE)
        settings.c_cflag |= tcflag_t(CS8)
        settings.c_cflag &= ~tcflag_t(PARENB)
        settings.c_cflag &= ~tcflag_t(CSTOPB)

        guard tcsetattr(fd, TCSANOW, &settings) == 0 else {
            Darwin.close(fd)
            onDisconnected("Could not apply serial settings")
            return
        }

        fileDescriptor = fd

        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readAvailableData()
        }

        source.setCancelHandler {
            Darwin.close(fd)
        }

        readSource = source
        source.resume()
        onConnected()
    }

    private func readAvailableData() {
        guard fileDescriptor >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)

        let count = buffer.withUnsafeMutableBytes { bytes in
            Darwin.read(fileDescriptor, bytes.baseAddress, bytes.count)
        }

        if count > 0 {
            let text = String(decoding: buffer.prefix(count), as: UTF8.self)
            onText(text)
        } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
            closePort()
            onDisconnected("Serial connection lost")
        } else if count == 0 {
            closePort()
            onDisconnected("Serial connection closed")
        }
    }
    
    func send(_ text: String) {
        queue.async { [self] in
            guard fileDescriptor >= 0 else {
                print("Cannot send: serial port is not connected")
                return
            }

            let data = Array(text.utf8) + [UInt8(10)] // Append newline
            var offset = 0

            while offset < data.count {
                let written = data.withUnsafeBytes { bytes in
                    Darwin.write(
                        fileDescriptor,
                        bytes.baseAddress!.advanced(by: offset),
                        data.count - offset
                    )
                }

                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    print("Serial write failed: \(String(cString: strerror(errno)))")
                    return
                }
            }
        }
    }

    private func closePort() {
        guard fileDescriptor >= 0 else { return }

        fileDescriptor = -1
        let source = readSource
        readSource = nil

        source?.cancel()

        // The dispatch source's cancellation handler closes the descriptor.
    }
}
