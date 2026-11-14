import Foundation
import Testing
@testable import LedgerCore

@Suite struct ScannerTests {
    /// 一時ディレクトリに決まった構成を作って読み、集計とハードリンクの扱いを確かめる。
    @Test func scansFolderAndCountsHardLinksOnce() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ledger-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("日本語"), withIntermediateDirectories: true)
        let big = Data(repeating: 1, count: 1_000_000)
        try big.write(to: root.appendingPathComponent("a/b/big.bin"))
        try Data(repeating: 2, count: 10).write(to: root.appendingPathComponent("日本語/小さい.txt"))
        try fm.linkItem(at: root.appendingPathComponent("a/b/big.bin"), to: root.appendingPathComponent("a/link.bin"))

        let scanner = DiskScanner(options: .init(rootPath: root.path, includeVolumeSummary: false, threads: 4))
        scanner.run()

        try scanner.tree.read { t in
            #expect(t.count == 7) // 根、a、日本語、b、link.bin、big.bin、小さい.txt
            let top = t.sortedChildren(0)
            #expect(top.map(t.name) == ["a", "日本語"])
            let a = top[0]
            // 1MB のファイルは一度だけ数える。
            #expect(t.size[a] >= 1_000_000 && t.size[a] < 1_100_000)
            #expect(t.size[0] == t.size[a] + t.size[top[1]])
            let linkCopies = t.children(a).filter { t.flags[$0].contains(.hardLinkDuplicate) }
                + t.children(t.children(a).first { t.name($0) == "b" }!).filter { t.flags[$0].contains(.hardLinkDuplicate) }
            #expect(linkCopies.count == 1)
            let small = try #require(t.children(top[1]).first)
            #expect(t.name(small) == "小さい.txt")
            #expect(t.path(small) == root.path + "/日本語/小さい.txt")
        }
        #expect(scanner.progress().finished)
    }

    @Test func marksUnreadableDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ledger-test-\(UUID().uuidString)")
        let locked = root.appendingPathComponent("locked")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 10).write(to: locked.appendingPathComponent("x"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? fm.removeItem(at: root)
        }
        let scanner = DiskScanner(options: .init(rootPath: root.path, includeVolumeSummary: false, threads: 2))
        scanner.run()
        scanner.tree.read { t in
            let child = t.children(0).first!
            #expect(t.flags[child].contains(.unreadable))
        }
        #expect(scanner.progress().unreadable == 1)
    }
}

@Suite struct LayoutTests {
    /// 根 100 の下に 60、30、0.05、残り 9.95 を置いた木を手で作る。
    func sampleTree() -> TreeStorage {
        var t = TreeStorage()
        t.appendNode(parent: 0, name: "root", size: 0, flags: .directory, modified: 0)
        t.firstChild[0] = 1
        t.childCount[0] = 4
        t.appendNode(parent: 0, name: "big", size: 0, flags: .directory, modified: 0)
        t.appendNode(parent: 0, name: "mid", size: 30, flags: [], modified: 0)
        t.appendNode(parent: 0, name: "tiny", size: 0, flags: [], modified: 0)
        t.appendNode(parent: 0, name: "rest", size: 9, flags: [], modified: 0)
        t.addSize(39, from: 0)
        t.firstChild[1] = 5
        t.childCount[1] = 2
        t.appendNode(parent: 1, name: "x", size: 60, flags: [], modified: 0)
        t.appendNode(parent: 1, name: "y", size: 1, flags: [], modified: 0)
        t.addSize(61, from: 1)
        return t
    }

    @Test func arcsFollowSizesAndGroupSmallItems() {
        let t = sampleTree()
        #expect(t.size[0] == 100)
        let arcs = SunburstLayout.arcs(in: t, center: 0, minAngle: 0.1)
        let depth1 = arcs.filter { $0.depth == 1 }
        #expect(depth1.map(\.node) == [1, 2, 4])
        #expect(abs(depth1[0].end - 2 * .pi * 0.61) < 1e-9)
        // y は 1/100 周で minAngle に届かず、まとめても届かないので描かない。
        let depth2 = arcs.filter { $0.depth == 2 }
        #expect(depth2.map(\.node) == [5])
        #expect(depth2[0].branch == depth1[0].branch)
        #expect(t.ancestry(5) == [0, 1, 5])
    }
}

@Suite struct PermissionTests {
    @Test func recognizesPromptingFolders() {
        let root = "/System/Volumes/Data"
        #expect(FullDiskAccess.prompts(path: root + "/Users/a/Desktop", scanRoot: root))
        #expect(FullDiskAccess.prompts(path: root + "/Users/a/Library/Containers", scanRoot: root))
        #expect(!FullDiskAccess.prompts(path: root + "/Users/a/Library/Caches", scanRoot: root))
        #expect(!FullDiskAccess.prompts(path: root + "/Applications", scanRoot: root))
    }

    /// システムとデータのボリュームが別々の使用量を返すこと（statfs ではどちらもコンテナ全体になる）。
    @Test func volumeUsageIsPerVolume() {
        let v = VolumeInfo.current()
        #expect(v.systemUsed > 1_000_000_000)
        #expect(v.systemUsed < v.dataUsed)
    }
}
