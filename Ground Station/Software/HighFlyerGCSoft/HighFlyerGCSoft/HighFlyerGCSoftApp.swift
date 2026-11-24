import SwiftUI
import SwiftData

@main
struct HighFlyerGCSoftApp: App {
    @State private var serialService = SerialService()
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        Window("Ground Control", id: "MainWindow") {
            Group {
                if(serialService.status == 2) {
                    ContentView()
                        .preferredColorScheme(.light) 
                        .environment(serialService)
                } else if(serialService.status == 1){
                    ContentUnavailableView(
                        "Connecting...",
                        systemImage: "cable.connector",
                        description: Text("Please wait for the device to establish connection")
                    )
                } else {
                    ContentUnavailableView(
                        "Ground station disconnected",
                        systemImage: "cable.connector",
                        description: Text("Connect the device to continue")
                    )
                }
            }
            .task {
                //openWindow(id: "DebugWindow")
                serialService.startScanning()
            }
        }.windowResizability(serialService.status == 2 ? .automatic : .contentMinSize)
        
        Window("Debug Window", id: "DebugWindow") {
            HStack {


                Button("Disconnect") {
                    serialService.disconnect()
                }
            }
        }
    }
}
