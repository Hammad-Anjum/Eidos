import Foundation

/// Turns platform / framework errors into messages a person can
/// actually read. Falls back to `localizedDescription` when we don't
/// have a specific mapping — but the common paths get friendly text.
enum UserFacingError {

    static func message(for error: Error) -> String {
        // Gemma / MLX
        if let gemma = error as? GemmaError {
            return gemma.errorDescription ?? "The model hit an error."
        }
        if let memError = error as? MemoryManagerError {
            return memError.errorDescription ?? "Something went wrong with memory."
        }
        if let crystalError = error as? MemoryCrystallizerError {
            return crystalError.errorDescription ?? "Couldn't distill this conversation."
        }
        if let hfError = error as? HuggingFaceError {
            return hfError.errorDescription ?? "Download failed."
        }
        if let calError = error as? CalendarError {
            return calError.errorDescription ?? "Calendar access denied."
        }

        // POSIX — most commonly "Operation not permitted" from sandbox denial.
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == 1 {
            return "Eidos can't access that file — check Settings → Privacy."
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == 257 {
            return "Eidos doesn't have permission to open that file."
        }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet:
                return "You're offline. Model download needs a connection."
            case NSURLErrorTimedOut:
                return "The network timed out. Try again on a stronger connection."
            case NSURLErrorCancelled:
                return "Request was cancelled."
            default:
                return "Network error: \(ns.localizedDescription)"
            }
        }

        // Fallback — at least trim the noise.
        let raw = error.localizedDescription
        // Trim Cocoa's "The operation couldn't be completed." preamble.
        let boilerplate = "The operation couldn't be completed."
        if raw.hasPrefix(boilerplate) {
            let trimmed = raw
                .replacingOccurrences(of: boilerplate, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " (:)"))
            return trimmed.isEmpty ? "Something went wrong." : trimmed
        }
        return raw
    }
}
