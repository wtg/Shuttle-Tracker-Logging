# Shuttle Tracker Logging
This is a Swift package that implements a client for the Shuttle Tracker unified logging system on Apple platforms.

## Usage
First, implement a configuration provider:
```swift
final class ConfigurationProvider: LoggingConfigurationProvider {
	enum Category: String, LoggingCategory {
		case general, network, location
		static var `default`: Self = .general
	}
	let doUploadLogs = true
	var uploadedLogs: [LoggingSystem<Category>.Log] = []
}
```
Note the nested `Category` enumeration, which specifies the available logging categories.

Next, add logic to upload logs to the remote server:
```swift
extension ConfigurationProvider: LogUploader {
	func upload(log: LoggingSystem<Category>.Log) async throws -> UUID {
		// Upload the log to the remote server and return the server-determined ID…
	}
}
```

Finally, use the `log(system:category:level:doUpload:_:)` macro to write to the logging system:
```swift
let result = 42
let configurationProvider = ConfigurationProvider()
let loggingSystem = LoggingSystem(configurationProvider: configurationProvider, uploader: configurationProvider)
#log(system: loggingSystem, level: .debug, "Hello, world! The result is \(42, privacy: .private(mask: .hash))")
```
