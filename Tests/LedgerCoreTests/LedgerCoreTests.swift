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

    /// 書き出した走査結果を読み戻すと、同じ木になる。
    @Test func archiveRoundTrip() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ledger-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("a/日本語"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 50_000).write(to: root.appendingPathComponent("a/日本語/x.bin"))
        let scanner = DiskScanner(options: .init(rootPath: root.path, includeVolumeSummary: false, threads: 2))
        scanner.run()
        let file = root.appendingPathComponent("tree.ledger")
        let volume = VolumeInfo(name: "HD", capacity: 10, available: 3, dataUsed: 5, systemUsed: 2)
        try scanner.tree.read { try TreeArchive.write($0, volume: volume, to: file) }
        let (loaded, v) = try TreeArchive.read(from: file)
        scanner.tree.read { t in
            #expect(loaded.count == t.count)
            #expect(loaded.size == t.size)
            #expect(loaded.firstChild == t.firstChild)
            #expect((0 ..< t.count).map(loaded.path) == (0 ..< t.count).map(t.path))
        }
        #expect(v?.dataUsed == 5 && v?.systemUsed == 2)
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

@Suite struct ClassificationTests {
    /// パスと容量の組から木を作る。途中のフォルダは自動で作る。
    func makeTree(_ files: [(String, UInt64)], extraRoot: [(String, UInt64)] = []) -> TreeStorage {
        final class Dir { var dirs: [String: Dir] = [:]; var files: [(String, UInt64)] = [] }
        let top = Dir()
        for (path, size) in files {
            var d = top
            let parts = path.split(separator: "/").map(String.init)
            for part in parts.dropLast() {
                if d.dirs[part] == nil { d.dirs[part] = Dir() }
                d = d.dirs[part]!
            }
            d.files.append((parts.last!, size))
        }
        var t = TreeStorage()
        t.appendNode(parent: 0, name: "Macintosh HD", size: 0, flags: .directory, modified: 0)
        var queue: [(Int, Dir)] = [(0, top)]
        while !queue.isEmpty {
            let (index, dir) = queue.removeFirst()
            let names = dir.dirs.keys.sorted()
            t.firstChild[index] = UInt32(t.count)
            t.childCount[index] = UInt32(names.count + dir.files.count + (index == 0 ? extraRoot.count : 0))
            for name in names {
                queue.append((t.count, dir.dirs[name]!))
                t.appendNode(parent: UInt32(index), name: name, size: 0, flags: .directory, modified: 0)
            }
            for (name, size) in dir.files {
                t.appendNode(parent: UInt32(index), name: name, size: size, flags: [], modified: 0)
                t.addSize(size, from: t.count - 1 == 0 ? 0 : index)
            }
            if index == 0 {
                for (name, size) in extraRoot {
                    t.appendNode(parent: 0, name: name, size: size, flags: .synthetic, modified: 0)
                    t.addSize(size, from: 0)
                }
            }
        }
        return t
    }

    @Test func groupsSystemDataByKind() throws {
        let t = makeTree([
            ("Users/a/Library/Caches/com.example/x", 100),
            ("Users/a/Library/Application Support/Foo/data.db", 50),
            ("Users/a/Library/Application Support/Foo/Code Cache/js", 30),
            ("Users/a/Library/Mail/V10/m", 999),
            ("Users/a/Library/Weird/thing", 3),
            ("usr/share/thing", 7),
            ("Users/a/Documents/report.pdf", 500),
            ("Users/a/.npm/_cacache/x", 20),
            ("Applications/App.app/bin", 400),
            ("private/var/folders/zz/abc/T/tmp", 40),
            ("System/Library/AssetsV2/model", 60),
        ], extraRoot: [("macOS 本体", 1000), ("その他", 80)])
        let c = Categories.classify(t)
        let sizes = Dictionary(uniqueKeysWithValues: c.groups.map { ($0.id, $0.size) })
        #expect(sizes["caches"] == 130)       // Code Cache はアプリの補助データから外してキャッシュに入れる
        #expect(sizes["app-data"] == 53)  // ~/Library の直下のよく知らないフォルダもアプリの補助データ
        #expect(sizes["dev-cache"] == 20)
        #expect(sizes["temporary"] == 40)
        #expect(sizes["macos-data"] == 60)
        #expect(sizes[Categories.snapshotsID] == 80)
        #expect(sizes[Categories.unclassifiedID] == 7)
        // メール、書類、アプリ、macOS 本体はシステムデータに数えない。
        #expect(c.total == 130 + 53 + 20 + 40 + 60 + 80 + 7)
        let unclassified = try #require(c.groups.first { $0.id == Categories.unclassifiedID })
        #expect(unclassified.nodes.map(t.name) == ["share"])
    }

    @Test func globMatching() {
        #expect(Glob.full(["Users", "*", "**", "Cache"][...], ["Users", "a", "x", "y", "Cache"][...]))
        #expect(Glob.full(["Users", "*", "**", "Cache"][...], ["Users", "a", "Cache"][...]))
        #expect(!Glob.full(["Users", "*", "Library"][...], ["Users", "a"][...]))
        #expect(Glob.canExtend(["Users", "*", "Library"][...], ["Users", "a"][...]))
        #expect(!Glob.canExtend(["Users", "*", "Library"][...], ["Users", "a", "Library"][...]))
        #expect(Glob.component("*.com.docker", "ABC.com.docker"))
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
