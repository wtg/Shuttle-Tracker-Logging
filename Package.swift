// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
	name: "STLogging",
	platforms: [
		.iOS(.v15),
		.tvOS(.v15),
		.watchOS(.v8),
		.visionOS(.v1),
		.macOS(.v12),
		.macCatalyst(.v13)
	],
	products: [
		.library(
			name: "STLogging",
			targets: [
				"STLogging"
			]
		),
		.executable(
			name: "MacrosClient",
			targets: [
				"MacrosClient"
			]
		)
	],
	dependencies: [
		.package(
			url: "https://github.com/apple/swift-syntax.git",
			from: "509.0.0"
		)
	],
	targets: [
		.macro(
			name: "STLoggingMacros",
			dependencies: [
				.product(
					name: "SwiftSyntaxMacros",
					package: "swift-syntax"
				),
				.product(
					name: "SwiftCompilerPlugin",
					package: "swift-syntax"
				)
			]
		),
		.target(
			name: "STLogging",
			dependencies: [
				"STLoggingMacros"
			]
		),
		.executableTarget(
			name: "MacrosClient",
			dependencies: [
				"STLogging"
			]
		)
	]
)
