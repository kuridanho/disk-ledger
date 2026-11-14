import Foundation
import LedgerCore

// 使い方: ledger-scan [パス]
// パスを省くと起動ディスクのデータボリューム全体を読み、所要時間と大きい項目を出す。
//        ledger-scan --load <ファイル>
// アプリの --dump で書き出した走査結果を読み、分類の内訳を出す。
let arguments = CommandLine.arguments.dropFirst()
if arguments.first == "--load", let file = arguments.dropFirst().first {
    do {
        let (t, volume) = try TreeArchive.read(from: URL(fileURLWithPath: file))
        let rest = Array(arguments.dropFirst(2))
        if rest.first == "--du" {
            // 指定した場所の中を大きい順に出す。例: --du ~/Library/Application\ Support 2
            for path in rest.dropFirst() { ClassificationReport.listChildren(t, path: path) }
        } else {
            ClassificationReport.print(t, volume: volume)
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}
let options: DiskScanner.Options
if let path = arguments.first {
    options = DiskScanner.Options(rootPath: path, includeVolumeSummary: false)
} else {
    options = DiskScanner.Options()
}

let scanner = DiskScanner(options: options)
nonisolated func fmt(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

// 進み具合は別のキューから出すので、メインアクターに縛られない関数の中で組み立てる。
nonisolated func startTicker(_ scanner: DiskScanner) -> DispatchSourceTimer {
    let ticker = DispatchSource.makeTimerSource(queue: .global())
    ticker.schedule(deadline: .now() + 5, repeating: 5)
    ticker.setEventHandler {
    let p = scanner.progress()
    FileHandle.standardError.write("\(Int(p.elapsed))s \(p.files) files \(fmt(p.bytes)) \(p.currentPath)\n".data(using: .utf8)!)
}
    ticker.resume()
    return ticker
}
let ticker = startTicker(scanner)
scanner.run()
ticker.cancel()

let p = scanner.progress()
print(String(format: "所要 %.1f 秒、ファイル %d、フォルダ %d、読めなかったフォルダ %d", p.elapsed, p.files, p.directories, p.unreadable))
if let v = scanner.volume {
    print("容量 \(fmt(v.capacity))、空き \(fmt(v.available))、データ使用 \(fmt(v.dataUsed))、システム使用 \(fmt(v.systemUsed))")
}
let rss: UInt64 = {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? info.resident_size : 0
}()
print("メモリ \(fmt(rss))")

scanner.tree.read { t in
    print("全体 \(fmt(t.size[0])) ノード \(t.count)")
    func show(_ node: Int, depth: Int) {
        for child in t.sortedChildren(node).prefix(depth == 0 ? 12 : 5) {
            let mark = t.flags[child].contains(.unreadable) ? " (読めない)" : ""
            print(String(repeating: "  ", count: depth + 1) + "\(t.name(child))  \(fmt(t.size[child]))\(mark)")
            if depth < 1 { show(child, depth: depth + 1) }
        }
    }
    show(0, depth: 0)
}
