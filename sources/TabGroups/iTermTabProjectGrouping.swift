//
//  iTermTabProjectGrouping.swift
//  iTerm2SharedARC
//
//  Pure logic behind auto-grouping tabs by project: turning a session's working
//  directory into a project root, and mapping that root onto a stable index into
//  the tab group color palette so a project keeps its color across launches.
//  Which tabs end up in which group is decided by PseudoTerminal (see
//  -autoGroupTabByProject:); nothing here knows about tabs.
//

import Foundation

@objc(iTermTabProjectGrouping)
class iTermTabProjectGrouping: NSObject {
    // Resolved roots keyed by the directory they were resolved from. Resolving is
    // only a handful of -fileExistsAtPath: calls, but a shell prompt can push a
    // working directory after every command, so each distinct directory walks at
    // most once. There is deliberately no invalidation: running `git init` in a
    // directory iTerm2 has already seen takes effect at the next launch.
    private static var cache = [String: String]()

    // The nearest ancestor of `path` (inclusive) that contains a .git entry, or
    // `path` itself when there is no repository above it. Returns nil unless the
    // path is absolute. Main thread only.
    @objc(projectRootForPath:)
    static func projectRoot(forPath path: String) -> String? {
        it_assert(Thread.isMainThread, "iTermTabProjectGrouping is main-thread only")
        guard path.hasPrefix("/") else {
            return nil
        }
        if let cached = cache[path] {
            return cached
        }
        let root = gitRoot(forDirectory: path) ?? path
        cache[path] = root
        return root
    }

    private static func gitRoot(forDirectory directory: String) -> String? {
        var candidate = directory
        while candidate.count > 1 && candidate.hasPrefix("/") {
            let dotGit = (candidate as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: dotGit) {
                return candidate
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return nil
    }

    // Whether auto-grouping may move a tab, given the user's opinion about its
    // group and how its project compares to the one it was last grouped for.
    // Split out of -[PseudoTerminal autoGroupTabByProject:] so the rule the
    // feature hinges on is stated once and unit-tested directly.
    //   - the user having moved, renamed or recolored this tab's group wins over
    //     anything the working directory says, forever;
    //   - an unknown project root means there is nothing to group by;
    //   - an unchanged project root means there is nothing to do, which matters
    //     because a shell pushes its directory after every command.
    @objc(shouldAutoGroupTabPinnedByUser:projectRoot:currentProjectRoot:)
    static func shouldAutoGroup(pinnedByUser: Bool,
                                projectRoot: String?,
                                currentProjectRoot: String?) -> Bool {
        if pinnedByUser {
            return false
        }
        guard let projectRoot else {
            return false
        }
        return projectRoot != currentProjectRoot
    }

    // Index into the tab group color palette for a project. This hashes the root
    // rather than counting existing groups (which is what a manually created
    // group does) so that the same project gets the same color in every window
    // and after a restart.
    @objc(colorIndexForProjectRoot:count:)
    static func colorIndex(forProjectRoot root: String, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        // FNV-1a. -[NSString hash] is not documented to be stable across OS
        // versions and this value is baked into what the user sees, so hash it
        // ourselves.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in root.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(count))
    }

    // Tests only. The cache has no invalidation in production.
    static func resetCacheForTesting() {
        cache = [:]
    }
}
