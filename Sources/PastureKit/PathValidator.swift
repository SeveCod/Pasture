import Foundation

public enum PathValidator {

    public static func isInside(target: URL, base: URL) -> Bool {
        let targetPath = target.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path
        return targetPath == basePath || targetPath.hasPrefix(basePath + "/")
    }
}
