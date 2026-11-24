import Charts
import SwiftUI
import SwiftData
import RealityKit
import MapKit
import UniformTypeIdentifiers


public let SectionBackground = Color(.white)

struct ContentView: View {
    
    @Environment(SerialService.self)
    private var serialService
    
    @State private var showingAlert = false
    
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    
    @State private var isExporting = false
    @State private var exportDocument = CSVDocument(text: "")
    
    let StatusTexts = ["Offline", "Idle", "Testing", "Armed", "Powered ascent", "Coasting", "Deployment", "Chuted descent", "Landed"]
    let StatusColors = [Color.red, .blue, .blue, .yellow, .green, .green, .green, .green, .green]
    
    var body: some View {
        ZStack {
            Color(red: 240/255, green: 240/255, blue: 240/255)
                .ignoresSafeArea()
    
            Group {
                VStack(alignment: .leading) {
                    HStack {
                        VStack {
                            RealityView { content in
                                if let modelEntity = try? await ModelEntity(named: "RocketModel") {
                                    modelEntity.name = "Rocket"
                                    modelEntity.position = [0, 0, -75]
                                
                                    
                                    content.add(modelEntity)
                                }
                                
                            } update: { content in
                                if let entity = content.entities.first(where: { $0.name == "Rocket" }) {
                                    let BaseRotation = simd_quatf(angle: .pi / -2, axis: [1, 0, 0])
                                    
                                    let RotationX = Float(serialService.currentData.Rotation_X) * .pi / 180
                                    let RotationY = Float(serialService.currentData.Rotation_Y) * .pi / 180
                                    let RotationZ = Float(serialService.currentData.Rotation_Z) * .pi / 180

                                    let QX = simd_quatf(angle: RotationX, axis: [1, 0, 0])
                                    let QY = simd_quatf(angle: RotationY, axis: [0, 1, 0])
                                    let QZ = simd_quatf(angle: RotationZ, axis: [0, 0, 1])

                                    entity.transform.rotation = BaseRotation * QX * QY * QZ
                                }
                            }
                            .aspectRatio(1/1, contentMode: .fit)
                            .padding(20)
                            .frame(width: 300)
                            .background {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(SectionBackground)
                            }
                            
                            VStack {
                                Spacer()
                                
                                HStack(alignment: .top) {
                                    VStack(alignment: .center) {
                                        Button("Reset sensors") {
                                            showingAlert = true
                                        }
                                        .frame(maxWidth: .infinity)
                                        .alert("Are you sure?", isPresented: $showingAlert) {
                                            Button("Reset", role: .destructive) {
                                                serialService.resetSensors()
                                            }
                                            Button("Cancel", role: .cancel) {}
                                        } message: {
                                            Text("This action will delete all unsaved data")
                                        }

                                        Button("Test comms") {
                                            serialService.sendCommand("test:start")
                                        }
                                            .frame(maxWidth: .infinity)
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    VStack(alignment: .center) {
                                        
                                        Button(serialService.currentData.Status > 1 ? "Disarm" : "Arm") {
                                            serialService.sendCommand(serialService.currentData.Status > 1 ? "Disarm" : "Arm")
                                        }
                                            .disabled(serialService.currentData.Status > 2)
                                            .frame(maxWidth: .infinity)
                                        
                                        Button("Launch") {
                                            serialService.sendCommand("Launch")
                                        }
                                            .disabled(serialService.currentData.Status > 2)
                                            .frame(maxWidth: .infinity)
                                        
                                        
                                        Button("Save CSV") {
                                            exportDocument = CSVDocument(
                                                text: serialService.GenerateCSV()
                                            )

                                            isExporting = true

                                        }
                                        .fileExporter(
                                            isPresented: $isExporting,
                                            document: exportDocument,
                                            contentType: .commaSeparatedText,
                                            defaultFilename: "Telemetry"
                                        ) { result in

                                            switch result {
                                            case .success(let url):
                                                print("Exported to: \(url)")

                                            case .failure(let error):
                                                print("Export failed: \(error)")
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                
                                Spacer()
                                
                                HStack() {
                                    Text("Status:")
                                    Text(StatusTexts[min(StatusTexts.count - 1, max(0, serialService.currentData.Status + 1))]).foregroundStyle(StatusColors[min(StatusColors.count - 1, max(0, serialService.currentData.Status + 1))])
                                }
                            }
                            .buttonStyle(FullWidthButtonStyle())
                            .controlSize(.regular)
                            .padding(20)
                            .frame(width: 300)
                            .background {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(SectionBackground)
                            }
                        }

                        VStack {
                            let AltitudeChartData = serialService.allData.map { point in ChartData(x: Double(point.Timestamp)/1000, y: point.Altitude)}
                            let VelocityYChartData = serialService.allData.map { point in ChartData(x: Double(point.Timestamp)/1000, y: point.Velocity_Y)}
                            
                            PrettyChart(Data: AltitudeChartData, Name: "Altitude", NameX: "Time")
                            PrettyChart(Data: VelocityYChartData, Name: "Velocity Y", NameX: "Time")
                        }
                        
                        VStack {
                            let AltitudeAccelerationY = serialService.allData.map { point in ChartData(x: Double(point.Timestamp)/1000, y: point.Acceleration_Y)}
                            
                            PrettyChart(Data: AltitudeAccelerationY, Name: "Acceleration Y", NameX: "Time")
                            
                            Map(position: $position) {
                                Marker("High Flyer", coordinate: CLLocationCoordinate2D(latitude: serialService.currentData.Latitude, longitude: serialService.currentData.Longitude))
                            }
                            .mapStyle(.standard)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        }
                            
                        
                    }
                    
                    HStack() {
                        ComponentInfo(Name: "Accelerometers", Working: true, Rows: [
                            ComponentInfoRow(Name: "Acc_X", Value: String(serialService.currentData.Acceleration_X) + "㎧", Red: false),
                            ComponentInfoRow(Name: "Acc_Y", Value: String(serialService.currentData.Acceleration_Y) + "㎧", Red: false),
                            ComponentInfoRow(Name: "Acc_Z", Value: String(serialService.currentData.Acceleration_Z) + "㎧", Red: false)
                        ])
                        
                        ComponentInfo(Name: "Barometer", Working: true, Rows: [
                            ComponentInfoRow(Name: "Temp", Value: String(serialService.currentData.Temperature) + "°C", Red: false),
                            ComponentInfoRow(Name: "Press", Value: String(serialService.currentData.Pressure) + "hPa", Red: false)
                        ])
                        
                        ComponentInfo(Name: "GPS", Working: true, Rows: [
                            ComponentInfoRow(Name: "Sat", Value: String(serialService.currentData.Satelites), Red: serialService.currentData.Satelites <= 3),
                            ComponentInfoRow(Name: "Longitude", Value: String(serialService.currentData.Longitude) + "N", Red: false),
                            ComponentInfoRow(Name: "Latitude", Value: String(serialService.currentData.Latitude) + "W", Red: false)
                        ])
                        
                        ComponentInfo(Name: "Radio", Working: true, Rows: [
                            ComponentInfoRow(Name: "Mode", Value: serialService.currentData.Status < 2 ? "Listening" : "Writing", Red: false),
                            ComponentInfoRow(Name: "Packet rate", Value: "120kbps", Red: true)
                        ])
                    }

                }
                .padding()
                .frame(
                    minWidth: 1200,
                    minHeight: 700
                )
            }
            
        }
        
    }
}



#Preview() {
    ContentView()
        .preferredColorScheme(.light)
        .environment(SerialService())
}

public struct ChartData:Identifiable {
    public let id = UUID()
    public let x:Double
    public let y:Double
    init(
        x:Double,
        y:Double
    )
    {
        self.x = x
        self.y = y
    }
}

public struct PrettyChart:View {
    public var Data:[ChartData]
    private var FilteredData: [ChartData] = []
    public var Name:String
    public var NameX:String
    public init(
        Data:[ChartData],
        Name:String,
        NameX:String,
    ) {
        self.Data = Data
        self.Name = Name
        self.NameX = NameX
        
        for point in Data {
            if let lastPoint = FilteredData.last {
                if point.x - lastPoint.x >= 0.05 {
                    FilteredData.append(point)
                }
            } else {
                FilteredData.append(point)
            }
        }
    }
    
    public var body:some View {

        
        Chart(FilteredData) {
            point in LineMark(
                x: .value(NameX, point.x),
                y: .value(Name, point.y)
            )
            .lineStyle(
                StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom(alpha: 1))
        }
        .chartXScale(
            domain: (Data.map(\.x).min() ?? 0)...(Data.map(\.x).max() ?? 1)
        )
        .chartXAxisLabel(NameX)
        .chartYAxisLabel(Name)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(SectionBackground)
        }
    }
}

public struct ComponentInfoRow:Identifiable {
    public let id = UUID()
    public var Name:String
    public var Value:String
    public var Red:Bool
}


public struct ComponentInfo:View {
    public var Name:String
    public var Working:Bool
    public var Rows:[ComponentInfoRow]
    
    public init(
        Name: String,
        Working:Bool,
        Rows:[ComponentInfoRow]
    ) {
        self.Name = Name
        self.Rows = Rows
        self.Working = Working
    }
    
    public var body:some View {
        VStack() {
            Text(Name).bold().font(.system(size: 18)).padding(.top, 20).padding(.horizontal, 20).padding(.bottom, 5)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(Rows) {
                        row in Text(row.Name + (row.Name == "" ? "" : ":"))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 15) {
                    ForEach(Rows) {
                        row in Text(row.Value).foregroundStyle(row.Red ? .red : .green)
                    }
                }
            }.padding(.bottom, 20).padding(.horizontal, 20)
            Spacer()
        }
        .frame(height: 150).frame(minWidth: 200)
        .background {
            RoundedRectangle(cornerRadius: 15)
            .fill(SectionBackground)
        }
    }
}


struct FullWidthButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Color.accentColor.opacity(
                    configuration.isPressed ? 0.6 : 1.0
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
