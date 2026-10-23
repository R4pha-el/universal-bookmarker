import Foundation

public enum ImportPolicy {
    public static let maximumSelectionCount = 20
    public static let maximumByteCount = 25 * 1_024 * 1_024

    public static func validate(selectionCount: Int) throws {
        guard selectionCount >= 0 else { throw BookmarkCoreError.invalidManifest("Invalid selection count.") }
        guard selectionCount <= maximumSelectionCount else {
            throw BookmarkCoreError.tooManyFiles(limit: maximumSelectionCount)
        }
    }

    public static func validate(byteCount: Int) throws {
        guard byteCount >= 0 else { throw BookmarkCoreError.invalidByteCount }
        guard byteCount <= maximumByteCount else { throw BookmarkCoreError.fileTooLarge(limit: maximumByteCount) }
    }
}
