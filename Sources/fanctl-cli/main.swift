import Foundation
import SMCKit

// Tiny verifier CLI. Read-only by default. The `set <i> <rpm>` and `auto <i>`
// subcommands will only succeed when run as root, since SMC writes are
// privileged. They exist here for end-to-end M3 testing — the production
// surface is the helper binary.

let args = CommandLine.arguments
let subcommand = args.count >= 2 ? args[1] : "status"

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("fanctl-cli: \(msg)\n".utf8))
    exit(1)
}

let smc: SMC
do {
    smc = try SMC()
} catch {
    die("Could not open AppleSMC: \(error)")
}
if ProcessInfo.processInfo.environment["FANCTL_DEBUG"] != nil {
    smc.debug = true
    FileHandle.standardError.write(Data("smc-debug: matched class \(smc.matchedClassName)\n".utf8))
}
if ProcessInfo.processInfo.environment["FANCTL_DIRECT"] != nil {
    smc.directSelectorMode = true
    FileHandle.standardError.write(Data("smc-debug: directSelectorMode=true\n".utf8))
}

let fans = FanController(smc: smc)

switch subcommand {
case "status":
    do {
        let count = try fans.fanCount()
        print("Fans: \(count)")
        for fan in try fans.readAllFans() {
            let badge = fan.mode == .auto ? "AUTO" : "MANUAL"
            print(String(
                format: "  F%d  cur=%6.0f  tgt=%6.0f  min=%6.0f  max=%6.0f  [%@]",
                fan.index, fan.current, fan.target, fan.min, fan.max, badge
            ))
        }
        print("")
        print("Top temperatures:")
        let temps = fans.discoverTemperatures().prefix(8)
        for t in temps {
            print(String(format: "  %@  %6.2f °C", "\(t.key)", t.celsius))
        }
    } catch {
        die("\(error)")
    }

case "raw":
    // `fanctl-cli raw F0Ac F0Mn TC0P ...`
    guard args.count >= 3 else { die("usage: raw <KEY> [KEY ...]") }
    for k in args.dropFirst(2) {
        guard k.utf8.count == 4 else { print("\(k): not a 4-char key"); continue }
        let key = SMCKey(String(k))
        do {
            let info = try smc.keyInfo(key)
            let value = try smc.read(key)
            print("\(key)  type=\(info.dataType)  size=\(info.dataSize)  value=\(value)")
        } catch {
            print("\(key)  ERR: \(error)")
        }
    }

case "set":
    // `sudo fanctl-cli set 0 4500`
    guard args.count == 4,
          let i = Int(args[2]),
          let rpm = Double(args[3]) else {
        die("usage: set <fanIndex> <rpm>")
    }
    do {
        try fans.setManual(i, rpm: rpm)
        print("Fan \(i) → MANUAL @ \(rpm) RPM")
    } catch {
        die("\(error) (writes need root)")
    }

case "auto":
    // `sudo fanctl-cli auto 0` or `sudo fanctl-cli auto all`
    guard args.count == 3 else { die("usage: auto <fanIndex|all>") }
    if args[2] == "all" {
        do { try fans.setAllAuto(); print("All fans → AUTO") }
        catch { die("\(error)") }
    } else if let i = Int(args[2]) {
        do { try fans.setAuto(i); print("Fan \(i) → AUTO") }
        catch { die("\(error) (writes need root)") }
    } else {
        die("usage: auto <fanIndex|all>")
    }

case "dump":
    // Walks every SMC key by index. Filter via grep, e.g. `fanctl-cli dump | grep ^F`.
    do {
        let total = try smc.totalKeyCount()
        FileHandle.standardError.write(Data("# total keys: \(total)\n".utf8))
        for i in 0..<total {
            guard let key = try? smc.keyAt(index: i) else { continue }
            let info = (try? smc.keyInfo(key)).map { "\($0.dataType) size=\($0.dataSize)" } ?? "?"
            print("\(key)  \(info)")
        }
    } catch {
        die("\(error)")
    }

case "watch":
    // Live status, refreshes every second. Ctrl-C to exit.
    while true {
        print("\u{1B}[2J\u{1B}[H", terminator: "")  // clear screen
        do {
            for fan in try fans.readAllFans() {
                let badge = fan.mode == .auto ? "AUTO" : "MANUAL"
                print(String(
                    format: "F%d  cur=%6.0f  tgt=%6.0f  [%@]",
                    fan.index, fan.current, fan.target, badge
                ))
            }
            print("---")
            for t in fans.discoverTemperatures().prefix(6) {
                print(String(format: "%@  %6.2f °C", "\(t.key)", t.celsius))
            }
        } catch {
            print("ERR: \(error)")
        }
        Thread.sleep(forTimeInterval: 1)
    }

default:
    print("""
    fanctl-cli — SMC verifier for FanCtl.app

    USAGE:
      fanctl-cli                 same as `status`
      fanctl-cli status          show fans + top temperatures
      fanctl-cli raw <KEY> ...   dump arbitrary SMC key(s)
      fanctl-cli watch           live refresh (Ctrl-C to quit)
      fanctl-cli set <i> <rpm>   manual mode (needs sudo)
      fanctl-cli auto <i|all>    back to macOS auto (needs sudo)
    """)
}
