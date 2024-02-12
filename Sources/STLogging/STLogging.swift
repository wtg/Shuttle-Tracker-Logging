import OSLog
import SwiftUI

/// A macro that appends to a log in the Shuttle Tracker unified logging system.
@freestanding(expression)
public macro log<CategoryType>(
	system: LoggingSystem<CategoryType>,
	category: CategoryType = .default,
	level: OSLogType = .default,
	doUpload: Bool = false,
	_ message: OSLogMessage
) = #externalMacro(
	module: "STLoggingMacros",
	type: "LogMacro"
) where CategoryType: LoggingCategory

/// The Shuttle Tracker unified logging system.
///
/// The `CategoryType` generic type parameter specifies the type that determines the available log categories. Generally, this should be an enumeration with a separate case for each available category. One particular category should be set as the default through ``LoggingCategory/default``.
public final class LoggingSystem<CategoryType> where CategoryType: LoggingCategory {
	
	/// A representation of a log in the Shuttle Tracker unified logging system.
	public struct Log: Hashable, Identifiable, Sendable {
		
		public enum ClientPlatform: String, Codable, Sendable {
			
			case ios, tvos, watchos, visionos, macos
			
		}
		
		public fileprivate(set) var id: UUID
		
		/// The content of this log.
		public let content: String
		
		/// The client platform that generated this log.
		public let clientPlatform: ClientPlatform
		
		/// When this log was created.
		public let date: Date
		
		/// Creates a log.
		/// - Parameter content: The content of the log.
		public init(content: some StringProtocol) {
			self.id = UUID()
			self.content = String(content)
			#if os(iOS)
			self.clientPlatform = .ios
			#elseif os(tvOS) // os(iOS)
			self.clientPlatform = .tvos
			#elseif os(watchOS) // os(tvOS)
			self.clientPlatform = .watchos
			#elseif os(visionOS) // os(watchOS)
			self.clientPlatform = .visionos
			#elseif os(macOS) // os(visionOS)
			self.clientPlatform = .macos
			#endif // os(macOS)
			self.date = .now
		}
		
		/// Writes this log to disk.
		/// - Returns: The local file URL of the log.
		@available(iOS 16, tvOS 16, watchOS 9, visionOS 1, macOS 13, *)
		public func writeToDisk() throws -> URL {
			let url = FileManager.default.temporaryDirectory.appending(component: "\(self.id.uuidString).log")
			try self.content.write(to: url, atomically: false, encoding: .utf8)
			return url
		}
		
	}
	
	private let subsystem = "com.gerzer.shuttletracker"
	
	private var loggers: [CategoryType: Logger] = [:]
	
	private let configurationProvider: any LoggingConfigurationProvider<CategoryType>
	
	private let uploader: any LogUploader<CategoryType>
	
	/// Creates a logging system.
	/// - Parameters:
	///   - configurationProvider: A configuration provider that customizes the behavior of the logging system.
	///   - uploader: An instance that can upload logs to a remote server.
	public init(configurationProvider: some LoggingConfigurationProvider<CategoryType>, uploader: some LogUploader<CategoryType>) {
		self.configurationProvider = configurationProvider
		self.uploader = uploader
	}
	
	/// Provides a customized logger to a given closure and optionally uploads the current log store after invoking the closure.
	///
	/// The user-facing log-upload opt-out is honored even when `doUpload` is set to `true`.
	/// - Note: It’s generally easier and safer to use the ``log(system:category:level:doUpload:_:)`` macro instead of this method.
	/// - Warning: Don’t save or pass the provided logger outside the scope of the closure.
	/// - Important: The closure is synchronous, so don’t dispatch any asynchronous tasks in it because log items that are written in such a task might not be saved in time for the automatic upload operation.
	/// - Parameters:
	///   - category: The subsystem category to use to customize the logger.
	///   - doUpload: Whether to upload the current log store after invoking the closure.
	///   - body: The closure to which the logger is provided.
	public func withLogger(for category: CategoryType = .default, doUpload: Bool = false, _ body: (Logger) throws -> Void) rethrows {
		let logger = self.loggers[category] ?? { // Lazily create and cache category-specific loggers
			let logger = Logger(subsystem: self.subsystem, category: String(category.rawValue))
			self.loggers[category] = logger
			return logger
		}()
		try body(logger)
		Task {
			let optIn = await MainActor.run {
				return self.configurationProvider.doUploadLogs
			}
			if doUpload && optIn {
				do {
					try await self.uploadLog()
				} catch {
					self.withLogger { (logger) in // Leave doUpload set to false (the default) to avoid the potential for infinite recursion
						logger.log(level: .error, "[\(#fileID):\(#line) \(#function, privacy: .public)] Failed to upload log: \(error, privacy: .public)")
					}
				}
			}
		}
	}
	
	/// Uploads the current log store to the remote server.
	/// - Important: This method does _not_ check the user-facing opt-out.
	/// - Throws: When retrieving the current log store or performing the upload task fails.
	public func uploadLog() async throws {
		let predicate = NSPredicate(format: "subsystem == %@", argumentArray: [self.subsystem])
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .medium
		let content = try OSLogStore(scope: .currentProcessIdentifier)
			.getEntries(matching: predicate)
			.reduce(into: "") { (partialResult, entry) in
				let message = if let logEntry = entry as? OSLogEntryLog, logEntry.category != CategoryType.default.rawValue {
					"[\(logEntry.category)] \(logEntry.composedMessage)"
				} else {
					entry.composedMessage
				}
				partialResult += "[\(formatter.string(from: entry.date))] \(message)\n"
			}
			.dropLast() // Drop the trailing newline character
		var log = Log(content: content)
		log.id = try await self.uploader.upload(log: log) // The remote server is the authoritative source for log IDs, so we overwrite the local default ID with the one that the server returns.
		let immutableLog = log // A mutable log can’t be captured in a concurrent closure, so we need to make an immutable copy before hopping to the main actor.
		await MainActor.run {
			#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
			withAnimation {
				self.configurationProvider.uploadedLogs.append(immutableLog)
			}
			#elseif os(macOS) // os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
			self.configurationProvider.uploadedLogs.append(immutableLog)
			#endif // os(macOS)
		}
	}
	
}

/// A custom type that determines the available log categories. Generally, this should be an enumeration with a separate case for each available category. One particular category should be set as the default through ``default``.
public protocol LoggingCategory: Hashable, RawRepresentable where RawValue == String {
	
	/// The default category.
	static var `default`: Self { get }
	
}

/// A configuration provider that customizes the behavior of a logging system.
@MainActor
public protocol LoggingConfigurationProvider<CategoryType>: AnyObject {
	
	associatedtype CategoryType: LoggingCategory
	
	/// Whether the user has opted in to log uploads.
	var doUploadLogs: Bool { get }
	
	/// All of the logs that have been uploaded to the remote server since the last time the user cleared the log store.
	var uploadedLogs: [LoggingSystem<CategoryType>.Log] { get set }
	
}

/// A type that implements logic for uploading logs to a remote server.
public protocol LogUploader<CategoryType> {
	
	associatedtype CategoryType: LoggingCategory
	
	/// Uploads a log to the remote server.
	/// - Parameter log: The log to upload.
	/// - Returns: The server-determined ID of the uploaded log.
	/// - Throws: When the upload task fails.
	func upload(log: LoggingSystem<CategoryType>.Log) async throws -> UUID
	
}
