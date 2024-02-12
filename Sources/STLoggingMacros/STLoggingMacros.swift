import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// A macro that appends to a log in the Shuttle Tracker unified logging system.
public struct LogMacro: ExpressionMacro {
	
	public static func expansion(
		of node: some FreestandingMacroExpansionSyntax,
		in context: some MacroExpansionContext
	) throws -> ExprSyntax {
		guard let system = node.argumentList.firstExpression(withLabel: .identifier("system")) else {
			throw ExpansionError.missingSystemArgument
		}
		let category = node.argumentList.firstExpression(withLabel: .identifier("category"))
		let level = node.argumentList.firstExpression(withLabel: .identifier("level"))
		let doUpload = node.argumentList.firstExpression(withLabel: .identifier("doUpload"))
		let message = node.argumentList.firstUnlabeledExpression().flatMap { (syntax) in
			return StringLiteralExprSyntax(syntax)
		}
		guard let message else {
			throw ExpansionError.missingMessageArgument
		}
		return try ExprSyntax(
			validating: ExprSyntax(
				FunctionCallExprSyntax(
					callee: MemberAccessExprSyntax(
						base: system,
						name: .identifier("withLogger")
					),
					trailingClosure: ClosureExprSyntax(
						signature: ClosureSignatureSyntax(
							parameterClause: .parameterClause(
								ClosureParameterClauseSyntax(
									parameters: ClosureParameterListSyntax {
										ClosureParameterSyntax(
											firstName: .identifier("logger")
										)
									}
								)
							)
						),
						statements: CodeBlockItemListSyntax {
							FunctionCallExprSyntax(
								callee: MemberAccessExprSyntax(
									base: DeclReferenceExprSyntax(
										baseName: .identifier("logger")
									),
									name: .identifier("log")
								)
							) {
								if let level {
									LabeledExprSyntax(
										label: "level",
										expression: level
									)
								}
								LabeledExprSyntax(
									expression: StringLiteralExprSyntax(
										openingQuote: .stringQuoteToken(),
										segments: StringLiteralSegmentListSyntax {
											StringSegmentSyntax(
												content: .stringSegment("[")
											)
											ExpressionSegmentSyntax {
												LabeledExprSyntax(
													expression: MacroExpansionExprSyntax(
														macroName: .identifier("fileID")
													) { }
												)
											}
											StringSegmentSyntax(
												content: .stringSegment(":")
											)
											ExpressionSegmentSyntax {
												LabeledExprSyntax(
													expression: MacroExpansionExprSyntax(
														macroName: .identifier("line")
													) { }
												)
											}
											StringSegmentSyntax(
												content: .stringSegment(" ")
											)
											ExpressionSegmentSyntax {
												LabeledExprSyntax(
													expression: MacroExpansionExprSyntax(
														macroName: .identifier("function")
													) { }
												)
												LabeledExprSyntax(
													label: "privacy",
													expression: MemberAccessExprSyntax(
														name: .identifier("public")
													)
												)
											}
											StringSegmentSyntax(
												content: .stringSegment("] ")
											)
											for segment in message.segments {
												segment
											}
										},
										closingQuote: .stringQuoteToken()
									)
								)
							}
						}
					)
				) {
					if let category {
						LabeledExprSyntax(
							label: "for",
							expression: category
						)
					}
					if let doUpload {
						LabeledExprSyntax(
							label: "doUpload",
							expression: doUpload
						)
					}
				}
			)
		)
	}
	
}

enum ExpansionError: LocalizedError {
	
	case missingSystemArgument
	
	case missingMessageArgument
	
	var errorDescription: String? {
		get {
			switch self {
			case .missingSystemArgument:
				return "Missing argument for parameter “system”."
			case .missingMessageArgument:
				return "Missing argument for parameter “message”."
			}
		}
	}
	
}

extension LabeledExprListSyntax {
	
	func firstExpression(withLabel labelKind: TokenKind) -> ExprSyntax? {
		return self.first { (syntax) in
			return .some(labelKind) ~= syntax.label?.tokenKind
		}?.expression
	}
	
	func firstUnlabeledExpression() -> ExprSyntax? {
		return self.first { (syntax) in
			return syntax.label == nil
		}?.expression
	}
	
}

@main
struct MacrosPlugin: CompilerPlugin {
	
	let providingMacros: [Macro.Type] = [
		LogMacro.self
	]
	
}
