import FakeRFBServerKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()

var fixturePath = "TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex"
var requestedPort: UInt16 = 5901

var iterator = arguments.makeIterator()
while let argument = iterator.next() {
    switch argument {
    case "--fixture":
        if let value = iterator.next() {
            fixturePath = value
        }
    case "--port":
        if let value = iterator.next(), let port = UInt16(value) {
            requestedPort = port
        }
    default:
        break
    }
}

let fixtureURL = URL(fileURLWithPath: fixturePath)
let transcript = try FakeRFBTranscript.loadHexFile(at: fixtureURL)
let server = try FakeRFBServer(transcript: transcript, port: requestedPort)
let port = try server.start()

print("FakeRFBServer listening on 127.0.0.1:\(port)")
RunLoop.current.run()
