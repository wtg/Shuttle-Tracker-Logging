import Foundation
import STLogging

class ConfigurationProvider: LoggingConfigurationProvider, LogUploader {
	
	enum Category: String, LoggingCategory {
		
		case test
		
		static var `default`: Self = .test
		
	}
	
	let doUploadLogs = true
	
	var uploadedLogs: [LoggingSystem<Category>.Log] = []
	
	func upload(log: LoggingSystem<Category>.Log) async throws -> UUID {
		return UUID()
	}
	
}

@main
struct MacrosClient {
	
	static func main() async {
		let result = 42
		let configurationProvider = ConfigurationProvider()
		let loggingSystem = LoggingSystem(configurationProvider: configurationProvider, uploader: configurationProvider)
		#log(system: loggingSystem, level: .debug, doUpload: true, "Hello, world! The result is \(result, privacy: .private(mask: .hash)).")
	}
	
}
