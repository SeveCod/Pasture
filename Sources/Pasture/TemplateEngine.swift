// Re-export PastureKit so all its public symbols (TemplateEngine, TemplateVariable,
// TokenEstimator, FilenameSanitizer, xmlEscapedAttribute) are available throughout
// the Pasture executable target without explicit imports in every file.
@_exported import PastureKit
